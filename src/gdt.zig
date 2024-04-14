/// Segment Descriptor
pub const Descriptor = packed struct(u64) {
    limit_low: u16,
    base_low: u24,
    access: AccessFlags,
    limit_high: u4,
    flags: Flags,
    base_high: u8,

    pub const AccessFlags = packed struct(u8) {
        ///  Best left false, the CPU will set it when the segment is accessed
        accessed: bool = false,
        /// For code segments:
        /// Readable bit. If false, read access for this segment is not allowed. If true, read access is allowed. Write access is never allowed for code segments.
        /// For data segments:
        /// Writeable bit. If false, write access for this segment is not allowed. If true, write access is allowed. Read access is always allowed for data segments.
        read_write: bool = true,

        /// For data selectors: Direction bit. If false the segment grows up. If true the segment grows down, ie. the Offset has to be greater than the Limit.
        /// For code selectors: Conforming bit. If false code in this segment can only be executed from the ring set in DPL.
        /// If true code in this segment can be executed from an equal or lower privilege level. For example, code in
        /// ring 3 can far-jump to conforming code in a ring 2 segment. The DPL field represent the highest privilege level
        /// that is allowed to execute the segment. For example, code in ring 0 cannot far-jump to a conforming code segment
        /// where DPL is 2, while code in ring 2 and 3 can. Note that the privilege level remains the same,
        /// ie. a far-jump from ring 3 to a segment with a DPL of 2 remains in ring 3 after the jump.
        direction_conforming: bool = false,

        ///  If false the descriptor defines a data segment. If true it defines a code segment which can be executed from.
        executable: bool,

        /// If false the descriptor defines a system segment (eg. a Task State Segment). If true it defines a code or data segment.
        descriptor_type: enum(u1) { system = 0, code_data = 1 } = .code_data,
        privilege: PrivilegeLevel,

        /// Allows an entry to refer to a valid segment. Must be true for any valid segment.
        present: bool = true,
    };

    pub const Flags = packed struct(u4) {
        _reserved: u1 = 0,

        /// If true, the descriptor defines a 64-bit code segment. When set,
        /// `size` should always be false. For any other type of segment
        /// (other code types or any data segment), it should be false.
        is_64bit: bool,

        /// Segment size.
        /// A GDT can have both 16-bit and 32-bit selectors at once.
        size: enum(u1) { u16 = 0, u32 = 1 },

        /// Indicates the size the Limit value is scaled by.
        /// If false, the Limit is in 1 Byte blocks (byte granularity).
        /// If true, the Limit is in 4 KiB blocks (page granularity).
        granularity: enum(u1) { byte = 0, @"4KiB" = 1 },
    };
};

pub const PrivilegeLevel = enum(u2) {
    /// Highest privilege, least protection (kernel/supervisor)
    ring0 = 0,

    // Used for device drivers. They offer more protection, but not as much as ring 3.
    ring1 = 1,
    ring2 = 2,

    /// Lowest privilege, most protection (user-space)
    ring3 = 3,
};

/// Segment Selector
pub const Selector = packed struct(u16) {
    /// The requested Privilege Level of the selector, determines if the
    /// selector is valid during permission checks and may set execution
    /// or memory access privilege.
    privilege: PrivilegeLevel,

    /// Specifies which descriptor table to use.
    table: enum(u1) { gdt = 0, ldt = 1 },

    /// Index of the GDT or LDT entry referenced by the selector.
    index: u13,
};

/// Descriptor Table Register.
/// Used for both GDT and IDT structures.
pub const DescTablePtr = packed struct(u48) {
    /// Size of the table in bytes - 1
    size: u16,

    /// Linear address of the table (not the physical address, paging applies).
    address: u32,
};

const PAGING_32BIT = Descriptor.Flags{
    .is_64bit = false,
    .size = .u32,
    .granularity = .@"4KiB",
};

const TABLE_SIZE: u16 = @sizeOf(Descriptor) * table.len;
const table = [_]Descriptor{
    // Null Descriptor
    make_entry(0, 0, @bitCast(@as(u8, 0x0)), @bitCast(@as(u4, 0x0))),

    // https://stackoverflow.com/questions/23978486/far-jump-in-gdt-in-bootloader
    // We set all segments to the 0..0xFFFFF range, overlapping them.
    // Kernel segments are priviledged while Userland segments arent.
    // This causes memory segmentation to be disabled (citation needed)
    // and enable paging.

    // Kernel Code Descriptor
    make_entry(0, 0xFFFFF, .{ .executable = true, .privilege = .ring0 }, PAGING_32BIT),

    // Kernel Data Descriptor
    make_entry(0, 0xFFFFF, .{ .executable = false, .privilege = .ring0 }, PAGING_32BIT),

    // User Code Descriptor
    make_entry(0, 0xFFFFF, .{ .executable = true, .privilege = .ring3 }, PAGING_32BIT),

    // User Data Descriptor
    make_entry(0, 0xFFFFF, .{ .executable = false, .privilege = .ring3 }, PAGING_32BIT),

    // TSS Descriptor (setup at runtime)
    // make_entry(
    //     0,
    //     0,
    //     .{
    //         .read_write = false,
    //         .executable = true,
    //         .descriptor_type = .system,
    //         .privilege = .ring0,
    //     },
    //     @bitCast(@as(u4, 0x0)),
    // ),
};

pub const KERNEL_CODE_SELECTOR = Selector{ .privilege = .ring0, .table = .gdt, .index = 1 };
pub const KERNEL_DATA_SELECTOR = Selector{ .privilege = .ring0, .table = .gdt, .index = 2 };

var gdt_ptr = DescTablePtr{
    .size = TABLE_SIZE - 1,
    .address = undefined,
};

pub fn load() void {
    asm volatile ("cli");

    // @Todo: initialize TSS here

    gdt_ptr.address = @intFromPtr(&table);

    // Load GDT into CPU
    asm volatile ("lgdt %[gdt_ptr]"
        :
        : [gdt_ptr] "p" (&gdt_ptr),
    );

    // Reload segment registers
    // Load kernel data segment into the other segment registers
    asm volatile (
        \\mov %%bx, %%ds
        \\mov %%bx, %%es
        \\mov %%bx, %%fs
        \\mov %%bx, %%gs
        \\mov %%bx, %%ss
        :
        : [select] "{bx}" (KERNEL_DATA_SELECTOR),
    );
    // Load kernel code segment into the CS register
    asm volatile (
        \\ljmp %[select], $1f
        \\1:
        :
        : [select] "n" (KERNEL_CODE_SELECTOR),
    );
}

pub fn get_loaded() DescTablePtr {
    var ptr = DescTablePtr{ .size = 0, .address = 0 };
    asm volatile ("sgdt %[out]"
        : [out] "=m" (ptr),
    );
    return ptr;
}

fn make_entry(base: u32, limit: u20, access: Descriptor.AccessFlags, flags: Descriptor.Flags) Descriptor {
    return Descriptor{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .access = access,
        .limit_high = @truncate(limit >> 16),
        .flags = flags,
        .base_high = @truncate(base >> 24),
    };
}
