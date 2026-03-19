#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Инициализация HID client — вызвать один раз при запуске HUD
void TouchAimbot_Init(void);

// Отправить свайп прицела:
// delta = смещение в экранных координатах (сколько пикселей сдвинуть прицел)
// Вызывать из renderESP вместо set_aim()
void TouchAimbot_SendDelta(CGFloat dx, CGFloat dy);

#ifdef __cplusplus
}
#endif
