#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <mach/mach.h>
#include <mach/processor_set.h>
#include <mach/mach_host.h>
#include <mach-o/dyld_images.h>
#include <sys/sysctl.h>

// ─── Globals ──────────────────────────────────────────────────────────────────
// get_task и Processpid обновляются в GetGameModule_Base каждый раз
// когда PID меняется (рестарт игры).
extern mach_port_t get_task;
extern pid_t       Processpid;

extern "C" kern_return_t mach_vm_region_recurse(
    vm_map_t map, mach_vm_address_t *address, mach_vm_size_t *size,
    uint32_t *depth, vm_region_recurse_info_t info, mach_msg_type_number_t *infoCnt);

// Валидный диапазон user-space адресов для arm64 iOS 16
inline bool isVaildPtr(long addr) {
    return addr > 0x100000000L && addr < 0x200000000000L;
}

// ─── API ──────────────────────────────────────────────────────────────────────

// Получить PID процесса по имени через sysctl
pid_t GetGameProcesspid(const char* name);

// Получить task port через processor_set_tasks (вызывать только из HUD, UID 0)
task_t GetTaskByPid(pid_t pid);

// Получить точный base адрес образа по имени через dyld image list
mach_vm_address_t GetImageBase(task_t task, const char* image_name);

// Инициализировать get_task и Processpid для данного процесса.
// Возвращает base адрес или 0 если игра не запущена.
// Вызывать каждый кадр — кэширует по PID, не пересоздаёт task port без нужды.
mach_vm_address_t GetGameModule_Base(const char* GameProcessName, const char* ImageName);

// Чтение/запись памяти игры через get_task
bool _read(long addr, void* buffer, int len);
bool _write(long addr, const void* buffer, int len);

template<typename T>
T ReadAddr(long address) {
    T data{};
    _read(address, reinterpret_cast<void*>(&data), sizeof(T));
    return data;
}

template<typename T>
bool WriteAddr(long address, const T& data) {
    return _write(address, reinterpret_cast<const void*>(&data), sizeof(T));
}

int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void* pattern, size_t patSize,
                 uint64_t* outAddrs, int maxResults);

#endif
