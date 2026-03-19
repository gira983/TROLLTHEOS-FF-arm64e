#pragma once
#include <mach/mach.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// HUD side (root): stash game task port into app's registered ports
// appTask = task port of the App process (obtained via processor_set_tasks)
// gameTask = task port of the game (freefireth)
bool PortStash_Register(mach_port_t appTask, mach_port_t gameTask);

// App side: retrieve stashed game task port from our own registered ports
mach_port_t PortStash_Lookup(void);

// Notification names for IPC between App and HUD
#define FRYZZ_NOTIFY_REQUEST  "com.fryzz.esp.port.request"
#define FRYZZ_NOTIFY_RESPONSE "com.fryzz.esp.port.response"

// Request file path for IPC (target PID)
#define FRYZZ_IPC_REQUEST_PATH "/tmp/fryzz_port_request"
#define FRYZZ_IPC_RESPONSE_PATH "/tmp/fryzz_port_response"

// Aim write IPC — App sends rotation, HUD writes via vm_write (UID 0)
#define FRYZZ_NOTIFY_AIM_WRITE  "com.fryzz.esp.aim.write"
#define FRYZZ_IPC_AIM_PATH      "/tmp/fryzz_aim_request"

// Aim request struct (written to FRYZZ_IPC_AIM_PATH)
typedef struct {
    uint64_t playerAddr;  // myPawnObject address
    float    x, y, z, w; // Quaternion
} FryzzAimRequest;

#ifdef __cplusplus
}
#endif
