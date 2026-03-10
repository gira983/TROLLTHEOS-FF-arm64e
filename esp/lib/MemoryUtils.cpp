#import "MemoryUtils.h"

mach_port_t get_task = MACH_PORT_NULL;
pid_t Processpid = 0;

pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    int err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);
    if (err == -1) return -1;

    struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
    if (!procBuffer) return -1;

    err = sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0);
    if (err == -1) { free(procBuffer); return -1; }

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

// processor_set_tasks — менее детектируемо чем task_for_pid
static mach_port_t GetTaskViaProcessorSet(pid_t targetPid) {
    host_t host = mach_host_self();
    processor_set_name_t psDefault;
    if (processor_set_default(host, &psDefault) != KERN_SUCCESS)
        return MACH_PORT_NULL;

    processor_set_t psPriv;
    if (host_processor_set_priv(host, psDefault, &psPriv) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

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
        pid_for_task(tasks[i], &pid);
        if (pid == targetPid) {
            result = tasks[i];
        } else {
            mach_port_deallocate(mach_task_self(), tasks[i]);
        }
    }
    vm_deallocate(mach_task_self(), (vm_address_t)tasks, taskCount * sizeof(task_t));
    mach_port_deallocate(mach_task_self(), psPriv);
    mach_port_deallocate(mach_task_self(), psDefault);
    return result;
}

vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid == -1) return 0;
    Processpid = pid;

    // Get task port
    get_task = GetTaskViaProcessorSet(pid);
    if (get_task == MACH_PORT_NULL)
        task_for_pid(mach_task_self(), pid, &get_task);
    if (get_task == MACH_PORT_NULL) return 0;

    // Walk VM regions looking for the main executable (freefireth binary)
    // Use proc_regionfilename to identify which region belongs to the game binary
    vm_map_offset_t addr = 0;
    vm_map_size_t   size = 0;
    uint32_t        depth = 0;
    struct vm_region_submap_info_64 info;
    mach_msg_type_number_t count = VM_REGION_SUBMAP_INFO_COUNT_64;

    char path[MAXPATHLEN];
    vm_map_offset_t best = 0;

    while (1) {
        kern_return_t kr = mach_vm_region_recurse(get_task, &addr, &size, &depth,
                                                   (vm_region_recurse_info_t)&info, &count);
        if (kr != KERN_SUCCESS) break;

        if (info.is_submap) { depth++; addr++; continue; }

        // Check if this region is the game executable
        int len = proc_regionfilename((int)pid, addr, path, sizeof(path));
        if (len > 0) {
            // freefireth binary contains "freefireth" in path
            if (strstr(path, "freefireth") && !strstr(path, "framework") && !strstr(path, "Framework")) {
                // Only take first (lowest) executable region — the __TEXT segment
                if (best == 0 || addr < best) {
                    best = addr;
                }
                // Once we found it and moved past it, stop
                // (the binary's __TEXT is contiguous)
            }
        }

        addr += size;
        count = VM_REGION_SUBMAP_INFO_COUNT_64;
        depth = 0;
    }

    if (best != 0) {
        NSLog(@"[FRYZZ] Found freefireth base via regionfilename: 0x%llx", (unsigned long long)best);
        return best;
    }

    // Fallback: return first region as before
    addr = 0; size = 0; depth = 0; count = VM_REGION_SUBMAP_INFO_COUNT_64;
    kern_return_t kr = mach_vm_region_recurse(get_task, &addr, &size, &depth,
                                               (vm_region_recurse_info_t)&info, &count);
    if (kr == KERN_SUCCESS) {
        NSLog(@"[FRYZZ] Fallback base: 0x%llx", (unsigned long long)addr);
        return addr;
    }
    return 0;
}

bool _read(long addr, void *buffer, int len) {
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;
    vm_size_t size = 0;
    kern_return_t error = vm_read_overwrite(get_task, (vm_address_t)addr, len, (vm_address_t)buffer, &size);
    return (error == KERN_SUCCESS && size == (vm_size_t)len);
}

bool _write(long addr, const void *buffer, int len) {
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;

    vm_address_t region = (vm_address_t)addr;
    vm_size_t rsize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(get_task, &region, &rsize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &infoCnt, &obj);
    if (kr != KERN_SUCCESS) return false;
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize)
        return false;

    kr = vm_write(get_task, (vm_address_t)addr, (vm_offset_t)buffer, (mach_msg_type_number_t)len);
    return kr == KERN_SUCCESS;
}
