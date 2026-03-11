#ifndef KFDMemory_h
#define KFDMemory_h

#include <stdint.h>
#include <stdbool.h>
#include <mach/mach.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─────────────────────────────────────────────────────────────────────────────
// KFD метод получения task порта (метод 3 в нашей системе)
//
// Использует kernel exploit (kfd) для обхода всех Mach API:
//   puaf_physpuppet — CVE-2023-23536, iOS <= 16.3.x
//   puaf_smith      — CVE-2023-32434, iOS <= 16.5
//   puaf_landa      — CVE-2023-41974, iOS <= 16.7.x
//
// После kopen() читаем allproc из ядра, ищем proc по PID,
// берём proc->task->vm_map и подменяем get_task напрямую.
//
// При ошибке или неподдерживаемой iOS — возвращает MACH_PORT_NULL
// и вызывающий код делает fallback на обычные методы.
// ─────────────────────────────────────────────────────────────────────────────

// Выбор puaf метода (соответствует enum puaf_method в libkfd)
typedef enum {
    kKFDMethodPhysPuppet = 0,  // CVE-2023-23536, iOS <= 16.3.x
    kKFDMethodSmith      = 1,  // CVE-2023-32434, iOS <= 16.5
    kKFDMethodLanda      = 2,  // CVE-2023-41974, iOS <= 16.7.x
} KFDPuafMethod;

// Статус kfd сессии
typedef enum {
    kKFDStatusNotStarted = 0,
    kKFDStatusRunning    = 1,
    kKFDStatusSuccess    = 2,
    kKFDStatusFailed     = 3,
    kKFDStatusUnsupported = 4,  // iOS версия не в таблице offsets
} KFDStatus;

extern KFDStatus g_kfdStatus;
extern uint64_t  g_kfdHandle;  // opaque kfd descriptor из kopen()

// Инициализировать kfd синхронно (блокирует поток)
bool KFDInit(KFDPuafMethod method);

// Инициализировать kfd асинхронно с callback по завершению
// Безопасно вызывать из main thread — работает на background thread
// completion(true) = успех, completion(false) = ошибка/неподдерживается
typedef void (^KFDInitCompletion)(bool success);
void KFDInitAsync(KFDPuafMethod method, KFDInitCompletion completion);

// Получить task port целевого процесса через kernel read
// Читает allproc в ядре, находит proc по pid, извлекает task->itk_sself
mach_port_t KFDAcquireTaskPort(pid_t targetPid);

// Читать память целевого процесса через kfd (kread по virtual address)
// Безопаснее vm_read — не проходит через Mach trap
bool KFDRead(uint64_t addr, void *buffer, size_t size);

// Закрыть kfd сессию (kclose)
void KFDClose(void);

#ifdef __cplusplus
}
#endif

#endif /* KFDMemory_h */
