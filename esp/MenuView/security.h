#pragma once
#include <sys/ptrace.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>

// ─────────────────────────────────────────────
// 1. Anti-Debug: запрет ptrace attach
//    Вызываем через function pointer чтобы не было прямого символа в бинаре
// ─────────────────────────────────────────────
static inline void sec_deny_debugger(void) {
    // Вызываем ptrace через указатель — символ ptrace не будет виден в import table
    typedef int (*ptrace_t)(int, pid_t, caddr_t, int);
    ptrace_t fn = (ptrace_t)dlsym(RTLD_DEFAULT, "ptrace");
    if (fn) fn(31 /*PT_DENY_ATTACH*/, 0, 0, 0);
}

// ─────────────────────────────────────────────
// 2. Проверка что к нам не подключён отладчик (sysctl)
// ─────────────────────────────────────────────
static inline bool sec_is_debugger_attached(void) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    memset(&info, 0, sizeof(info));
    sysctl(mib, 4, &info, &size, NULL, 0);
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

// ─────────────────────────────────────────────
// 3. Anti-Frida: ищем Frida агент в загруженных библиотеках
// ─────────────────────────────────────────────
static inline bool sec_frida_detected(void) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        // Frida вставляет frida-agent или FridaGadget
        if (strstr(name, "frida")   != NULL) return true;
        if (strstr(name, "cynject") != NULL) return true;
        if (strstr(name, "substrate") != NULL) return true;
    }
    // Проверяем открытые порты Frida (27042 default)
    // через /proc не работает на iOS, но можно проверить символы
    if (dlsym(RTLD_DEFAULT, "frida_agent_main") != NULL) return true;
    return false;
}

// ─────────────────────────────────────────────
// 4. Проверка целостности — hash первых байт нашей функции
//    Если кто-то патчит бинарь — hash изменится
// ─────────────────────────────────────────────
static inline uint32_t sec_hash_bytes(const uint8_t *data, size_t len) {
    uint32_t h = 0x811C9DC5u;
    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 0x01000193u;
    }
    return h;
}

// Вычисляем hash при первом вызове, потом сравниваем
static inline bool sec_check_integrity(void *func_ptr, size_t check_len) {
    static uint32_t saved_hash = 0;
    static bool initialized = false;

    uint8_t *ptr = (uint8_t *)func_ptr;
    uint32_t current = sec_hash_bytes(ptr, check_len);

    if (!initialized) {
        saved_hash  = current;
        initialized = true;
        return true; // первый раз — запоминаем
    }
    return (current == saved_hash);
}

// ─────────────────────────────────────────────
// 5. Timing check — отладчики замедляют выполнение
// ─────────────────────────────────────────────
#include <time.h>
static inline bool sec_timing_check(void) {
    struct timespec t1, t2;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    // Простая операция которая занимает ~0 нс в норме
    volatile int x = 0;
    for (int i = 0; i < 100; i++) x += i;
    clock_gettime(CLOCK_MONOTONIC, &t2);
    long elapsed_ns = (t2.tv_sec - t1.tv_sec) * 1000000000L + (t2.tv_nsec - t1.tv_nsec);
    // Если дольше 5мс — скорее всего брейкпоинт или замедление от отладчика
    return elapsed_ns < 5000000L;
}

// ─────────────────────────────────────────────
// 6. Главная функция — вызываем всё при старте
//    Возвращает false если что-то подозрительно
// ─────────────────────────────────────────────
static inline bool sec_init(void) {
    // Запрещаем attach отладчика
    sec_deny_debugger();

    // Проверяем Frida
    if (sec_frida_detected()) return false;

    // Проверяем отладчик
    if (sec_is_debugger_attached()) return false;

    return true;
}

// Периодическая проверка (вызывать раз в несколько секунд)
static inline bool sec_periodic_check(void) {
    if (sec_is_debugger_attached()) return false;
    if (!sec_timing_check())        return false;
    if (sec_frida_detected())       return false;
    return true;
}
