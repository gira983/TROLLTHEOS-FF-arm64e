#ifndef MemoryUtils_h
#define MemoryUtils_h

#include <mach/mach.h>
#include <sys/sysctl.h>
#include <string>
#include <stdint.h>

#pragma mark - Globals (extern — одна копия в MemoryUtils.cpp)
extern mach_port_t get_task;
extern pid_t       Processpid;

extern "C" kern_return_t mach_vm_region_recurse(vm_map_t                 map,
                                                mach_vm_address_t        *address,
                                                mach_vm_size_t           *size,
                                                uint32_t                 *depth,
                                                vm_region_recurse_info_t info,
                                                mach_msg_type_number_t   *infoCnt);

inline bool isVaildPtr(long addr) {
    return addr > 0x100000000 && addr < 0x1600000000;
}

pid_t           GetGameProcesspid(char* GameProcessName);
vm_map_offset_t GetGameModule_Base(char* GameProcessName);

bool _read(long addr, void *buffer, int len);
bool _write(long addr, const void *buffer, int len);

int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults);

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

#endif
