#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void TouchAimbot_Init(void);
void TouchAimbot_SendDelta(CGFloat dx, CGFloat dy);
void TouchAimbot_Release(void);

#ifdef __cplusplus
}
#endif
