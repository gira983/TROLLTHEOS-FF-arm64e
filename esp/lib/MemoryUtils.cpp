#import "MemoryUtils.h"
#include <mach/mach.h>
#include <mach/processor_set.h>

// ── Глобальные ────────────────────────────────────────────────────────
mach_port_t get_task = MACH_PORT_NULL;
pid_t       Processpid = 0;

// ── PID через sysctl (не детектируется — стандартный способ) ──────────
pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    sysctl((int *)name, (sizeof(name)/sizeof(*name))-1, NULL, &length, NULL, 0);

    struct kinfo_proc *buf = (struct kinfo_proc *)malloc(length);
    if (!buf) return -1;

    if (sysctl((int *)name, (sizeof(name)/sizeof(*name))-1, buf, &length, NULL, 0) == -1) {
        free(buf); return -1;
    }

    int count = (int)(length / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        if (strstr(buf[i].kp_proc.p_comm, GameProcessName)) {
            pid_t pid = buf[i].kp_proc.p_pid;
            free(buf);
            return pid;
        }
    }
    free(buf);
    return -1;
}

// ── Получение task через processor_set_tasks (НЕ task_for_pid) ────────
// processor_set_tasks возвращает task порты всех процессов через
// host_processor_set_priv — это kernel-level доступ, anti-cheat его не мониторит
static mach_port_t GetTaskViaProcessorSet(pid_t target_pid) {
    mach_port_t host = mach_host_self();
    mach_port_t host_priv = MACH_PORT_NULL;

    // host_get_special_port(4) = HOST_PRIV_PORT — доступен в TrollStore
    kern_return_t kr = host_get_special_port(host, HOST_LOCAL_NODE, 4, &host_priv);
    if (kr != KERN_SUCCESS || host_priv == MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), host);
        return MACH_PORT_NULL;
    }

    // Получаем default processor set
    processor_set_name_t ps_name = MACH_PORT_NULL;
    kr = processor_set_default(host, &ps_name);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), host_priv);
        mach_port_deallocate(mach_task_self(), host);
        return MACH_PORT_NULL;
    }

    // Получаем привилегированный порт processor set
    processor_set_t ps_priv = MACH_PORT_NULL;
    kr = host_processor_set_priv(host_priv, ps_name, &ps_priv);
    mach_port_deallocate(mach_task_self(), ps_name);
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), host_priv);
        mach_port_deallocate(mach_task_self(), host);
        return MACH_PORT_NULL;
    }

    // Получаем список task портов всех процессов в processor set
    task_array_t tasks = nullptr;
    mach_msg_type_number_t task_count = 0;
    kr = processor_set_tasks(ps_priv, &tasks, &task_count);
    mach_port_deallocate(mach_task_self(), ps_priv);
    mach_port_deallocate(mach_task_self(), host_priv);
    mach_port_deallocate(mach_task_self(), host);
    if (kr != KERN_SUCCESS || !tasks) return MACH_PORT_NULL;

    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < task_count; i++) {
        pid_t pid = 0;
        if (pid_for_task(tasks[i], &pid) == KERN_SUCCESS && pid == target_pid) {
            result = tasks[i];
            // Не деаллоцируем — это наш порт
            // Остальные деаллоцируем
            for (mach_msg_type_number_t j = 0; j < task_count; j++) {
                if (j != i) mach_port_deallocate(mach_task_self(), tasks[j]);
            }
            break;
        } else {
            mach_port_deallocate(mach_task_self(), tasks[i]);
        }
    }
    vm_deallocate(mach_task_self(), (vm_address_t)tasks,
                  task_count * sizeof(task_t));
    return result;
}

// ── GetGameModule_Base — ищет task без task_for_pid ───────────────────
vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid == -1) return 0;

    Processpid = pid;

    // 1) Пробуем processor_set_tasks — основной метод
    mach_port_t task = GetTaskViaProcessorSet(pid);

    // 2) Fallback: task_for_pid (если вдруг processor_set не сработал)
    if (task == MACH_PORT_NULL) {
        task_for_pid(mach_task_self(), pid, &task);
    }

    if (task == MACH_PORT_NULL) return 0;
    get_task = task;

    // Ищем базовый адрес модуля
    vm_map_offset_t vmoffset = 0;
    vm_map_size_t   vmsize   = 0;
    uint32_t        depth    = 0;
    struct vm_region_submap_info_64 info;
    mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;

    kern_return_t kr = mach_vm_region_recurse(get_task, &vmoffset, &vmsize,
                                               &depth, (vm_region_recurse_info_t)&info,
                                               &info_count);
    if (kr == KERN_SUCCESS) return vmoffset;
    return 0;
}

// ── Read / Write — через vm_read_overwrite / vm_write ─────────────────
bool _read(long addr, void *buffer, int len) {
    if (!isVaildPtr(addr)) return false;
    vm_size_t out = 0;
    kern_return_t kr = vm_read_overwrite(get_task, (vm_address_t)addr,
                                          len, (vm_address_t)buffer, &out);
    return (kr == KERN_SUCCESS && (int)out == len);
}

bool _write(long addr, const void *buffer, int len) {
    if (!isVaildPtr(addr)) return false;

    // Проверяем что регион writable перед записью
    vm_address_t    region_addr = (vm_address_t)addr;
    vm_size_t       region_size = 0;
    vm_region_basic_info_data_64_t region_info;
    mach_msg_type_number_t info_cnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj_name = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(get_task, &region_addr, &region_size,
                                     VM_REGION_BASIC_INFO_64,
                                     (vm_region_info_t)&region_info,
                                     &info_cnt, &obj_name);
    if (kr != KERN_SUCCESS) return false;

    kern_return_t wkr = vm_write(get_task, (vm_address_t)addr,
                                  (vm_offset_t)buffer,
                                  (mach_msg_type_number_t)len);
    return (wkr == KERN_SUCCESS);
}

// ── Сканирование памяти по значению (аналог h5gg searchNumber) ────────
// Читает память кусками по 1MB, ищет паттерн с выравниванием по patSize
int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults) {
    if (get_task == MACH_PORT_NULL || patSize == 0 || !outAddrs || maxResults <= 0)
        return 0;

    const size_t CHUNK = 0x100000; // 1MB кусками
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

        // Выравненный поиск — как h5gg I32/I64 search
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
