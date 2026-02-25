# XYRIS_OS
## First version of XYRIS_OS!

The main ESP rendering logic is implemented in the update_data method. On git simple demo, not real code for some kind of game.

## How to use?
**1. Get the PID and task port of your game:**
```
Current:
- (void)SetUpBase {
    pid_t pid = get_pid_by_name("DeltaForceClient");
    if (pid > 0){
        initialize_task_port(pid);
        task_t task = global_task_port;
        if (task != MACH_PORT_NULL) {
            LDVQuangBase = get_image_base_address(task, "DeltaForceClient");
        }
    }
}
Origin:
// pid_t pid = get_pid_by_name("MainBinaryOfGame");
// task_t task = get_task_by_pid(pid);
// OR
// task_t task = get_task_for_PID(pid); <- ezz detect
```

**2. Read world addresses and pointers like this.:**
```c
long Gworld = QuangRead<long>(LDVQuangBase + 0x23456789);
long Pointer = QuangRead<long>(Gworld + 0x123);

```

### Archive Note
This code snippet was written in late December 2025 and illustrates how UE4 game titles like DeltaForce read and write.<br>

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


> _"Some paths dissolve as others take form. iOS continues to evolve, time moves forward, and I am shaped along with it."_ — **LDVQuang2306**
