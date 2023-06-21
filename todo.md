# [Creating an Operating System](https://wiki.osdev.org/Creating_an_Operating_System)
## Phase I
In this phase we will set up a toolchain and create a basic kernel that will become the core of the new operating system.

- [x] [Creating a Hello World kernel](https://wiki.osdev.org/Bare_Bones) \
Your next task is to make a simple hello world kernel that is able to start up, print a message to the output device and then loop endlessly. While simple and useless, it will serve as a great example and starting point for a real system, as well as confirm that your testing environment works correctly.

- [x] [Setting up a Project](https://wiki.osdev.org/Meaty_Skeleton) \
With a basic working example, your next task is to set up a build infrastructure using whatever build system you see fit. Be careful in your choices of technology, GNU Make is easier to port than Python.

- [ ] [Stack Smash Protector](https://wiki.osdev.org/Stack_Smashing_Protector) \
Early is not too soon to think about security and robustness. You can take advantage of the optional stack smash protector offered by modern compilers that detect stack buffer overruns rather than behaving unexpectedly (or nothing happening, if unlucky).

- [x] [Multiboot](https://wiki.osdev.org/Multiboot) \
It's useful to know what features and information the bootloader offers the kernel, as this may help you get memory maps, set video modes, and even kernel symbol tables.

- [ ] [Global Descriptor Table](https://wiki.osdev.org/Global_Descriptor_Table) \
The Global Descriptor Table is an important part of the processor state and it should as such be one of the first things that are initialized. It probably makes a lot of sense to set up it even prior to kernel_early.

- [ ] [Memory Management](https://wiki.osdev.org/Memory_Management) \
Memory allocation and management is one of the most basic functions in an operating system. You need to keep track of physical page frames, what ranges of virtual memory are used, and implementing a heap (malloc, free) upon it for internal kernel use.

- [ ] [Interrupts](https://wiki.osdev.org/Interrupts) \
Your kernel needs to handle asynchronous events sent by the hardware to function properly.

- [ ] [Multithreaded Kernel](https://wiki.osdev.org/index.php?title=Multithreaded_Kernel&action=edit&redlink=1) \
It is best to go multithreaded early in the development of your kernel or you'll end up rewriting parts of your kernel. We'll certainly need this when we add processes later on.

- [ ] [Keyboard](https://wiki.osdev.org/Keyboard) \
Your operating system will certainly need support for reading input from the computer operator so it can adapt its behavior to his wishes.

- [ ] [Internal Kernel Debugger](https://wiki.osdev.org/Internal_Kernel_Debugger) \
It is very useful for a multithreaded kernel to have built-in debugging facilities early on. You could have a magic key that stops the entire kernel and dumps the user to a mini-kernel with a command line interface for debugging. It could know the data structures used by the scheduler to list all the threads and perform call traces.

- [ ] [Filesystem Support](https://wiki.osdev.org/Filesystem) \
It'll be useful to have support for filesystems early on and transferring files onto your operating system using a [initialization ramdisk](https://wiki.osdev.org/Initrd).

[Going further on x86](https://wiki.osdev.org/Going_Further_on_x86)
 - [Setting_Up_Paging](https://wiki.osdev.org/Setting_Up_Paging)
 - [GDT_Tutorial](https://wiki.osdev.org/GDT_Tutorial)
