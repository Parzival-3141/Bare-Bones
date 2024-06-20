const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

const os_name = "myos";

fn get_grub_cfg(b: *Build, kernel_filename: []const u8) []const u8 {
    const grub_cfg =
        \\set default=0
        \\set timeout=0
        \\
        \\menuentry "{s}" {{
        \\    multiboot /boot/{s}
        \\    boot
        \\}}
    ;

    return b.fmt(grub_cfg, .{ os_name, kernel_filename });
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *Build) !void {
    const target = std.Target.Query{
        .cpu_arch = .x86,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_source_file = b.path("src/kernel.zig"),
        .target = b.resolveTargetQuery(target),
        .optimize = optimize,
        .use_lld = true,
    });
    kernel.setLinkerScriptPath(b.path("src/linker.ld"));
    kernel.root_module.code_model = .kernel;

    // @NOTE: stack overflow/smash protector only works on targets with a libc (https://github.com/ziglang/zig/issues/4542),
    // but stack overflow detection is enabled by default in safe build modes.
    // We use ReleaseSafe because of this.
    // kernel.stack_protector = true;

    b.installArtifact(kernel);

    {
        const kernel_qemu_cmd = b.addSystemCommand(&.{
            "qemu-system-i386",
            "-no-reboot",
            "-no-shutdown",
            "-serial",
            "stdio",
            "-D",
            "./qemu.log",
            "-kernel",
        });
        kernel_qemu_cmd.addArtifactArg(kernel);

        if (b.option([]const u8, "qemu-d", "Pass '-d' flags to QEMU. (Must be comma seperated with no spaces)")) |args| {
            kernel_qemu_cmd.addArgs(&.{ "-d", args });
        }

        const kernel_qemu_step = b.step("run-kernel", "Executes raw kernel binary through QEMU");
        kernel_qemu_step.dependOn(&kernel_qemu_cmd.step);
    }

    const use_wsl = b.option(bool, "wsl", "Run GRUB commands through WSL") orelse false;

    if (b.option(bool, "verify-mboot", "Verify kernel is Multiboot compliant") orelse false) {
        // [wsl] grub-file --is-x86-multiboot zig-out/bin/kernel.bin
        const verify_cmd = b.addSystemCommand(&.{
            if (use_wsl) "wsl" else "",
            "grub2-file",
            "--is-x86-multiboot",
        });
        verify_cmd.addArtifactArg(kernel);
        verify_cmd.expectExitCode(0);
    }

    // Build and run OS ISO
    {
        const isodir = b.addWriteFiles();
        _ = isodir.add("boot/grub/grub.cfg", get_grub_cfg(b, kernel.name));
        _ = isodir.addCopyFile(kernel.getEmittedBin(), b.fmt("boot/{s}", .{kernel.name}));

        const iso_name = os_name ++ ".iso";
        const mkrescue_cmd = b.addSystemCommand(&.{
            if (use_wsl) "wsl" else "",
            "grub2-mkrescue",
            "-o",
        });
        const iso = mkrescue_cmd.addOutputFileArg(iso_name);
        mkrescue_cmd.addDirectoryArg(isodir.getDirectory());

        const build_iso = b.step("iso", "Build operating system ISO image (requires GRUB)");
        build_iso.dependOn(&b.addInstallBinFile(iso, iso_name).step);

        const iso_run_cmd = b.addSystemCommand(&.{ "qemu-system-i386", "-cdrom" });
        iso_run_cmd.addFileArg(iso);

        const iso_run_step = b.step("run-iso", "Executes ISO image through QEMU");
        iso_run_step.dependOn(&iso_run_cmd.step);
    }
}
