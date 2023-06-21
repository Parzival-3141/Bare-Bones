/// Magic value that lets the bootloader find the multiboot header
pub const HEADER_MAGIC = 0x1BADB002;

/// The bootloader should leave this value in the EAX register to signal it
/// booted us correctly.
pub const BOOTLOADER_MAGIC = 0x2BAD2B002;

/// Should be embedded in the first 8KiB of the kernel for a bootloader to find
pub const Header = extern struct {
    magic: u32,
    flags: Flags,
    checksum: u32,

    pub fn init(flags: Flags) Header {
        return .{
            .magic = HEADER_MAGIC,
            .flags = flags,
            .checksum = ~(HEADER_MAGIC +% @bitCast(u32, flags)) +% 1,
        };
    }

    pub const Flags = packed struct(u32) {
        /// Align the OS and loaded modules on 4KB page boundaries.
        @"align": bool = false,

        /// Include information about avaliable memory in 'mem_*' fields of the
        /// Info struct. Also include memory map info in 'mmap_*' fields if the
        /// bootloader supports it and it exists.
        mem_info: bool = false,

        /// Include information about the video mode table.
        video_table: bool = false,

        _padding: u29 = 0,

        // @Todo: Unused. Requires the rest of the Header fields and Info.u to be specified,
        // so I'm ignoring it for now.
        // _padding: u13 = 0,
        // aout_or_elf_table: bool = false,
    };
};

pub const Info = packed struct {
    flags: Flags,

    // Available memory from BIOS
    /// Maximum value is 640 KB
    mem_lower: u32,
    /// Maximum value is the address of the first upper memory hole minus 1 megabyte.
    /// It is not guaranteed to be this value.
    mem_upper: u32,

    /// "root" partition
    boot_device: u32,

    /// Kernel command line
    cmdline: u32,

    // Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    /// Active element is determined by `aout_syms` and `elf_section_header` flags
    syms: packed union {
        aout: AOut_SymbolTableInfo,
        elf: ELF_SectionHeaderInfo,

        comptime {
            const assert = @import("std").debug.assert;
            assert(@sizeOf(@This()) == @sizeOf(u128));
            assert(@bitSizeOf(@This()) == @bitSizeOf(u128));
        }
    },

    // Memory Mapping buffer
    mmap_length: u32,
    mmap_addr: u32,

    // Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    /// ROM configuration table
    /// Address of the ROM configuration table returned by the GET CONFIGURATION BIOS call.
    /// If the BIOS call fails, then the size of the table must be zero.
    config_table: u32,

    /// Boot Loader Name
    /// Physical address of the name of a boot loader booting the kernel.
    /// The name is a normal C-style zero-terminated string.
    boot_loader_name: u32,

    /// APM table
    apm_table: u32,

    // Video
    vbe_control_info: u32,
    vbe_mode_info: u32,
    vbe_mode: u16,
    vbe_interface_seg: u16,
    vbe_interface_off: u16,
    vbe_interface_len: u16,

    // @Note: all this is unused... so I'll just ignore it
    //   framebuffer_addr: u64,
    //   framebuffer_pitch: u32,
    //   framebuffer_width: u32,
    //   framebuffer_height: u32,
    //   framebuffer_bpp: u8,
    // #define MULTIBOOT_FRAMEBUFFER_TYPE_INDEXED 0
    // #define MULTIBOOT_FRAMEBUFFER_TYPE_RGB     1
    // #define MULTIBOOT_FRAMEBUFFER_TYPE_EGA_TEXT     2
    //   framebuffer_type: u8,
    //   union
    //   {
    //     struct
    //     {
    //       framebuffer_palette_addr: u32,
    //       framebuffer_palette_num_colors: u16,
    //     },
    //     struct
    //     {
    //       framebuffer_red_field_position: u8,
    //       framebuffer_red_mask_size: u8,
    //       framebuffer_green_field_position: u8,
    //       framebuffer_green_mask_size: u8,
    //       framebuffer_blue_field_position: u8,
    //       framebuffer_blue_mask_size: u8,
    //     },
    //   },

    pub const Flags = packed struct(u32) {
        /// Is there basic lower/upper memory information?
        memory: bool,

        /// Is there a boot device set?
        bootdev: bool,

        /// Is the command-line defined?
        cmdline: bool,

        /// are there modules to do something with?
        mods: bool,

        // These next two are mutually exclusive
        /// Is there a symbol table loaded?
        aout_syms: bool,
        /// Is there an ELF section header table?
        elf_section_header: bool,

        /// Is there a full memory map?
        mem_map: bool,

        /// Is there drive info?
        drive_info: bool,

        /// Is there a config table?
        config_table: bool,

        /// Is there a boot loader name?
        boot_loader_name: bool,

        /// Is there a APM table?
        apm_table: bool,

        /// Is there video information?
        vbe_info: bool,
        framebuffer_info: bool,

        _padding: u19 = 0,
    };
};

pub const BootModule = packed struct {
    // Module memory is start_addr to end_addr-1 (inclusive)
    start_addr: u32,
    end_addr: u32,

    /// Input string passed from the bootloader. Up to the OS for interpretation.
    /// Type: [*:0]const u8
    cmdline: u32,

    _reserved: u32,
};

pub const AOut_SymbolTableInfo = packed struct {
    //         +-------------------+
    // 28      | tabsize           |
    // 32      | strsize           |
    // 36      | addr              |
    // 40      | reserved (0)      |
    //         +-------------------+
    // These indicate where the symbol table from an a.out kernel image can be found.
    // ‘addr’ is the physical address of the size (4-byte unsigned long) of an array
    // of a.out format nlist structures, followed immediately by the array itself,
    // then the size (4-byte unsigned long) of a set of zero-terminated ASCII strings
    // (plus sizeof(unsigned long) in this case), and finally the set of strings itself.
    // ‘tabsize’ is equal to its size parameter (found at the beginning of the symbol section),
    // and ‘strsize’ is equal to its size parameter (found at the beginning of the string section)
    // of the following string table to which the symbol table refers. Note that ‘tabsize’
    // may be 0, indicating no symbols, even if bit 4 in the ‘flags’ word is set.

    tab_size: u32,
    str_size: u32,
    addr: u32,

    _reserved: u32,
};

pub const ELF_SectionHeaderInfo = packed struct {
    //         +-------------------+
    // 28      | num               |
    // 32      | size              |
    // 36      | addr              |
    // 40      | shndx             |
    //         +-------------------+
    // These indicate where the section header table from an ELF kernel is,
    // the size of each entry, number of entries, and the string table used
    // as the index of names. They correspond to the ‘shdr_*’ entries
    // (‘shdr_num’, etc.) in the Executable and Linkable Format (ELF) specification
    // in the program header. All sections are loaded, and the physical address fields
    // of the ELF section header then refer to where the sections are in memory
    // (refer to the i386 ELF documentation for details as to how to read the section
    // header(s)). Note that ‘shdr_num’ may be 0, indicating no symbols, even if
    // bit 5 in the ‘flags’ word is set.

    num: u32,
    size: u32,
    addr: u32,
    shndx: u32,
};

pub const MemoryMapEntry = packed struct {
    //         +-------------------+
    // -4      | size              |
    //         +-------------------+
    // 0       | base_addr         |
    // 8       | length            |
    // 16      | type              |
    //         +-------------------+
    // where ‘size’ is the size of the associated structure in bytes, which can be greater
    // than the minimum of 20 bytes. ‘base_addr’ is the starting address. ‘length’ is the
    // size of the memory region in bytes. ‘type’ is the variety of address range represented,
    // where a value of 1 indicates available RAM, value of 3 indicates usable memory holding
    // ACPI information, value of 4 indicates reserved memory which needs to be preserved on
    // hibernation, value of 5 indicates a memory which is occupied by defective RAM modules
    // and all other values currently indicated a reserved area.
    //
    // The map provided is guaranteed to list all standard RAM that should be available for normal use.

    /// Size of the the current entry. Minimum of 20 bytes
    size: u32,
    base_addr: u64,
    /// Size of memory region in bytes
    length: u64,
    mem_type: MemoryType,

    pub const MemoryType = enum(u32) {
        available = 1,
        reserved = 2,

        /// Usable memory holding ACPI information
        acpi_reclaimable = 3,

        /// Reserved memory which needs to be preserved on hibernation
        nvs = 4,

        /// Occupied by defective RAM modules
        badram = 5,

        /// All other values currently indicated a reserved area
        _,
    };
};
