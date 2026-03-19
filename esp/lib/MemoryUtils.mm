// MemoryUtils_ObjC.mm — ObjC/Foundation parts of MemoryUtils
// Split from MemoryUtils.cpp because .cpp cannot use ObjC types.
#import "PortStash.h"
#import <notify.h>
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <unistd.h>
#import <dispatch/dispatch.h>

// Method3: Request task port from root HUD via PortStash IPC
// HUD (root) gets port via processor_set_tasks, stashes via mach_ports_register
// App retrieves via mach_ports_lookup — kernel handles port right transfer
extern "C" mach_port_t Method3_PortStash(pid_t targetPid) {
    // Write request: [targetPid, appPid]
    pid_t pids[2] = { targetPid, getpid() };
    NSData *req = [NSData dataWithBytes:pids length:sizeof(pids)];
    if (![req writeToFile:@FRYZZ_IPC_REQUEST_PATH atomically:YES]) return MACH_PORT_NULL;

    // Signal HUD and wait for response
    __block BOOL done = NO;
    int token;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    notify_register_dispatch(FRYZZ_NOTIFY_RESPONSE, &token,
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(int t) {
            notify_cancel(t);
            done = YES;
            dispatch_semaphore_signal(sem);
        });
    notify_post(FRYZZ_NOTIFY_REQUEST);
    // Wait max 3 seconds
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));

    if (!done) return MACH_PORT_NULL;

    // Check response
    NSString *resp = [NSString stringWithContentsOfFile:@FRYZZ_IPC_RESPONSE_PATH
                                              encoding:NSUTF8StringEncoding error:nil];
    if (![@"ok" isEqualToString:resp]) return MACH_PORT_NULL;

    // Retrieve stashed port from our registered ports array
    return PortStash_Lookup();
}
