/*
 * KFDMemory.mm
 * Интеграция libkfd для получения task порта игры через kernel exploit.
 *
 * Поток работы:
 *  1. KFDInit()         — kopen() → получаем kernel r/w
 *  2. KFDAcquireTaskPort() — идём по allproc, находим freefireth proc,
 *                            берём proc->task->itk_sself (mach port)
 *  3. get_task подменяется на найденный порт
 *  4. Далее vm_read/vm_write работают как обычно
 *
 * При любой ошибке — graceful fallback на Method1_ProcessorSetTasks.
 */

#include "KFDMemory.h"

// libkfd — header-only library, включаем один раз здесь
// CONFIG_ASSERT/PRINT/TIMER = 0 по умолчанию (задано через #ifndef в libkfd.h)
#include "libkfd.h"

#include <sys/sysctl.h>
#include <mach/mach.h>
#include <pthread.h>

// ─────────────────────────────────────────────────────────────────────────────
// Глобальное состояние
// ─────────────────────────────────────────────────────────────────────────────
KFDStatus g_kfdStatus = kKFDStatusNotStarted;
uint64_t  g_kfdHandle = 0;

// ─────────────────────────────────────────────────────────────────────────────
// Вспомогательные структуры XNU (нужны для поиска task port через kernel)
// ─────────────────────────────────────────────────────────────────────────────

// Из XNU: osfmk/ipc/ipc_port.h
// ipc_port.ip_kobject содержит указатель на task_t
// Нам нужен не vm_map, а сам mach port — ищем itk_sself у task
// task offset layout (arm64, iOS 16.x):
//   proc + 0x730 = task (current_task)
//   task + 0x0028 = vm_map
//   task + 0x0108 = itk_sself (send right на сам task — это и есть task port)
// Офсет itk_sself стабилен для iOS 16.x
#define TASK_ITK_SSELF_OFFSET  0x0108

// proc__object_size из dynamic_info — 0x730 для iOS 16.x
#define PROC_OBJECT_SIZE       0x0730
// task__map offset — 0x0028
#define TASK_MAP_OFFSET        0x0028

// ─────────────────────────────────────────────────────────────────────────────
// Проверка поддерживаемой версии iOS (только то что есть в dynamic_info.h)
// ─────────────────────────────────────────────────────────────────────────────
static bool IsKFDSupported(void) {
    char kern_version[512] = {};
    size_t size = sizeof(kern_version);
    if (sysctlbyname("kern.version", kern_version, &size, NULL, 0) != 0)
        return false;

    // Проверяем что версия есть в таблице libkfd
    const u64 count = sizeof(kern_versions) / sizeof(kern_versions[0]);
    for (u64 i = 0; i < count; i++) {
        const char *kv = kern_versions[i].kern_version;
        if (kv && strcmp(kv, "todo") != 0 &&
            strncmp(kern_version, kv, strlen(kv)) == 0) {
            return true;
        }
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDInit — открываем kernel file descriptor
// ─────────────────────────────────────────────────────────────────────────────
bool KFDInit(KFDPuafMethod method) {
    if (g_kfdStatus == kKFDStatusSuccess) return true;
    // Не блокируем повторный запуск после Failed/Unsupported —
    // пользователь мог переключить метод (например с smith на landa)
    // kKFDStatusRunning блокируем чтобы не запускать параллельно
    if (g_kfdStatus == kKFDStatusRunning)  return false;

    // Сбрасываем предыдущий провал — новый метод может сработать
    g_kfdStatus = kKFDStatusRunning;
    g_kfdHandle = 0;

    // Проверяем поддержку текущей iOS
    if (!IsKFDSupported()) {
        g_kfdStatus = kKFDStatusUnsupported;
        return false;
    }

    // Выбираем kread/kwrite методы:
    // kread_sem_open + kwrite_sem_open — работает на всех поддерживаемых iOS 16.x
    // kread_kqueue_workloop_ctl — только на некоторых (см. kread_kqueue_workloop_ctl_supported)
    u64 kread_method  = kread_sem_open;
    u64 kwrite_method = kwrite_sem_open;

    @try {
        // 64 страницы — меньше риск OOM, достаточно для наших целей
        g_kfdHandle = kopen(64, (u64)method, kread_method, kwrite_method);
        if (g_kfdHandle != 0) {
            g_kfdStatus = kKFDStatusSuccess;
            return true;
        }
    } @catch (NSException *e) {
        // ObjC исключение
        (void)e;
    } @catch (...) {
        // C++ исключение
    }
    // kopen вернул 0 или выбросил — считаем провалом без ребута

    g_kfdStatus = kKFDStatusFailed;
    g_kfdHandle = 0;
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDInitAsync — запускает kopen на отдельном потоке
// Если SIGSEGV — процесс упадёт, но это произойдёт ДО старта HUD
// поэтому лаунчер просто покажет ошибку а HUD не запустится
// ─────────────────────────────────────────────────────────────────────────────
void KFDInitAsync(KFDPuafMethod method, KFDInitCompletion completion) {
    // Таймаут 12 сек — smith зависает на iOS 16.6+
    // Используем pthread чтобы можно было его отменить по таймауту
    const double kTimeoutSeconds = 12.0;

    __block bool finished = false;
    __block bool timedOutFlag = false;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    // Запускаем на отдельном pthread (не dispatch) чтобы можно было cancel
    __block pthread_t kfd_thread = NULL;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    // Блок для передачи в pthread
    KFDPuafMethod capturedMethod = method;
    dispatch_semaphore_t capturedSem = sem;

    // Используем dispatch для простоты — но добавляем проверку таймаута снаружи
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0), ^{
        bool result = KFDInit(capturedMethod);
        finished = true;
        dispatch_semaphore_signal(capturedSem);
        // Вызываем completion только если не был таймаут
        if (!timedOutFlag && completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }
    });

    pthread_attr_destroy(&attr);

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(kTimeoutSeconds * NSEC_PER_SEC));
    long timedOut = dispatch_semaphore_wait(sem, deadline);
    if (timedOut != 0 && !finished) {
        timedOutFlag = true;
        g_kfdStatus = kKFDStatusFailed;
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(false); });
        }
        // Фоновый поток продолжит работу но его результат будет проигнорирован
        // Через usleep(500) в grab_free_pages он завершится сам через несколько секунд
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDAcquireTaskPort — находим proc целевого процесса через allproc в ядре
// и извлекаем его task port
// ─────────────────────────────────────────────────────────────────────────────
mach_port_t KFDAcquireTaskPort(pid_t targetPid) {
    if (g_kfdStatus != kKFDStatusSuccess || g_kfdHandle == 0)
        return MACH_PORT_NULL;

    struct kfd *kfd = (struct kfd *)g_kfdHandle;
    if (!kfd->info.kaddr.current_proc) return MACH_PORT_NULL;

    // Ищем proc целевого процесса по allproc начиная от current_proc
    // Идём по le_prev (назад к kernel_proc), максимум 1024 шага
    u64 proc_kaddr = kfd->info.kaddr.current_proc;
    u64 target_proc = 0;

    for (int iter = 0; iter < 1024; iter++) {
        i32 pid = 0;
        kread(g_kfdHandle, proc_kaddr + dynamic_info(proc__p_pid), &pid, sizeof(pid));

        if (pid == targetPid) {
            target_proc = proc_kaddr;
            break;
        }

        u64 next = 0;
        kread(g_kfdHandle, proc_kaddr + dynamic_info(proc__p_list__le_prev), &next, sizeof(next));
        next = UNSIGN_PTR(next);
        if (!next || next == proc_kaddr) break;
        proc_kaddr = next;
    }

    if (!target_proc) return MACH_PORT_NULL;

    // Нашли proc игры — получаем task port через pid_iterate
    // pid_iterate не требует com.apple.system-task-ports и работает в любом процессе
    mach_port_name_array_t names = nullptr;
    mach_port_type_array_t types = nullptr;
    mach_msg_type_number_t nameCount = 0, typeCount = 0;

    kern_return_t kr = mach_port_names(mach_task_self(), &names, &nameCount, &types, &typeCount);
    if (kr != KERN_SUCCESS) return MACH_PORT_NULL;

    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < nameCount; i++) {
        if (!(types[i] & MACH_PORT_TYPE_SEND)) continue;
        pid_t p = -1;
        if (pid_for_task(names[i], &p) == KERN_SUCCESS && p == targetPid) {
            mach_port_mod_refs(mach_task_self(), names[i], MACH_PORT_RIGHT_SEND, +1);
            result = names[i];
            break;
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)names, nameCount * sizeof(mach_port_name_t));
    vm_deallocate(mach_task_self(), (vm_address_t)types, typeCount * sizeof(mach_port_type_t));
    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDRead — читаем kernel virtual address напрямую через kfd
// ─────────────────────────────────────────────────────────────────────────────
bool KFDRead(uint64_t addr, void *buffer, size_t size) {
    if (g_kfdStatus != kKFDStatusSuccess || !g_kfdHandle) return false;
    if (!addr || !buffer || !size) return false;

    @try {
        kread(g_kfdHandle, addr, buffer, size);
        return true;
    } @catch (...) {
        return false;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDFindGameProc — находим proc и pmap целевого процесса через allproc
// Кэшируем результат — allproc не меняется пока игра запущена
// ─────────────────────────────────────────────────────────────────────────────
static uint64_t s_cached_game_pmap = 0;
static pid_t    s_cached_game_pid  = -1;

static bool KFDFindGameProc(pid_t targetPid, uint64_t *out_proc, uint64_t *out_pmap) {
    if (g_kfdStatus != kKFDStatusSuccess || !g_kfdHandle) return false;

    // Возвращаем кэш если pid совпадает
    if (out_pmap && s_cached_game_pid == targetPid && s_cached_game_pmap) {
        *out_pmap = s_cached_game_pmap;
        return true;
    }

    struct kfd *kfd = (struct kfd *)g_kfdHandle;
    if (!kfd->info.kaddr.current_proc) return false;

    // Ищем по всему allproc через le_prev от current_proc
    u64 proc_kaddr = kfd->info.kaddr.current_proc;

    for (int iter = 0; iter < 4096; iter++) {
        i32 pid = 0;
        kread(g_kfdHandle, proc_kaddr + dynamic_info(proc__p_pid), &pid, sizeof(pid));

        if (pid == targetPid) {
            if (out_proc) *out_proc = proc_kaddr;
            if (out_pmap) {
                u64 task_kaddr = proc_kaddr + dynamic_info(proc__object_size);
                u64 signed_map = 0;
                kread(g_kfdHandle, task_kaddr + dynamic_info(task__map), &signed_map, sizeof(signed_map));
                u64 map_kaddr = UNSIGN_PTR(signed_map);
                u64 signed_pmap = 0;
                kread(g_kfdHandle, map_kaddr + offsetof(struct _vm_map, pmap), &signed_pmap, sizeof(signed_pmap));
                *out_pmap = UNSIGN_PTR(signed_pmap);
                s_cached_game_pmap = *out_pmap;
                s_cached_game_pid  = targetPid;
            }
            return true;
        }

        u64 next = 0;
        kread(g_kfdHandle, proc_kaddr + dynamic_info(proc__p_list__le_prev), &next, sizeof(next));
        next = UNSIGN_PTR(next);
        if (!next || next == proc_kaddr) break;
        proc_kaddr = next;
    }
    return false;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDReadGameMemory — читаем user-space VA целевого процесса через его pmap
// Не использует task port, vm_read_overwrite или любые Mach API
// Полностью через kernel page tables
// ─────────────────────────────────────────────────────────────────────────────
bool KFDReadGameMemory(pid_t targetPid, uint64_t gameVA, void *buffer, size_t size) {
    if (g_kfdStatus != kKFDStatusSuccess || !g_kfdHandle) return false;
    if (!gameVA || !buffer || !size) return false;

    struct kfd *kfd = (struct kfd *)g_kfdHandle;

    // Ищем pmap игры (кэшируется снаружи — первый вызов медленный)
    uint64_t game_pmap = 0;
    if (!KFDFindGameProc(targetPid, nullptr, &game_pmap) || !game_pmap)
        return false;

    // Лог первого успешного вызова
    static bool s_logged_stealth = false;
    if (!s_logged_stealth) {
        s_logged_stealth = true;
        FILE *f = fopen("/var/mobile/kfd_debug.log", "a");
        if (f) { fprintf(f, "[STEALTH] KFDReadGameMemory active, pmap=0x%llx\n", (unsigned long long)game_pmap); fclose(f); }
    }

    // Читаем побайтово по страницам через page walk игрового pmap
    // Каждые 16KB — новый page table walk
    const u64 PAGE_SIZE = 0x4000; // arm64 16K pages
    uint8_t *dst = (uint8_t *)buffer;
    u64 remaining = size;
    u64 va = gameVA;

    // Временно подменяем TTBR0 на pmap игры для vtophys
    // Сохраняем оригинальный pmap нашего процесса
    u64 saved_pmap_va = kfd->perf.ttbr[0].va;
    u64 saved_pmap_pa = kfd->perf.ttbr[0].pa;

    // Читаем tte (page table base) из pmap игры
    u64 game_tte = 0;
    kread(g_kfdHandle, game_pmap + offsetof(struct pmap, tte), &game_tte, sizeof(game_tte));
    u64 game_ttep = 0;
    kread(g_kfdHandle, game_pmap + offsetof(struct pmap, ttep), &game_ttep, sizeof(game_ttep));

    // Подменяем TTBR0 на page tables игры
    kfd->perf.ttbr[0].va = game_tte;
    kfd->perf.ttbr[0].pa = game_ttep;

    bool success = true;
    while (remaining > 0) {
        u64 page_offset = va & (PAGE_SIZE - 1);
        u64 chunk = PAGE_SIZE - page_offset;
        if (chunk > remaining) chunk = remaining;

        // Транслируем VA игры в PA через её page tables
        u64 pa = vtophys(kfd, va);
        if (!pa) {
            success = false;
            break;
        }

        // PA → kernel VA → читаем через perf_kread
        u64 kva = phystokv(kfd, pa);
        if (!kva) {
            success = false;
            break;
        }

        kread(g_kfdHandle, kva, dst, chunk);
        dst += chunk;
        va += chunk;
        remaining -= chunk;
    }

    // Восстанавливаем наш pmap
    kfd->perf.ttbr[0].va = saved_pmap_va;
    kfd->perf.ttbr[0].pa = saved_pmap_pa;

    return success;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDWriteGameMemory — пишем в user-space VA целевого процесса через его pmap
// ─────────────────────────────────────────────────────────────────────────────
bool KFDWriteGameMemory(pid_t targetPid, uint64_t gameVA, const void *buffer, size_t size) {
    if (g_kfdStatus != kKFDStatusSuccess || !g_kfdHandle) return false;
    if (!gameVA || !buffer || !size || (size % 8 != 0)) return false;

    struct kfd *kfd = (struct kfd *)g_kfdHandle;

    uint64_t game_pmap = 0;
    if (!KFDFindGameProc(targetPid, nullptr, &game_pmap) || !game_pmap)
        return false;

    u64 saved_pmap_va = kfd->perf.ttbr[0].va;
    u64 saved_pmap_pa = kfd->perf.ttbr[0].pa;

    u64 game_tte = 0;
    kread(g_kfdHandle, game_pmap + offsetof(struct pmap, tte), &game_tte, sizeof(game_tte));
    u64 game_ttep = 0;
    kread(g_kfdHandle, game_pmap + offsetof(struct pmap, ttep), &game_ttep, sizeof(game_ttep));

    kfd->perf.ttbr[0].va = game_tte;
    kfd->perf.ttbr[0].pa = game_ttep;

    const u64 PAGE_SIZE = 0x4000;
    const uint8_t *src = (const uint8_t *)buffer;
    u64 remaining = size;
    u64 va = gameVA;
    bool success = true;

    while (remaining > 0) {
        u64 page_offset = va & (PAGE_SIZE - 1);
        u64 chunk = PAGE_SIZE - page_offset;
        if (chunk > remaining) chunk = remaining;
        // выравниваем chunk до 8 байт для kwrite
        chunk = chunk & ~7ULL;
        if (chunk == 0) { va++; remaining--; src++; continue; }

        u64 pa = vtophys(kfd, va);
        if (!pa) { success = false; break; }
        u64 kva = phystokv(kfd, pa);
        if (!kva) { success = false; break; }

        kwrite(g_kfdHandle, (void*)src, kva, chunk);
        src += chunk;
        va += chunk;
        remaining -= chunk;
    }

    kfd->perf.ttbr[0].va = saved_pmap_va;
    kfd->perf.ttbr[0].pa = saved_pmap_pa;

    return success;
}

// ─────────────────────────────────────────────────────────────────────────────
// KFDClose
// ─────────────────────────────────────────────────────────────────────────────
void KFDClose(void) {
    if (g_kfdHandle) {
        @try { kclose(g_kfdHandle); } @catch (...) {}
        g_kfdHandle = 0;
    }
    g_kfdStatus = kKFDStatusNotStarted;
}
