#import "MemoryUtils.h"

// Глобальный task port игрового процесса
mach_port_t get_task = MACH_PORT_NULL;
pid_t Processpid = 0;

// Получить PID по имени процесса через sysctl
pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);

    struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
    if (!procBuffer) return -1;

    if (sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0) == -1) {
        free(procBuffer);
        return -1;
    }

    int count = (int)length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        if (strstr(procBuffer[i].kp_proc.p_comm, GameProcessName)) {
            pid_t pid = procBuffer[i].kp_proc.p_pid;
            free(procBuffer);
            return pid;
        }
    }
    free(procBuffer);
    return -1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Port Stash Retrieval
//
// Схема (из workaround.md):
//   HUD (root) → processor_set_tasks → task port игры
//   HUD → mach_ports_register(app_task, [game_task], 1)   ← kernel сам переносит right
//   App → mach_ports_lookup(mach_task_self(), ...)         ← забираем port
//
// Вся «опасная» работа происходит в HUD процессе (root).
// Основной app не вызывает task_for_pid — античит не видит ничего.
// ─────────────────────────────────────────────────────────────────────────────

#define NOTIFY_PORT_REQUEST  "ch.xxtou.notification.port.request"
#define NOTIFY_PORT_READY    "ch.xxtou.notification.port.ready"
#define PORT_REQUEST_FILE    "/var/mobile/Library/Caches/fryzz_port_req.txt"

// Запросить task port у HUD процесса через file-based IPC + Darwin notifications
// HUD слушает NOTIFY_PORT_REQUEST, выполняет processor_set_tasks,
// стэшит port через mach_ports_register, сигналит NOTIFY_PORT_READY
static mach_port_t RequestPortFromHUD(pid_t targetPid) {
    // Записываем запрос: targetPid + наш PID
    pid_t myPid = getpid();
    char req[64];
    snprintf(req, sizeof(req), "%d %d", (int)targetPid, (int)myPid);
    FILE *f = fopen(PORT_REQUEST_FILE, "w");
    if (!f) return MACH_PORT_NULL;
    fputs(req, f);
    fclose(f);

    // Регистрируем ожидание ответа ПЕРЕД сигналом запроса
    __block int readyToken = 0;
    __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    notify_register_dispatch(NOTIFY_PORT_READY, &readyToken, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(int t) {
        notify_cancel(t);
        dispatch_semaphore_signal(sem);
    });

    // Сигналим HUD
    notify_post(NOTIFY_PORT_REQUEST);

    // Ждём ответа максимум 5 секунд
    int timedOut = dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));
    if (timedOut) {
        notify_cancel(readyToken);
        return MACH_PORT_NULL;
    }

    // Забираем стэшнутый port из нашего registered ports array
    mach_port_array_t ports = NULL;
    mach_msg_type_number_t portsCount = 0;
    kern_return_t kr = mach_ports_lookup(mach_task_self(), &ports, &portsCount);
    if (kr != KERN_SUCCESS || portsCount == 0 || ports == NULL)
        return MACH_PORT_NULL;

    mach_port_t result = ports[0];

    // Освобождаем массив (но НЕ сам port — он нам нужен)
    vm_deallocate(mach_task_self(), (vm_address_t)ports, portsCount * sizeof(mach_port_t));

    return result;
}

vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    vm_map_offset_t vmoffset = 0;
    vm_map_size_t vmsize = 0;
    uint32_t nesting_depth = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = 16;

    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid == -1) return 0;
    Processpid = pid;

    // Запрашиваем port у HUD (root процесс) через port stashing
    // Никакого task_for_pid в основном процессе — античит не детектирует
    get_task = RequestPortFromHUD(pid);

    if (get_task != MACH_PORT_NULL) {
        kern_return_t kr = mach_vm_region_recurse(get_task, &vmoffset, &vmsize,
            &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        if (kr == KERN_SUCCESS) {
            return vmoffset;
        }
        mach_port_deallocate(mach_task_self(), get_task);
        get_task = MACH_PORT_NULL;
    }

    return 0;
}

bool _read(long addr, void *buffer, int len)
{
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;
    vm_size_t size = 0;
    kern_return_t error = vm_read_overwrite(get_task, (vm_address_t)addr, len, (vm_address_t)buffer, &size);
    return (error == KERN_SUCCESS && size == (vm_size_t)len);
}

bool _write(long addr, const void *buffer, int len)
{
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;

    vm_address_t region = (vm_address_t)addr;
    vm_size_t    rsize  = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(get_task, &region, &rsize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &infoCnt, &obj);
    if (kr != KERN_SUCCESS) return false;
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize)
        return false;

    kr = vm_write(get_task,
                  (vm_address_t)addr,
                  (vm_offset_t)buffer,
                  (mach_msg_type_number_t)len);
    return kr == KERN_SUCCESS;
}
