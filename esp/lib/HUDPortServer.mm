#import "PortStash.h"
#import "MemoryUtils.h"
#import <mach/mach.h>
#import <notify.h>
#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <Foundation/Foundation.h>

// Cached game task port — set when port request succeeds
static mach_port_t g_cachedGameTask = MACH_PORT_NULL;

// Called from HUD process (UID 0) to serve task port requests.
// Runs on a background thread alongside the HUD UI.
extern "C" void HUDPortServer_Start(void) {
    // Verify we're running as root
    if (getuid() != 0) {
        NSLog(@"[HUDPortServer] NOT root (uid=%d) — port server disabled", getuid());
        return;
    }
    NSLog(@"[HUDPortServer] Running as root (uid=0) ✓");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // Register for request notifications from App
        int token;
        notify_register_dispatch(FRYZZ_NOTIFY_REQUEST, &token,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            ^(int t) {
                NSLog(@"[HUDPortServer] Received port request");

                // Read target PID and app PID from request file
                NSData *data = [NSData dataWithContentsOfFile:@FRYZZ_IPC_REQUEST_PATH];
                if (!data || data.length < sizeof(pid_t) * 2) {
                    NSLog(@"[HUDPortServer] Bad request file");
                    return;
                }
                pid_t pids[2];
                memcpy(pids, data.bytes, sizeof(pids));
                pid_t targetPid = pids[0];
                pid_t appPid    = pids[1];
                NSLog(@"[HUDPortServer] targetPid=%d appPid=%d", targetPid, appPid);

                // Get task port for game via processor_set_tasks (we're root)
                InitFunctionPointers();
                mach_port_t gameTask = Method1_ProcessorSetTasks_Public(targetPid);
                if (gameTask == MACH_PORT_NULL) {
                    NSLog(@"[HUDPortServer] Failed to get game task port");
                    // Signal failure
                    [@"fail" writeToFile:@FRYZZ_IPC_RESPONSE_PATH
                              atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    notify_post(FRYZZ_NOTIFY_RESPONSE);
                    return;
                }
                NSLog(@"[HUDPortServer] Got game task port: %u", gameTask);

                // Get app task port
                mach_port_t appTask = Method1_ProcessorSetTasks_Public(appPid);
                if (appTask == MACH_PORT_NULL) {
                    NSLog(@"[HUDPortServer] Failed to get app task port");
                    mach_port_deallocate(mach_task_self(), gameTask);
                    [@"fail" writeToFile:@FRYZZ_IPC_RESPONSE_PATH
                              atomically:YES encoding:NSUTF8StringEncoding error:nil];
                    notify_post(FRYZZ_NOTIFY_RESPONSE);
                    return;
                }

                // Cache gameTask in HUD for aim writes (UID 0 vm_write)
                if (g_cachedGameTask != MACH_PORT_NULL)
                    mach_port_deallocate(mach_task_self(), g_cachedGameTask);
                g_cachedGameTask = gameTask;

                // Stash game port into app's registered ports via kernel API
                bool ok = PortStash_Register(appTask, gameTask);
                mach_port_deallocate(mach_task_self(), appTask);
                // Don't deallocate gameTask — it's now owned by app's port namespace

                NSLog(@"[HUDPortServer] PortStash_Register: %s", ok ? "OK" : "FAIL");
                [@(ok ? "ok" : "fail") writeToFile:@FRYZZ_IPC_RESPONSE_PATH
                          atomically:YES encoding:NSUTF8StringEncoding error:nil];
                notify_post(FRYZZ_NOTIFY_RESPONSE);
            });

        NSLog(@"[HUDPortServer] Listening for requests...");

        // Aim write server — получаем rotation от App, пишем через vm_write (UID 0)
        int aimToken;
        notify_register_dispatch(FRYZZ_NOTIFY_AIM_WRITE, &aimToken,
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0),
            ^(int t) {
                if (g_cachedGameTask == MACH_PORT_NULL) return;

                // Читаем aim request из файла
                NSData *data = [NSData dataWithContentsOfFile:@FRYZZ_IPC_AIM_PATH];
                if (!data || data.length < sizeof(FryzzAimRequest)) return;

                FryzzAimRequest req;
                memcpy(&req, data.bytes, sizeof(req));
                if (req.playerAddr == 0) return;

                // Пишем оба rotation поля из UID 0
                float quat[4] = { req.x, req.y, req.z, req.w };
                vm_write(g_cachedGameTask,
                         (vm_address_t)(req.playerAddr + 0x53C),
                         (vm_offset_t)quat, sizeof(quat));
                vm_write(g_cachedGameTask,
                         (vm_address_t)(req.playerAddr + 0x172C),
                         (vm_offset_t)quat, sizeof(quat));
            });

        // Keep thread alive
        [[NSRunLoop currentRunLoop] run];
    });
}
