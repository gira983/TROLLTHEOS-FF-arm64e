#import "MemoryUtils.h"

// Глобальный task port игрового процесса (инициализируется в GetGameModule_Base)
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

// Получить task port через processor_set_tasks — не детектируется как task_for_pid
// Требует entitlement: com.apple.system-task-ports (уже в ent.plist)
static mach_port_t GetTaskViaProcessorSet(pid_t targetPid) {
    host_t host = mach_host_self();

    // Получаем default processor set
    processor_set_name_t psDefault;
    if (processor_set_default(host, &psDefault) != KERN_SUCCESS)
        return MACH_PORT_NULL;

    // Получаем привилегированный порт processor set
    processor_set_t psPriv;
    if (host_processor_set_priv(host, psDefault, &psPriv) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

    // Получаем список всех tasks в системе
    task_array_t tasks;
    mach_msg_type_number_t taskCount = 0;
    if (processor_set_tasks(psPriv, &tasks, &taskCount) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psPriv);
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < taskCount; i++) {
        pid_t pid = -1;
        pid_for_task(tasks[i], &pid);  // обратный lookup — менее подозрительно
        if (pid == targetPid) {
            result = tasks[i];
        } else {
            // Освобождаем все task ports кроме нашего
            mach_port_deallocate(mach_task_self(), tasks[i]);
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)tasks, taskCount * sizeof(task_t));
    mach_port_deallocate(mach_task_self(), psPriv);
    mach_port_deallocate(mach_task_self(), psDefault);

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

    // processor_set_tasks — не детектируется античитом как task_for_pid
    // task_for_pid убран — детектируется Free Fire античитом
    get_task = GetTaskViaProcessorSet(pid);

    if (get_task != MACH_PORT_NULL) {
        kern_return_t kr = mach_vm_region_recurse(get_task, &vmoffset, &vmsize,
            &nesting_depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
        if (kr == KERN_SUCCESS) {
            return vmoffset;
        }
    }

    return 0;
}

bool _read(long addr, void *buffer, int len)
{
    if (!isVaildPtr(addr)) return false;
    vm_size_t size = 0;
    kern_return_t error = vm_read_overwrite(get_task, (vm_address_t)addr, len, (vm_address_t)buffer, &size);
    if(error != KERN_SUCCESS || size != len)
    {
        return false;
    }
    return true;
}

bool _write(long addr, const void *buffer, int len)
{
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;

    // Проверяем что регион существует и доступен для записи
    // vm_protect временно делает страницу writable если нужно
    vm_address_t region = (vm_address_t)addr;
    vm_size_t    rsize  = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(get_task, &region, &rsize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &infoCnt, &obj);
    if (kr != KERN_SUCCESS) return false;  // регион не существует — не пишем
    // addr должен попасть в найденный регион
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize)
        return false;

    kr = vm_write(get_task,
                  (vm_address_t)addr,
                  (vm_offset_t)buffer,
                  (mach_msg_type_number_t)len);
    return kr == KERN_SUCCESS;
}


// Сканирование памяти чужого процесса по значению — аналог h5gg.searchNumber
// Читает память кусками по 1MB, ищет паттерн с шагом patSize (выравненный поиск)
int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults) {
    if (get_task == MACH_PORT_NULL || patSize == 0 || !outAddrs || maxResults <= 0)
        return 0;

    const size_t CHUNK = 0x100000; // 1MB
    uint8_t *buf = (uint8_t *)malloc(CHUNK);
    if (!buf) return 0;

    int found = 0;
    for (uint64_t addr = rangeStart; addr < rangeEnd && found < maxResults; addr += CHUNK) {
        vm_size_t actualRead = 0;
        kern_return_t kr = vm_read_overwrite(get_task,
                                             (vm_address_t)addr,
                                             (vm_size_t)CHUNK,
                                             (vm_address_t)buf,
                                             &actualRead);
        if (kr != KERN_SUCCESS || actualRead < patSize) continue;

        // Выравненный поиск по patSize (как h5gg I32/I64 search)
        for (vm_size_t i = 0; i + patSize <= actualRead; i += patSize) {
            if (memcmp(buf + i, pattern, patSize) == 0) {
                outAddrs[found++] = addr + i;
                if (found >= maxResults) break;
            }
        }
    }
    free(buf);
    return found;
}
