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

    /// Available memory from BIOS
    mem_lower: u32,
    mem_upper: u32,

    /// "root" partition
    boot_device: u32,

    /// Kernel command line
    cmdline: u32,

    /// Boot-Module list
    mods_count: u32,
    mods_addr: u32,

    /// Unused
    // union
    // {
    //   multiboot_aout_symbol_table_t aout_sym;
    //   multiboot_elf_section_header_table_t elf_sec;
    // } u;
    u: u128,

    /// Memory Mapping buffer
    mmap_length: u32,
    mmap_addr: u32,

    /// Drive Info buffer
    drives_length: u32,
    drives_addr: u32,

    /// ROM configuration table
    config_table: u32,

    /// Boot Loader Name
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
        elf_shdr: bool,

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
