// TouchAimbot.mm — aimbot через IOHIDEvent injection
// Вместо WriteAddr(rotation) → инжектируем touch swipe в HID стек
// Выглядит как реальный палец пользователя — не детектируется memory-based античитом
#import "TouchAimbot.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

// ── IOHIDEvent private API ────────────────────────────────────────────────────
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

// Must be declared before use in function pointer typedefs
typedef double   IOHIDFloat;
typedef uint32_t IOHIDEventOptionBits;

typedef IOHIDEventSystemClientRef (*t_IOHIDEventSystemClientCreate)(CFAllocatorRef);
typedef void (*t_IOHIDEventSystemClientDispatchEvent)(IOHIDEventSystemClientRef, IOHIDEventRef);
typedef IOHIDEventRef (*t_IOHIDEventCreateDigitizerFingerEvent)(
    CFAllocatorRef allocator,
    uint64_t       timeStamp,
    uint32_t       transducerType,   // kIOHIDDigitizerTransducerTypeFinger = 1
    uint32_t       index,
    uint32_t       identity,
    uint32_t       eventMask,        // kIOHIDDigitizerEventTouch = 0x10
    uint32_t       buttonMask,       // 0
    IOHIDFloat     x,
    IOHIDFloat     y,
    IOHIDFloat     z,
    IOHIDFloat     tipPressure,
    IOHIDFloat     barrelPressure,   // 0.0
    IOHIDFloat     twist,
    bool           isRange,
    bool           isTouching,
    IOHIDEventOptionBits options);

static t_IOHIDEventSystemClientCreate           fn_ClientCreate     = NULL;
static t_IOHIDEventSystemClientDispatchEvent    fn_ClientDispatch   = NULL;
static t_IOHIDEventCreateDigitizerFingerEvent   fn_FingerEvent      = NULL;
static IOHIDEventSystemClientRef                g_hidClient         = NULL;

static dispatch_once_t g_initOnce;

extern "C" void TouchAimbot_Init(void) {
    dispatch_once(&g_initOnce, ^{
        void *iohid = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (!iohid) {
            NSLog(@"[TouchAimbot] Failed to open IOKit");
            return;
        }
        fn_ClientCreate   = (t_IOHIDEventSystemClientCreate)   dlsym(iohid, "IOHIDEventSystemClientCreate");
        fn_ClientDispatch = (t_IOHIDEventSystemClientDispatchEvent) dlsym(iohid, "IOHIDEventSystemClientDispatchEvent");
        fn_FingerEvent    = (t_IOHIDEventCreateDigitizerFingerEvent) dlsym(iohid, "IOHIDEventCreateDigitizerFingerEvent");

        if (!fn_ClientCreate || !fn_ClientDispatch || !fn_FingerEvent) {
            NSLog(@"[TouchAimbot] Missing IOHIDEvent symbols");
            return;
        }

        g_hidClient = fn_ClientCreate(kCFAllocatorDefault);
        if (!g_hidClient) {
            NSLog(@"[TouchAimbot] Failed to create HID client");
            return;
        }
        NSLog(@"[TouchAimbot] HID client ready ✓");
    });
}

// Текущая позиция виртуального пальца (джойстик прицела)
static CGFloat g_touchX = -1;
static CGFloat g_touchY = -1;
static bool    g_touchActive = false;
static uint32_t g_touchID = 42; // уникальный ID нашего виртуального касания

extern "C" void TouchAimbot_SendDelta(CGFloat dx, CGFloat dy) {
    if (!g_hidClient || !fn_FingerEvent || !fn_ClientDispatch) return;
    if (fabs(dx) < 0.5 && fabs(dy) < 0.5) return;

    // Используем правый джойстик прицела — типичный центр около (1100, 500) для FF landscape
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat vW = MAX(screen.width, screen.height);
    CGFloat vH = MIN(screen.width, screen.height);

    // Начальная позиция — центр правого джойстика (правая нижняя четверть экрана)
    if (!g_touchActive) {
        g_touchX = vW * 0.78f;
        g_touchY = vH * 0.72f;
    }

    uint64_t timestamp = mach_absolute_time();

    // Нормализуем в единицы IOHIDEvent (0.0 - 1.0 от размера экрана)
    IOHIDFloat nx = g_touchX / vW;
    IOHIDFloat ny = g_touchY / vH;

    // Clamp
    nx = fmax(0.0, fmin(1.0, nx));
    ny = fmax(0.0, fmin(1.0, ny));

    if (!g_touchActive) {
        // Phase Began
        IOHIDEventRef began = fn_FingerEvent(
            kCFAllocatorDefault,
            timestamp,
            1,      // kIOHIDDigitizerTransducerTypeFinger
            0,      // index
            g_touchID,
            0x10,   // kIOHIDDigitizerEventTouch
            0,      // buttonMask
            nx, ny, 0.0,  // x, y, z
            1.0,    // tipPressure
            0.0,    // barrelPressure
            0.0,    // twist
            false,  // isRange
            true,   // isTouching
            0       // options
        );
        if (began) {
            fn_ClientDispatch(g_hidClient, began);
            CFRelease(began);
        }
        g_touchActive = true;
    }

    // Двигаем
    g_touchX += dx;
    g_touchY += dy;
    g_touchX = fmax(vW * 0.5f, fmin(vW, g_touchX));
    g_touchY = fmax(0, fmin(vH, g_touchY));

    IOHIDFloat mx = g_touchX / vW;
    IOHIDFloat my = g_touchY / vH;

    IOHIDEventRef moved = fn_FingerEvent(
        kCFAllocatorDefault,
        timestamp + 1000,
        1, 0, g_touchID,
        0x10, 0,
        mx, my, 0.0,
        1.0, 0.0, 0.0,
        false, true,
        1  // kIOHIDEventOptionIsAbsolute
    );
    if (moved) {
        fn_ClientDispatch(g_hidClient, moved);
        CFRelease(moved);
    }
}

// Вызвать когда цель потеряна — отпустить касание
extern "C" void TouchAimbot_Release(void) {
    if (!g_hidClient || !fn_FingerEvent || !fn_ClientDispatch || !g_touchActive) return;

    uint64_t timestamp = mach_absolute_time();
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat vW = MAX(screen.width, screen.height);
    CGFloat vH = MIN(screen.width, screen.height);

    IOHIDFloat nx = g_touchX / vW;
    IOHIDFloat ny = g_touchY / vH;

    IOHIDEventRef ended = fn_FingerEvent(
        kCFAllocatorDefault,
        timestamp,
        1, 0, g_touchID,
        0x10, 0,
        nx, ny, 0.0,
        0.0, 0.0, 0.0,
        false, false,
        0
    );
    if (ended) {
        fn_ClientDispatch(g_hidClient, ended);
        CFRelease(ended);
    }
    g_touchActive = false;
}
