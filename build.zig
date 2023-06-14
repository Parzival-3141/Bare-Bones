const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const target = std.zig.CrossTarget{
        .cpu_arch = .x86,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
    };

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const kernel = b.addExecutable(.{
        .name = "kernel.bin",
        .root_source_file = .{ .path = "src/boot.zig" },
        .target = target,
        .optimize = optimize,
    });
    kernel.setLinkerScriptPath(.{ .path = "src/linker.ld" });
    kernel.code_model = .kernel;

    const kernel_install = b.addInstallArtifact(kernel);
    b.getInstallStep().dependOn(&kernel_install.step);
    build_iso(b, kernel_install, kernel.out_filename);
}

fn build_iso(b: *std.Build, kernel_install: *Step.InstallArtifact, kernel_filename: []const u8) void {
    const iso = BuildIsoStep.create(b, b.getInstallPath(kernel_install.dest_dir, kernel_filename), kernel_filename);
    iso.step.dependOn(&kernel_install.step);
    b.getInstallStep().dependOn(&iso.step);
}

// @Todo: custom step library. Automate this with comptime functions
const Step = std.Build.Step;
const BuildIsoStep = struct {
    step: Step,
    kernel_path: []const u8,
    kernel_filename: []const u8,

    pub fn create(owner: *std.Build, kernel_path: []const u8, kernel_filename: []const u8) *BuildIsoStep {
        const self = owner.allocator.create(BuildIsoStep) catch @panic("OOM");
        const name = "iso";
        self.* = .{
            .step = Step.init(.{
                .id = .custom,
                .name = name,
                .owner = owner,
                .makeFn = make,
            }),
            .kernel_path = kernel_path,
            .kernel_filename = kernel_filename,
        };
        return self;
    }

    fn make(step: *Step, prog_node: *std.Progress.Node) !void {
        // fast enough that we don't need progress.
        _ = prog_node;

        const b = step.owner;
        const self = @fieldParentPtr(BuildIsoStep, "step", step);
        const fs = std.fs;

        try fs.cwd().makePath(b.pathFromRoot("isodir/boot/grub"));
        var bootdir = try fs.cwd().openDir(b.pathFromRoot("isodir/boot"), .{});
        defer bootdir.close();

        try fs.cwd().copyFile(self.kernel_path, bootdir, self.kernel_filename, .{});
        try fs.cwd().copyFile(b.pathFromRoot("src/grub.cfg"), bootdir, "grub/grub.cfg", .{});
    }
};
