#import "MemoryUtils.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/sysctl.h>
#include <limits.h>

// ─── Globals ──────────────────────────────────────────────────────────────────
mach_port_t get_task   = MACH_PORT_NULL;
pid_t       Processpid = 0;

// ─── dyld structs для удалённого чтения ───────────────────────────────────────
struct remote_dyld_image_info {
    mach_vm_address_t imageLoadAddress;
    mach_vm_address_t imageFilePath;
    mach_vm_size_t    imageFileModDate;
};

struct remote_dyld_all_image_infos {
    uint32_t          version;
    uint32_t          infoArrayCount;
    mach_vm_address_t infoArray;
};

// ─── Динамический резолвинг — убирает символы из import table ─────────────────
typedef kern_return_t (*t_vm_read_overwrite)(vm_map_t, vm_address_t, vm_size_t, vm_address_t, vm_size_t*);
typedef kern_return_t (*t_vm_write)(vm_map_t, vm_address_t, vm_offset_t, mach_msg_type_number_t);
typedef kern_return_t (*t_vm_region_64)(vm_map_t, vm_address_t*, vm_size_t*, vm_region_flavor_t, vm_region_info_t, mach_msg_type_number_t*, mach_port_t*);
typedef kern_return_t (*t_mach_vm_region_recurse)(vm_map_t, mach_vm_address_t*, mach_vm_size_t*, natural_t*, vm_region_recurse_info_t, mach_msg_type_number_t*);
typedef kern_return_t (*t_processor_set_default)(host_t, processor_set_name_t*);
typedef kern_return_t (*t_host_processor_set_priv)(host_t, processor_set_name_t, processor_set_t*);
typedef kern_return_t (*t_processor_set_tasks)(processor_set_t, task_array_t*, mach_msg_type_number_t*);
typedef kern_return_t (*t_pid_for_task)(mach_port_t, int*);
typedef kern_return_t (*t_task_info)(task_name_t, task_flavor_t, task_info_t, mach_msg_type_number_t*);

static t_vm_read_overwrite       fn_vm_read_overwrite       = nullptr;
static t_vm_write                fn_vm_write                = nullptr;
static t_vm_region_64            fn_vm_region_64            = nullptr;
static t_mach_vm_region_recurse  fn_mach_vm_region_recurse  = nullptr;
static t_processor_set_default   fn_processor_set_default   = nullptr;
static t_host_processor_set_priv fn_host_processor_set_priv = nullptr;
static t_processor_set_tasks     fn_processor_set_tasks     = nullptr;
static t_pid_for_task            fn_pid_for_task            = nullptr;
static t_task_info               fn_task_info               = nullptr;

static void* rfn(const char* a, const char* b) {
    char name[64] = {};
    strlcat(name, a, sizeof(name));
    strlcat(name, b, sizeof(name));
    return dlsym(RTLD_DEFAULT, name);
}

static void InitFn() {
    static bool done = false;
    if (done) return;
    done = true;
    fn_vm_read_overwrite       = (t_vm_read_overwrite)      rfn("vm_read_",        "overwrite");
    fn_vm_write                = (t_vm_write)               rfn("vm_w",            "rite");
    fn_vm_region_64            = (t_vm_region_64)           rfn("vm_regi",         "on_64");
    fn_mach_vm_region_recurse  = (t_mach_vm_region_recurse) rfn("mach_vm_region_", "recurse");
    fn_processor_set_default   = (t_processor_set_default)  rfn("processor_set_",  "default");
    fn_host_processor_set_priv = (t_host_processor_set_priv)rfn("host_processor_set_","priv");
    fn_processor_set_tasks     = (t_processor_set_tasks)    rfn("processor_set_",  "tasks");
    fn_pid_for_task            = (t_pid_for_task)           rfn("pid_for",         "_task");
    fn_task_info               = (t_task_info)              rfn("task_i",          "nfo");
}

// ─── PID ──────────────────────────────────────────────────────────────────────
pid_t GetGameProcesspid(const char* name) {
    size_t len = 0;
    static const int mib[] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    sysctl((int*)mib, 3, NULL, &len, NULL, 0);
    struct kinfo_proc* buf = (struct kinfo_proc*)malloc(len);
    if (!buf) return -1;
    if (sysctl((int*)mib, 3, buf, &len, NULL, 0) != 0) { free(buf); return -1; }
    int count = (int)(len / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        if (strstr(buf[i].kp_proc.p_comm, name)) {
            pid_t pid = buf[i].kp_proc.p_pid;
            free(buf);
            return pid;
        }
    }
    free(buf);
    return -1;
}

// ─── Task port через processor_set_tasks (только из root HUD) ─────────────────
task_t GetTaskByPid(pid_t pid) {
    InitFn();
    if (!fn_processor_set_default || !fn_host_processor_set_priv || !fn_processor_set_tasks)
        return MACH_PORT_NULL;

    host_t host = mach_host_self();
    processor_set_name_t psName = MACH_PORT_NULL;
    if (fn_processor_set_default(host, &psName) != KERN_SUCCESS)
        return MACH_PORT_NULL;

    processor_set_t psPriv = MACH_PORT_NULL;
    if (fn_host_processor_set_priv(host, psName, &psPriv) != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), psName);
        return MACH_PORT_NULL;
    }

    task_array_t tasks = nullptr;
    mach_msg_type_number_t taskCount = 0;
    kern_return_t kr = fn_processor_set_tasks(psPriv, &tasks, &taskCount);
    mach_port_deallocate(mach_task_self(), psPriv);
    mach_port_deallocate(mach_task_self(), psName);
    if (kr != KERN_SUCCESS) return MACH_PORT_NULL;

    task_t result = MACH_PORT_NULL;
    for (mach_msg_type_number_t i = 0; i < taskCount; i++) {
        pid_t p = -1;
        if (fn_pid_for_task) fn_pid_for_task(tasks[i], &p);
        if (p == pid) result = tasks[i];
        else mach_port_deallocate(mach_task_self(), tasks[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)tasks, taskCount * sizeof(task_t));
    return result;
}

// ─── Base адрес образа по имени через dyld image list ─────────────────────────
// Адаптировано из sisi проекта (pid.mm → get_image_base_address)
mach_vm_address_t GetImageBase(task_t task, const char* image_name) {
    InitFn();
    if (task == MACH_PORT_NULL || !fn_task_info || !fn_vm_read_overwrite) return 0;

    task_dyld_info_data_t dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    if (fn_task_info(task, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count) != KERN_SUCCESS)
        return 0;

    // Читаем dyld_all_image_infos
    remote_dyld_all_image_infos infos = {};
    vm_size_t out = 0;
    if (fn_vm_read_overwrite(task, dyld_info.all_image_info_addr,
                             sizeof(infos), (vm_address_t)&infos, &out) != KERN_SUCCESS)
        return 0;
    if (infos.infoArrayCount == 0) return 0;

    // Читаем массив образов
    uint32_t img_count = infos.infoArrayCount;
    size_t arr_size = img_count * sizeof(remote_dyld_image_info);
    remote_dyld_image_info* imgs = (remote_dyld_image_info*)malloc(arr_size);
    if (!imgs) return 0;

    out = 0;
    kern_return_t kr = fn_vm_read_overwrite(task, infos.infoArray,
                                             arr_size, (vm_address_t)imgs, &out);
    if (kr != KERN_SUCCESS) { free(imgs); return 0; }

    // Ищем образ по имени
    mach_vm_address_t result = 0;
    for (uint32_t i = 0; i < img_count; i++) {
        if (!imgs[i].imageFilePath) continue;
        char path[PATH_MAX] = {};
        out = 0;
        fn_vm_read_overwrite(task, imgs[i].imageFilePath,
                             PATH_MAX - 1, (vm_address_t)path, &out);
        if (strstr(path, image_name)) {
            result = imgs[i].imageLoadAddress;
            break;
        }
    }
    free(imgs);
    return result;
}

// ─── GetGameModule_Base ────────────────────────────────────────────────────────
// Вызывать каждый кадр из update_data — кэширует по PID как в sisi проекте.
// Возвращает base адрес или 0 если игра не запущена.
mach_vm_address_t GetGameModule_Base(const char* GameProcessName, const char* ImageName) {
    InitFn();

    pid_t pid = GetGameProcesspid(GameProcessName);
    if (pid <= 0) {
        // Игра не запущена — сбрасываем
        if (get_task != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), get_task);
            get_task = MACH_PORT_NULL;
        }
        Processpid = 0;
        return 0;
    }

    // PID не изменился и task port валиден — возвращаем кэш
    // (base адрес хранится снаружи в esp.mm как static, как в sisi)
    if (pid == Processpid && get_task != MACH_PORT_NULL)
        return 0; // сигнал "используй кэш"

    // PID изменился или task port сброшен — переинициализируем
    if (get_task != MACH_PORT_NULL) {
        mach_port_deallocate(mach_task_self(), get_task);
        get_task = MACH_PORT_NULL;
    }

    Processpid = pid;
    get_task   = GetTaskByPid(pid);
    if (get_task == MACH_PORT_NULL) return 0;

    return (mach_vm_address_t)GetImageBase(get_task, ImageName ? ImageName : GameProcessName);
}

// ─── Read ──────────────────────────────────────────────────────────────────────
bool _read(long addr, void* buffer, int len) {
    if (!isVaildPtr(addr) || get_task == MACH_PORT_NULL || !fn_vm_read_overwrite) return false;
    vm_size_t size = 0;
    return fn_vm_read_overwrite(get_task, (vm_address_t)addr, (vm_size_t)len,
                                (vm_address_t)buffer, &size) == KERN_SUCCESS
           && size == (vm_size_t)len;
}

// ─── Write ─────────────────────────────────────────────────────────────────────
bool _write(long addr, const void* buffer, int len) {
    if (!isVaildPtr(addr) || get_task == MACH_PORT_NULL) return false;
    if (!fn_vm_region_64 || !fn_vm_write) return false;

    vm_address_t region = (vm_address_t)addr;
    vm_size_t    rsize  = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCnt = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t obj = MACH_PORT_NULL;
    if (fn_vm_region_64(get_task, &region, &rsize, VM_REGION_BASIC_INFO_64,
                        (vm_region_info_t)&info, &infoCnt, &obj) != KERN_SUCCESS) return false;
    if ((vm_address_t)addr < region || (vm_address_t)addr + len > region + rsize) return false;

    return fn_vm_write(get_task, (vm_address_t)addr,
                       (vm_offset_t)buffer, (mach_msg_type_number_t)len) == KERN_SUCCESS;
}

// ─── Scan ──────────────────────────────────────────────────────────────────────
int scanForValue(uint64_t rangeStart, uint64_t rangeEnd,
                 const void* pattern, size_t patSize,
                 uint64_t* outAddrs, int maxResults) {
    if (get_task == MACH_PORT_NULL || patSize == 0 || !outAddrs || maxResults <= 0) return 0;
    if (!fn_vm_read_overwrite) return 0;
    const size_t CHUNK = 0x100000;
    uint8_t* buf = (uint8_t*)malloc(CHUNK);
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
