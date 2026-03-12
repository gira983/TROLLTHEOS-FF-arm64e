#import "MemoryUtils.h"
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <sys/sysctl.h>
#include <pthread.h>

extern "C" {
#include "KFDMemory.h"
}

// ─────────────────────────────────────────────────────────────────────────────
// Globals
// ─────────────────────────────────────────────────────────────────────────────
mach_port_t get_task   = MACH_PORT_NULL;
pid_t       Processpid = 0;
int g_taskMethod    = 1;
int g_kfdPuafMethod = 1;

// ─────────────────────────────────────────────────────────────────────────────
// Динамический резолвинг Mach API через dlsym.
// Вместо прямого вызова vm_read_overwrite() — вызов через указатель,
// resolv-им один раз при первом использовании.
// Это убирает символы из import table бинаря (что видит static анализатор).
// ─────────────────────────────────────────────────────────────────────────────
typedef kern_return_t (*t_vm_read_overwrite)(vm_map_t, vm_address_t, vm_size_t, vm_address_t, vm_size_t*);
typedef kern_return_t (*t_vm_write)(vm_map_t, vm_address_t, vm_offset_t, mach_msg_type_number_t);
typedef kern_return_t (*t_vm_region_64)(vm_map_t, vm_address_t*, vm_size_t*, vm_region_flavor_t, vm_region_info_t, mach_msg_type_number_t*, mach_port_t*);
typedef kern_return_t (*t_mach_vm_region_recurse)(vm_map_t, mach_vm_address_t*, mach_vm_size_t*, natural_t*, vm_region_recurse_info_t, mach_msg_type_number_t*);
typedef kern_return_t (*t_task_for_pid)(mach_port_t, int, mach_port_t*);
typedef kern_return_t (*t_pid_for_task)(mach_port_t, int*);
typedef kern_return_t (*t_mach_port_names)(ipc_space_t, mach_port_name_array_t*, mach_msg_type_number_t*, mach_port_type_array_t*, mach_msg_type_number_t*);
typedef kern_return_t (*t_processor_set_tasks)(processor_set_t, task_array_t*, mach_msg_type_number_t*);
typedef kern_return_t (*t_processor_set_default)(host_t, processor_set_name_t*);
typedef kern_return_t (*t_host_processor_set_priv)(host_t, processor_set_name_t, processor_set_t*);

static t_vm_read_overwrite        fn_vm_read_overwrite        = nullptr;
static t_vm_write                 fn_vm_write                 = nullptr;
static t_vm_region_64             fn_vm_region_64             = nullptr;
static t_mach_vm_region_recurse   fn_mach_vm_region_recurse   = nullptr;
static t_task_for_pid             fn_task_for_pid             = nullptr;
static t_pid_for_task             fn_pid_for_task             = nullptr;
static t_mach_port_names          fn_mach_port_names          = nullptr;
static t_processor_set_tasks      fn_processor_set_tasks      = nullptr;
static t_processor_set_default    fn_processor_set_default    = nullptr;
static t_host_processor_set_priv  fn_host_processor_set_priv  = nullptr;

// Имена функций хранятся по частям — не как целые строки в бинаре
static void* resolve_fn(const char* a, const char* b) {
    // Собираем имя функции из двух частей в runtime
    char name[64] = {};
    strlcat(name, a, sizeof(name));
    strlcat(name, b, sizeof(name));
    return dlsym(RTLD_DEFAULT, name);
}

static void InitFunctionPointers(void) {
    static bool done = false;
    if (done) return;
    done = true;

    fn_vm_read_overwrite       = (t_vm_read_overwrite)      resolve_fn("vm_read_", "overwrite");
    fn_vm_write                = (t_vm_write)               resolve_fn("vm_w", "rite");
    fn_vm_region_64            = (t_vm_region_64)           resolve_fn("vm_regi", "on_64");
    fn_mach_vm_region_recurse  = (t_mach_vm_region_recurse) resolve_fn("mach_vm_region_", "recurse");
    fn_task_for_pid            = (t_task_for_pid)           resolve_fn("task_for", "_pid");
    fn_pid_for_task            = (t_pid_for_task)           resolve_fn("pid_for", "_task");
    fn_mach_port_names         = (t_mach_port_names)        resolve_fn("mach_port", "_names");
    fn_processor_set_tasks     = (t_processor_set_tasks)    resolve_fn("processor_set", "_tasks");
    fn_processor_set_default   = (t_processor_set_default)  resolve_fn("processor_set", "_default");
    fn_host_processor_set_priv = (t_host_processor_set_priv)resolve_fn("host_processor_set", "_priv");
}

// ─────────────────────────────────────────────────────────────────────────────
// Rate limiting — не читаем/пишем слишком часто
// Античит может замечать аномально высокую частоту Mach trap'ов
// ─────────────────────────────────────────────────────────────────────────────
static uint64_t _get_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + ts.tv_nsec;
}

// ─────────────────────────────────────────────────────────────────────────────
// Preferences
// ─────────────────────────────────────────────────────────────────────────────
static void LoadTaskMethodFromPrefs(void) {
    CFStringRef path = CFSTR("/var/mobile/Library/Preferences/ch.xxtou.hudapp.plist");
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, false);
    if (!url) return;
    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream) return;
    if (CFReadStreamOpen(stream)) {
        CFPropertyListRef plist = CFPropertyListCreateWithStream(
            kCFAllocatorDefault, stream, 0, kCFPropertyListImmutable, NULL, NULL);
        CFReadStreamClose(stream);
        if (plist && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
            CFDictionaryRef dict = (CFDictionaryRef)plist;
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("taskMethod"));
            if (num && CFGetTypeID(num) == CFNumberGetTypeID()) {
                int val = 1; CFNumberGetValue(num, kCFNumberIntType, &val); g_taskMethod = val;
            }
            CFNumberRef puafNum = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("kfdPuafMethod"));
            if (puafNum && CFGetTypeID(puafNum) == CFNumberGetTypeID()) {
                int val = 1; CFNumberGetValue(puafNum, kCFNumberIntType, &val); g_kfdPuafMethod = val;
            }
        }
        if (plist) CFRelease(plist);
    } else {
        CFRelease(stream);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Task port acquisition
// ─────────────────────────────────────────────────────────────────────────────
static mach_port_t Method0_TaskForPid(pid_t targetPid) {
    if (!fn_task_for_pid) return MACH_PORT_NULL;
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = fn_task_for_pid(mach_task_self(), targetPid, &task);
    return (kr == KERN_SUCCESS) ? task : MACH_PORT_NULL;
}

static mach_port_t Method1_ProcessorSetTasks(pid_t targetPid) {
    if (!fn_processor_set_default || !fn_host_processor_set_priv || !fn_processor_set_tasks)
        return MACH_PORT_NULL;
    host_t host = mach_host_self();
    processor_set_name_t psDefault;
    if (fn_processor_set_default(host, &psDefault) != KERN_SUCCESS) return MACH_PORT_NULL;
    processor_set_t psPriv;
    if (fn_host_processor_set_priv(host, psDefault, &psPriv) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psDefault); return MACH_PORT_NULL;
    }
    task_array_t tasks; mach_msg_type_number_t taskCount = 0;
    if (fn_processor_set_tasks(psPriv, &tasks, &taskCount) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psPriv);
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }
    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < taskCount; i++) {
        pid_t pid = -1;
        if (fn_pid_for_task) fn_pid_for_task(tasks[i], &pid);
        if (pid == targetPid) result = tasks[i];
        else mach_port_deallocate(mach_task_self(), tasks[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)tasks, taskCount * sizeof(task_t));
    mach_port_deallocate(mach_task_self(), psPriv);
    mach_port_deallocate(mach_task_self(), psDefault);
    return result;
}

static mach_port_t Method2_PidIterate(pid_t targetPid) {
    if (!fn_mach_port_names || !fn_pid_for_task) return MACH_PORT_NULL;
    mach_port_name_array_t names = nullptr;
    mach_port_type_array_t types = nullptr;
    mach_msg_type_number_t nameCount = 0, typeCount = 0;
    if (fn_mach_port_names(mach_task_self(), &names, &nameCount, &types, &typeCount) != KERN_SUCCESS)
        return MACH_PORT_NULL;
    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < nameCount; i++) {
        if (!(types[i] & MACH_PORT_TYPE_SEND)) continue;
        pid_t pid = -1;
        if (fn_pid_for_task(names[i], &pid) == KERN_SUCCESS && pid == targetPid) {
            mach_port_mod_refs(mach_task_self(), names[i], MACH_PORT_RIGHT_SEND, +1);
            result = names[i]; break;
        }
    }
    vm_deallocate(mach_task_self(), (vm_address_t)names, nameCount * sizeof(mach_port_name_t));
    vm_deallocate(mach_task_self(), (vm_address_t)types, typeCount * sizeof(mach_port_type_t));
    return result;
}

mach_port_t AcquireTaskPort(pid_t pid) {
    InitFunctionPointers();
    mach_port_t task = MACH_PORT_NULL;
    if (g_taskMethod == 3) {
        if (g_kfdStatus == kKFDStatusSuccess)
            task = KFDAcquireTaskPort(pid);
        if (task == MACH_PORT_NULL) task = Method1_ProcessorSetTasks(pid);
        if (task == MACH_PORT_NULL) task = Method0_TaskForPid(pid);
        return task;
    }
    if      (g_taskMethod == 0) task = Method0_TaskForPid(pid);
    else if (g_taskMethod == 1) task = Method1_ProcessorSetTasks(pid);
    else if (g_taskMethod == 2) task = Method2_PidIterate(pid);
    if (task == MACH_PORT_NULL && g_taskMethod != 1) task = Method1_ProcessorSetTasks(pid);
    if (task == MACH_PORT_NULL && g_taskMethod != 0) task = Method0_TaskForPid(pid);
    if (task == MACH_PORT_NULL && g_taskMethod != 2) task = Method2_PidIterate(pid);
    return task;
}

// ─────────────────────────────────────────────────────────────────────────────
// PID
// ─────────────────────────────────────────────────────────────────────────────
pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);
    struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
    if (!procBuffer) return -1;
    if (sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0) == -1) {
        free(procBuffer); return -1;
    }
    int count = (int)length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        if (strstr(procBuffer[i].kp_proc.p_comm, GameProcessName)) {
            pid_t pid = procBuffer[i].kp_proc.p_pid;
            free(procBuffer); return pid;
        }
    }
    free(procBuffer); return -1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Base address
// ─────────────────────────────────────────────────────────────────────────────
vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    InitFunctionPointers();
    LoadTaskMethodFromPrefs();
    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid == -1) return 0;
    Processpid = pid;
    get_task   = AcquireTaskPort(pid);
    if (get_task == MACH_PORT_NULL) return 0;
    if (!fn_mach_vm_region_recurse) return 0;

    vm_map_offset_t vmoffset = 0;
    vm_map_size_t   vmsize   = 0;
    uint32_t        depth    = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = 16;
    kern_return_t kr = fn_mach_vm_region_recurse(get_task, &vmoffset, &vmsize,
                                                  &depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
    return (kr == KERN_SUCCESS) ? vmoffset : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Read
// Читаем случайными размерами chunk'ов чтобы паттерн трафика не был ровным.
// Случайная задержка между операциями (0-50 мкс) имитирует нормальный код.
// ─────────────────────────────────────────────────────────────────────────────
bool _read(long addr, void *buffer, int len) {
    if (!isVaildPtr(addr) || !fn_vm_read_overwrite) return false;

    // Читаем за один вызов — минимум syscall'ов
    vm_size_t size = 0;
    kern_return_t kr = fn_vm_read_overwrite(get_task, (vm_address_t)addr, (vm_size_t)len,
                                             (vm_address_t)buffer, &size);
    if (kr != KERN_SUCCESS || size != (vm_size_t)len) return false;

    // Случайный jitter 0-30 мкс — нарушает детерминированный timing паттерн
    uint32_t jitter = ((uint32_t)_get_ns() ^ (uint32_t)(uintptr_t)buffer) & 0x1F;
    if (jitter > 0) {
        struct timespec ts = { 0, (long)(jitter * 1000) };
        nanosleep(&ts, nullptr);
    }
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Write
// Перед записью делаем vm_region_64 — проверяем что регион writable.
// Дополнительно: jitter аналогичный _read.
// ─────────────────────────────────────────────────────────────────────────────
bool _write(long addr, const void *buffer, int len) {
    if (!isVaildPtr(addr) || get_task == MACH_PORT_NULL) return false;
    if (!fn_vm_region_64 || !fn_vm_write) return false;

    vm_address_t region = (vm_address_t)addr;
    vm_size_t    rsize  = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;

    kern_return_t kr = fn_vm_region_64(get_task, &region, &rsize,
                                        VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &infoCnt, &obj);
    if (kr != KERN_SUCCESS) return false;
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize) return false;

    // Jitter перед записью
    uint32_t jitter = ((uint32_t)_get_ns() ^ (uint32_t)(uintptr_t)addr) & 0x1F;
    if (jitter > 0) {
        struct timespec ts = { 0, (long)(jitter * 1000) };
        nanosleep(&ts, nullptr);
    }

    return fn_vm_write(get_task, (vm_address_t)addr,
                       (vm_offset_t)buffer, (mach_msg_type_number_t)len) == KERN_SUCCESS;
}

// ─────────────────────────────────────────────────────────────────────────────
// Value scan — читаем регион целиком одним большим vm_read
// ─────────────────────────────────────────────────────────────────────────────
int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults) {
    if (get_task == MACH_PORT_NULL || patSize == 0 || !outAddrs || maxResults <= 0) return 0;
    if (!fn_vm_read_overwrite) return 0;

    const size_t CHUNK = 0x100000;
    uint8_t *buf = (uint8_t *)malloc(CHUNK);
    if (!buf) return 0;

    int found = 0;
    for (uint64_t addr = rangeStart; addr < rangeEnd && found < maxResults; addr += CHUNK) {
        vm_size_t actualRead = 0;
        kern_return_t kr = fn_vm_read_overwrite(get_task, (vm_address_t)addr,
                                                 (vm_size_t)CHUNK, (vm_address_t)buf, &actualRead);
        if (kr != KERN_SUCCESS || actualRead < patSize) continue;
        for (vm_size_t i = 0; i + patSize <= actualRead; i += patSize) {
            if (memcmp(buf + i, pattern, patSize) == 0) {
                outAddrs[found++] = addr + i;
                if (found >= maxResults) break;
            }
        }
    }
    free(buf);
    return found;
}
