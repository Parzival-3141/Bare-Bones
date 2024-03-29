const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

const os_name = "myos";

/// Meant to be formatted with `.{ os_name, kernel_filename }`
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
    const target = std.zig.CrossTarget{
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
        .root_source_file = .{ .path = "src/kernel.zig" },
        .target = target,
        .optimize = optimize,
        .use_lld = true,
    });
    kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    kernel.code_model = .kernel;
    // kernel.emit_asm = .emit;

    // @NOTE: stack overflow/smash protector only works on targets with a libc (https://github.com/ziglang/zig/issues/4542),
    // but stack overflow detection is enabled by default in safe build modes.
    // We use ReleaseSafe because of this.
    // kernel.stack_protector = true;

    const kernel_install = b.addInstallArtifact(kernel, .{});
    b.getInstallStep().dependOn(&kernel_install.step);

    {
        const iso = addISO(b, os_name ++ ".iso", kernel_install);
        const build_iso = b.step("iso", "Build operating system ISO image (requires GRUB)");
        build_iso.dependOn(&iso.step);

        const iso_run_cmd = b.addSystemCommand(&.{ "qemu-system-i386", "-cdrom", os_name ++ ".iso" });
        iso_run_cmd.step.dependOn(&iso.step);

        const iso_run_step = b.step("run-iso", "Executes ISO image through QEMU");
        iso_run_step.dependOn(&iso_run_cmd.step);
    }

    {
        const elf_run_cmd = b.addSystemCommand(&.{
            "qemu-system-i386",
            "-no-reboot",
            "-no-shutdown",
            "-serial",
            "stdio",
            // "-D",
            // "./qemu.log",
            "-kernel",
            b.getInstallPath(kernel_install.dest_dir.?, kernel.out_filename),
        });
        elf_run_cmd.step.dependOn(b.getInstallStep());

        if (b.option([]const u8, "qemu-d", "Pass '-d' flags to QEMU. (Must be comma seperated with no spaces)")) |args| {
            elf_run_cmd.addArgs(&.{ "-d", args });
        }

        const elf_run_step = b.step("run-kernel", "Executes raw kernel binary through QEMU");
        elf_run_step.dependOn(&elf_run_cmd.step);
    }
}

fn addISO(b: *Build, comptime iso_name: []const u8, kernel_install: *Step.InstallArtifact) *BuildIsoStep {
    const kernel_filename = kernel_install.artifact.out_filename;
    const iso = BuildIsoStep.create(
        b,
        iso_name,
        // @Todo: must use unix-style relative path when using WSL
        // b.getInstallPath(kernel_install.dest_dir, kernel_filename),
        b.fmt("zig-out/bin/{s}", .{kernel_filename}),
        kernel_filename,
        b.option(bool, "wsl", "Run GRUB commands through WSL") orelse false,
        b.option(bool, "verify-mboot", "Verify kernel is Multiboot compliant") orelse false,
    );

    iso.step.dependOn(&kernel_install.step);
    return iso;
}

const BuildIsoStep = struct {
    step: Step,
    iso_name: []const u8,
    kernel_path: []const u8,
    kernel_filename: []const u8,
    use_wsl: bool,
    verify_multiboot: bool,

    pub fn create(
        owner: *Build,
        comptime iso_name: []const u8,
        kernel_path: []const u8,
        kernel_filename: []const u8,
        use_wsl: bool,
        verify_multiboot: bool,
    ) *BuildIsoStep {
        const self = owner.allocator.create(BuildIsoStep) catch @panic("OOM");
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = "build-iso " ++ iso_name,
                .owner = owner,
                .makeFn = make,
            }),
            .iso_name = iso_name,
            .kernel_path = kernel_path,
            .kernel_filename = kernel_filename,
            .use_wsl = use_wsl,
            .verify_multiboot = verify_multiboot,
        };
        return self;
    }

    fn make(step: *Step, prog_node: *std.Progress.Node) anyerror!void {
        var sub_node = prog_node.start("", 3);
        sub_node.activate();
        defer sub_node.end();

        step.result_cached = false;

        const b = step.owner;
        const self = @fieldParentPtr(BuildIsoStep, "step", step);
        const fs = std.fs;

        const kernel_path_posix = normalize_path_seperators(b.allocator, self.kernel_path) catch @panic("OOM");
        defer b.allocator.free(kernel_path_posix);

        if (self.verify_multiboot) {
            // Verify multiboot header
            // [wsl] grub-file --is-x86-multiboot zig-out/bin/kernel.bin
            sub_node.setName("verifying multiboot header");
            sub_node.context.refresh();

            const verify_cmd = &[_][]const u8{
                if (self.use_wsl) "wsl" else "",
                "grub-file",
                "--is-x86-multiboot",
                kernel_path_posix,
            };

            const verify_result = std.ChildProcess.exec(.{
                .allocator = b.allocator,
                .argv = verify_cmd,
            }) catch |err| {
                const cmd = std.mem.join(b.allocator, " ", verify_cmd) catch @panic("OOM");
                defer b.allocator.free(cmd);

                step.addError(
                    "VerifyMultibootFailed:\nVerify command failed with error {s}:\n{s}",
                    .{ @errorName(err), cmd },
                ) catch @panic("OOM");
                return error.MakeFailed;
            };

            if (verify_result.stderr.len != 0) {
                step.addError("VerifyMultibootFailed:\n{s}", .{verify_result.stderr}) catch @panic("OOM");
                return error.MakeFailed;
            }

            if (verify_result.term.Exited != 0) return error.NotMultibootCompliant;
        }
        sub_node.completeOne();

        // Create isodir directory
        sub_node.setName("constructing isodir");
        sub_node.context.refresh();

        try fs.cwd().makePath(b.pathFromRoot("isodir/boot/grub"));
        var bootdir = try fs.cwd().openDir(b.pathFromRoot("isodir/boot"), .{});
        defer bootdir.close();

        try fs.cwd().copyFile(self.kernel_path, bootdir, self.kernel_filename, .{});
        // try fs.cwd().copyFile(b.pathFromRoot("src/grub.cfg"), bootdir, "grub/grub.cfg", .{});
        try bootdir.writeFile("grub/grub.cfg", get_grub_cfg(b, self.kernel_filename));
        sub_node.completeOne();

        // Build iso
        // [wsl] grub-mkrescue -o self.iso_name isodir
        sub_node.setName(b.fmt("building {s}", .{self.iso_name}));
        sub_node.context.refresh();

        const mkrescue_cmd = &[_][]const u8{
            if (self.use_wsl) "wsl" else "",
            "grub-mkrescue",
            "-o",
            self.iso_name,
            "isodir",
        };

        const mkrescue_result = std.ChildProcess.exec(.{
            .allocator = b.allocator,
            .argv = mkrescue_cmd,
        }) catch |err| {
            const cmd = std.mem.join(b.allocator, " ", mkrescue_cmd) catch @panic("OOM");
            defer b.allocator.free(cmd);

            step.addError(
                "Build command failed with error {s}:\n{s}",
                .{ @errorName(err), cmd },
            ) catch @panic("OOM");
            return error.MakeFailed;
        };
        std.debug.print("\n{s}", .{mkrescue_result.stderr});

        if (mkrescue_result.term.Exited != 0) return error.mkescueFailed;

        sub_node.completeOne();
        sub_node.context.refresh();
    }
};

fn normalize_path_seperators(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]u8 {
    const result = try allocator.dupe(u8, path);
    for (result) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return result;
}
