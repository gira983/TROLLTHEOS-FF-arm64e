#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <mach/mach.h>
#include <mach/processor_set.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>
#include <string>

#pragma mark - Task Method

// Метод получения task порта:
// 0 = direct   (task_for_pid)        — прямой, быстрый, легче детектируется
// 1 = procset  (processor_set_tasks) — через список всех tasks, менее заметен (DEFAULT)
// 2 = iterate  (mach_port_names)     — итерация pid_for_task по всем портам, скрытный
// 3 = kfd      (kernel exploit)      — обходит все Mach API
//                                      physpuppet=iOS<=16.3, smith=iOS<=16.5, landa=iOS<=16.7

// kfd puaf sub-метод (только когда g_taskMethod == 3):
// 0 = physpuppet, 1 = smith, 2 = landa
extern int g_kfdPuafMethod;

extern mach_port_t get_task;
extern pid_t Processpid;

extern "C" kern_return_t mach_vm_region_recurse(vm_map_t                 map,
                                                mach_vm_address_t        *address,
                                                mach_vm_size_t           *size,
                                                uint32_t                 *depth,
                                                vm_region_recurse_info_t info,
                                                mach_msg_type_number_t   *infoCnt);

inline bool isVaildPtr(long addr){
    return addr > 0x100000000 && addr < 0x1600000000;
}

pid_t GetGameProcesspid(char* GameProcessName);

// Получить task порт выбранным методом (g_taskMethod)
mach_port_t AcquireTaskPort(pid_t pid);

vm_map_offset_t GetGameModule_Base(char* GameProcessName);

bool _read(long addr, void *buffer, int len);
void InitFunctionPointers(void);
extern "C" mach_port_t Method1_ProcessorSetTasks_Public(pid_t targetPid);
bool _write(long addr, const void *buffer, int len);

template<typename T>
T ReadAddr(long address) {
    T data{};
    _read(address, reinterpret_cast<void *>(&data), sizeof(T));
    return data;
}

template<typename T>
bool WriteAddr(long address, const T &data) {
    return _write(address, reinterpret_cast<const void *>(&data), sizeof(T));
}

int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults);

#endif
