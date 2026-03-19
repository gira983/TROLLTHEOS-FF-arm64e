#import "PortStash.h"
#import <mach/mach.h>
#import <stdio.h>

// HUD (root) stashes game task port into App's registered port array
// Kernel handles the port right transfer automatically
bool PortStash_Register(mach_port_t appTask, mach_port_t gameTask) {
    if (appTask == MACH_PORT_NULL || gameTask == MACH_PORT_NULL) return false;

    mach_port_array_t ports = (mach_port_array_t)malloc(sizeof(mach_port_t));
    if (!ports) return false;
    ports[0] = gameTask;

    kern_return_t kr = mach_ports_register(appTask, ports, 1);
    free(ports);

    return (kr == KERN_SUCCESS);
}

// App retrieves stashed game task port from its own registered port array
mach_port_t PortStash_Lookup(void) {
    mach_port_array_t ports = NULL;
    mach_msg_type_number_t count = 0;

    kern_return_t kr = mach_ports_lookup(mach_task_self(), &ports, &count);
    if (kr != KERN_SUCCESS || count == 0 || !ports) return MACH_PORT_NULL;

    mach_port_t result = ports[0];
    vm_deallocate(mach_task_self(), (vm_address_t)ports, count * sizeof(mach_port_t));

    // Validate: check it's actually a task port
    if (result == MACH_PORT_NULL) return MACH_PORT_NULL;
    mach_port_type_t type;
    if (mach_port_type(mach_task_self(), result, &type) != KERN_SUCCESS) return MACH_PORT_NULL;
    if (!(type & MACH_PORT_TYPE_SEND)) return MACH_PORT_NULL;

    return result;
}
