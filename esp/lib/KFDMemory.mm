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
    if (g_kfdStatus == kKFDStatusFailed)  return false;

    g_kfdStatus = kKFDStatusRunning;

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
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        bool result = KFDInit(method);
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(result);
            });
        }
    });
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
// KFDRead — читаем память целевого процесса напрямую через kfd
// Обходим vm_read_overwrite полностью
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
// KFDClose
// ─────────────────────────────────────────────────────────────────────────────
void KFDClose(void) {
    if (g_kfdHandle) {
        @try { kclose(g_kfdHandle); } @catch (...) {}
        g_kfdHandle = 0;
    }
    g_kfdStatus = kKFDStatusNotStarted;
}
