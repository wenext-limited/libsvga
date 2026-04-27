const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const static_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    static_module.linkSystemLibrary("z", .{});
    const package_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    package_module.linkSystemLibrary("z", .{});

    const lib = b.addLibrary(.{
        .name = "svga",
        .linkage = .static,
        .root_module = static_module,
    });
    lib.installHeader(b.path("include/svga.h"), "svga.h");
    const install_lib = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&install_lib.step);
    if (isDarwin(target.result.os.tag)) {
        const rearchive = b.addSystemCommand(&.{"sh"});
        rearchive.addFileArg(b.path("tools/rearchive_macos.sh"));
        rearchive.addArg(b.getInstallPath(.lib, "libsvga.a"));
        rearchive.step.dependOn(&install_lib.step);
        b.getInstallStep().dependOn(&rearchive.step);
    }

    const probe_module = b.createModule(.{
        .root_source_file = b.path("tools/svga_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    probe_module.addImport("libsvga", package_module);
    const probe = b.addExecutable(.{
        .name = "svga_probe",
        .root_module = probe_module,
    });
    b.installArtifact(probe);

    const run_probe = b.addRunArtifact(probe);
    if (b.args) |args| {
        run_probe.addArgs(args);
    }
    const probe_step = b.step("probe", "Parse SVGA files and print movie metadata");
    probe_step.dependOn(&run_probe.step);

    const tests = b.addTest(.{
        .root_module = static_module,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run libsvga tests");
    test_step.dependOn(&run_tests.step);
}

fn isDarwin(os_tag: std.Target.Os.Tag) bool {
    return switch (os_tag) {
        .ios, .macos, .tvos, .visionos, .watchos => true,
        else => false,
    };
}
