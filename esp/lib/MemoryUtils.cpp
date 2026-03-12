#import "MemoryUtils.h"
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <time.h>

// ─── Лог в файл ───────────────────────────────────────────────────────────────
#define KFD_LOG_PATH "/var/mobile/kfd_debug.log"

static void kfd_log(const char *fmt, ...) {
    FILE *f = fopen(KFD_LOG_PATH, "a");
    if (!f) return;
    // Время
    time_t t = time(NULL);
    struct tm *tm = localtime(&t);
    fprintf(f, "[%02d:%02d:%02d] ", tm->tm_hour, tm->tm_min, tm->tm_sec);
    // Сообщение
    va_list args;
    va_start(args, fmt);
    vfprintf(f, fmt, args);
    va_end(args);
    fprintf(f, "\n");
    fclose(f);
}
// ──────────────────────────────────────────────────────────────────────────────

// KFD метод — компилируется как ObjC++ (.mm) через KFDMemory.mm
// Здесь только extern объявления
extern "C" {
#include "KFDMemory.h"
}

// Глобальный task port игрового процесса
mach_port_t get_task  = MACH_PORT_NULL;
pid_t       Processpid = 0;

// Текущий метод получения task порта (0/1/2)
// Читается из plist при старте, меняется из Config таба в HUD
int g_taskMethod    = 1; // proc_set по умолчанию
int g_kfdPuafMethod = 1; // smith по умолчанию (iOS <= 16.5)

// Загружаем выбранный метод из plist (записывает лаунчер Fryzzternal)
// Используем CoreFoundation — работает в чистом C++ файле без ObjC
static void LoadTaskMethodFromPrefs(void) {
    CFStringRef path = CFSTR("/var/mobile/Library/Preferences/ch.xxtou.hudapp.plist");
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, path, kCFURLPOSIXPathStyle, false);
    if (!url) return;

    CFReadStreamRef stream = CFReadStreamCreateWithFile(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!stream) return;

    if (CFReadStreamOpen(stream)) {
        CFPropertyListRef plist = CFPropertyListCreateWithStream(
            kCFAllocatorDefault, stream, 0,
            kCFPropertyListImmutable, NULL, NULL);
        CFReadStreamClose(stream);

        if (plist && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
            CFDictionaryRef dict = (CFDictionaryRef)plist;
            CFNumberRef num = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("taskMethod"));
            if (num && CFGetTypeID(num) == CFNumberGetTypeID()) {
                int val = 1;
                CFNumberGetValue(num, kCFNumberIntType, &val);
                g_taskMethod = val;
            }
            CFNumberRef puafNum = (CFNumberRef)CFDictionaryGetValue(dict, CFSTR("kfdPuafMethod"));
            if (puafNum && CFGetTypeID(puafNum) == CFNumberGetTypeID()) {
                int val = 1;
                CFNumberGetValue(puafNum, kCFNumberIntType, &val);
                g_kfdPuafMethod = val;
            }
        }
        if (plist) CFRelease(plist);
    } else {
        CFRelease(stream);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Метод 0: task_for_pid — прямой вызов
// Самый простой, требует task_for_pid-allow entitlement.
// Хорошо известен античиту — используй только для теста.
// ─────────────────────────────────────────────────────────────────────────────
static mach_port_t Method0_TaskForPid(pid_t targetPid) {
    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), targetPid, &task);
    if (kr != KERN_SUCCESS) return MACH_PORT_NULL;
    return task;
}

// ─────────────────────────────────────────────────────────────────────────────
// Метод 1: processor_set_tasks — получаем список всех tasks через processor set
// Не вызывает task_for_pid напрямую. Требует com.apple.system-task-ports.
// Рекомендуемый метод — уже доказал работу на TrollStore.
// ─────────────────────────────────────────────────────────────────────────────
static mach_port_t Method1_ProcessorSetTasks(pid_t targetPid) {
    host_t host = mach_host_self();

    processor_set_name_t psDefault;
    if (processor_set_default(host, &psDefault) != KERN_SUCCESS)
        return MACH_PORT_NULL;

    processor_set_t psPriv;
    if (host_processor_set_priv(host, psDefault, &psPriv) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

    task_array_t tasks;
    mach_msg_type_number_t taskCount = 0;
    if (processor_set_tasks(psPriv, &tasks, &taskCount) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psPriv);
        mach_port_deallocate(mach_task_self(), psDefault);
        return MACH_PORT_NULL;
    }

    mach_port_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < taskCount; i++) {
        pid_t pid = -1;
        pid_for_task(tasks[i], &pid);
        if (pid == targetPid) {
            result = tasks[i];
        } else {
            mach_port_deallocate(mach_task_self(), tasks[i]);
        }
    }

    vm_deallocate(mach_task_self(), (vm_address_t)tasks, taskCount * sizeof(task_t));
    mach_port_deallocate(mach_task_self(), psPriv);
    mach_port_deallocate(mach_task_self(), psDefault);

    return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Метод 2: pid_iterate — перебираем порты Mach через mach_port_names,
// вызываем pid_for_task на каждом пока не найдём нужный PID.
// Не использует ни task_for_pid ни processor_set — самый скрытный.
// Медленнее, но вызывается только один раз при старте.
// ─────────────────────────────────────────────────────────────────────────────
static mach_port_t Method2_PidIterate(pid_t targetPid) {
    mach_port_name_array_t names = nullptr;
    mach_port_type_array_t types = nullptr;
    mach_msg_type_number_t nameCount = 0, typeCount = 0;

    kern_return_t kr = mach_port_names(mach_task_self(), &names, &nameCount, &types, &typeCount);
    if (kr != KERN_SUCCESS) return MACH_PORT_NULL;

    mach_port_t result = MACH_PORT_NULL;

    for (mach_msg_type_number_t i = 0; i < nameCount; i++) {
        if (!(types[i] & MACH_PORT_TYPE_SEND)) continue;

        pid_t pid = -1;
        kern_return_t pkr = pid_for_task(names[i], &pid);
        if (pkr == KERN_SUCCESS && pid == targetPid) {
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
// Универсальная функция — выбирает метод по g_taskMethod
// Fallback по цепочке если выбранный не сработал
// ─────────────────────────────────────────────────────────────────────────────
mach_port_t AcquireTaskPort(pid_t pid) {
    mach_port_t task = MACH_PORT_NULL;

    if (g_taskMethod == 3) {
        // HUD процесс: g_kfdStatus всегда NotStarted (разные процессы)
        // Запускаем kopen прямо здесь если ещё не запущен
        if (g_kfdStatus != kKFDStatusSuccess) {
            kfd_log("[KFD-DBG] HUD: running KFDInit with puafMethod=%d", g_kfdPuafMethod);
            KFDInit((KFDPuafMethod)g_kfdPuafMethod);
            kfd_log("[KFD-DBG] HUD: KFDInit done, kfdStatus=%d kfdHandle=%llu",
                    (int)g_kfdStatus, (unsigned long long)g_kfdHandle);
        }

        if (g_kfdStatus == kKFDStatusSuccess) {
            task = KFDAcquireTaskPort(pid);
            kfd_log("[KFD-DBG] KFDAcquireTaskPort returned 0x%x", task);
        }
        // Если kfd не дал task — пробуем все fallback методы
        if (task == MACH_PORT_NULL) {
            task = Method2_PidIterate(pid);
            kfd_log("[KFD-DBG] Method2_PidIterate fallback returned 0x%x", task);
        }
        if (task == MACH_PORT_NULL) {
            task = Method1_ProcessorSetTasks(pid);
            kfd_log("[KFD-DBG] Method1_ProcessorSetTasks fallback returned 0x%x", task);
        }
        if (task == MACH_PORT_NULL) {
            task = Method0_TaskForPid(pid);
            kfd_log("[KFD-DBG] Method0_TaskForPid fallback returned 0x%x", task);
        }
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
// PID по имени процесса
// ─────────────────────────────────────────────────────────────────────────────
pid_t GetGameProcesspid(char* GameProcessName) {
    size_t length = 0;
    static const int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, NULL, &length, NULL, 0);

    struct kinfo_proc *procBuffer = (struct kinfo_proc *)malloc(length);
    if (!procBuffer) return -1;

    if (sysctl((int *)name, (sizeof(name) / sizeof(*name)) - 1, procBuffer, &length, NULL, 0) == -1) {
        free(procBuffer);
        return -1;
    }

    int count = (int)length / sizeof(struct kinfo_proc);
    for (int i = 0; i < count; i++) {
        if (strstr(procBuffer[i].kp_proc.p_comm, GameProcessName)) {
            pid_t pid = procBuffer[i].kp_proc.p_pid;
            free(procBuffer);
            return pid;
        }
    }
    free(procBuffer);
    return -1;
}

// ─────────────────────────────────────────────────────────────────────────────
// Base address
// ─────────────────────────────────────────────────────────────────────────────
vm_map_offset_t GetGameModule_Base(char* GameProcessName) {
    // Читаем выбранный метод из настроек лаунчера
    LoadTaskMethodFromPrefs();

    kfd_log("[KFD-DBG] GetGameModule_Base: taskMethod=%d kfdStatus=%d kfdHandle=%llu",
            g_taskMethod, (int)g_kfdStatus, (unsigned long long)g_kfdHandle);

    pid_t pid = GetGameProcesspid(GameProcessName);
    kfd_log("[KFD-DBG] target pid=%d", pid);
    if (pid == -1) return 0;

    Processpid = pid;
    get_task   = AcquireTaskPort(pid);
    kfd_log("[KFD-DBG] get_task=0x%x", get_task);
    if (get_task == MACH_PORT_NULL) return 0;

    vm_map_offset_t vmoffset  = 0;
    vm_map_size_t   vmsize    = 0;
    uint32_t        depth     = 0;
    struct vm_region_submap_info_64 vbr;
    mach_msg_type_number_t vbrcount = 16;

    kern_return_t kr = mach_vm_region_recurse(get_task, &vmoffset, &vmsize,
                                              &depth, (vm_region_recurse_info_t)&vbr, &vbrcount);
    return (kr == KERN_SUCCESS) ? vmoffset : 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Read / Write
// ─────────────────────────────────────────────────────────────────────────────
bool _read(long addr, void *buffer, int len) {
    if (!isVaildPtr(addr)) return false;
    if (get_task == MACH_PORT_NULL) return false;
    vm_size_t size = 0;
    return vm_read_overwrite(get_task, (vm_address_t)addr, len,
                             (vm_address_t)buffer, &size) == KERN_SUCCESS
           && size == (vm_size_t)len;
}

bool _write(long addr, const void *buffer, int len) {
    if (!isVaildPtr(addr) || get_task == MACH_PORT_NULL) return false;
    vm_address_t region = (vm_address_t)addr;
    vm_size_t    rsize  = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    kern_return_t kr = vm_region_64(get_task, &region, &rsize,
                                    VM_REGION_BASIC_INFO_64,
                                    (vm_region_info_t)&info, &infoCnt, &obj);
    if (kr != KERN_SUCCESS) return false;
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize) return false;
    return vm_write(get_task, (vm_address_t)addr,
                    (vm_offset_t)buffer, (mach_msg_type_number_t)len) == KERN_SUCCESS;
}

// ─────────────────────────────────────────────────────────────────────────────
// Value scan
// ─────────────────────────────────────────────────────────────────────────────
int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void *pattern, size_t patSize,
                 uint64_t *outAddrs, int maxResults) {
    if (get_task == MACH_PORT_NULL || patSize == 0 || !outAddrs || maxResults <= 0)
        return 0;

    const size_t CHUNK = 0x100000;
    uint8_t *buf = (uint8_t *)malloc(CHUNK);
    if (!buf) return 0;

    int found = 0;
    for (uint64_t addr = rangeStart; addr < rangeEnd && found < maxResults; addr += CHUNK) {
        vm_size_t actualRead = 0;
        kern_return_t kr = vm_read_overwrite(get_task, (vm_address_t)addr,
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
