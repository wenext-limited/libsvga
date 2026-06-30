const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_system_zlib = b.option(
        bool,
        "system-zlib",
        "Use the target platform's libz instead of the portable Zig inflate backend",
    ) orelse defaultSystemZlib(target.result);
    const build_probe = b.option(
        bool,
        "build-probe",
        "Build and install the svga_probe executable",
    ) orelse true;
    const build_phase_bench = b.option(
        bool,
        "build-phase-bench",
        "Build and install the svga_phase_bench executable",
    ) orelse true;
    const release_version = b.option(
        []const u8,
        "release-version",
        "Version suffix used by the package-release step",
    ) orelse "dev";
    const release_dir = b.option(
        []const u8,
        "release-dir",
        "Output directory used by the package-release step",
    ) orelse "zig-out/release";
    const skip_apple_package = b.option(
        bool,
        "skip-apple-package",
        "Skip the Apple XCFramework archive in the package-release step",
    ) orelse false;
    const macos_min_version = b.option(
        []const u8,
        "macos-min-version",
        "Minimum macOS version used by the package-release Apple archive",
    ) orelse "12.0";
    const ios_min_version = b.option(
        []const u8,
        "ios-min-version",
        "Minimum iOS version used by the package-release Apple archive",
    ) orelse "15.0";

    // Make the zlib backend choice visible to parser.zig at comptime. Native
    // Apple builds default to libz for speed; packaged release artifacts pass
    // -Dsystem-zlib=false below so they stay self-contained.
    const options = b.addOptions();
    options.addOption(bool, "use_system_zlib", use_system_zlib);

    const static_module = b.createModule(.{
        .root_source_file = b.path("src/c_api.zig"),
        .target = target,
        .optimize = optimize,
    });
    static_module.addOptions("build_options", options);
    if (use_system_zlib) {
        static_module.linkSystemLibrary("z", .{});
    }
    const package_module = b.createModule(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    package_module.addOptions("build_options", options);
    if (use_system_zlib) {
        package_module.linkSystemLibrary("z", .{});
    }

    const lib = b.addLibrary(.{
        .name = "svga",
        .linkage = .static,
        .root_module = static_module,
    });
    lib.installHeader(b.path("include/svga.h"), "svga.h");
    const install_lib = b.addInstallArtifact(lib, .{});
    b.getInstallStep().dependOn(&install_lib.step);
    if (isDarwin(target.result.os.tag)) {
        // Zig may produce a thin archive with nested archive members on Darwin.
        // Re-archiving keeps the static library friendly to Xcode and SwiftPM.
        const rearchive = b.addSystemCommand(&.{"sh"});
        rearchive.addFileArg(b.path("tools/rearchive_macos.sh"));
        rearchive.addArg(b.getInstallPath(.lib, "libsvga.a"));
        rearchive.step.dependOn(&install_lib.step);
        b.getInstallStep().dependOn(&rearchive.step);
    }

    const probe_step = b.step("probe", "Parse SVGA files and print movie metadata");
    if (build_probe and canBuildProbe(target.result)) {
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
        probe_step.dependOn(&run_probe.step);
    }

    const phase_bench_step = b.step("phase-bench", "Benchmark libsvga parse phases over SVGA fixtures");
    if (build_phase_bench and canBuildProbe(target.result)) {
        const phase_bench_module = b.createModule(.{
            .root_source_file = b.path("tools/svga_phase_bench.zig"),
            .target = target,
            .optimize = optimize,
        });
        phase_bench_module.addImport("libsvga", package_module);
        const phase_bench = b.addExecutable(.{
            .name = "svga_phase_bench",
            .root_module = phase_bench_module,
        });
        b.installArtifact(phase_bench);

        const run_phase_bench = b.addRunArtifact(phase_bench);
        if (b.args) |args| {
            run_phase_bench.addArgs(args);
        }
        phase_bench_step.dependOn(&run_phase_bench.step);
    }

    const tests = b.addTest(.{
        .root_module = static_module,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run libsvga tests");
    test_step.dependOn(&run_tests.step);

    addReleasePackages(b, optimize, release_version, release_dir, skip_apple_package, macos_min_version, ios_min_version);
}

fn isDarwin(os_tag: std.Target.Os.Tag) bool {
    return switch (os_tag) {
        .ios, .macos, .tvos, .visionos, .watchos => true,
        else => false,
    };
}

fn defaultSystemZlib(target: std.Target) bool {
    return isDarwin(target.os.tag);
}

fn canBuildProbe(target: std.Target) bool {
    return switch (target.os.tag) {
        .freestanding => false,
        else => switch (target.cpu.arch) {
            .wasm32, .wasm64 => target.os.tag == .wasi,
            else => true,
        },
    };
}

const PortablePackage = struct {
    name: []const u8,
    target: []const u8,
};

// Non-Apple release packages are plain static-library bundles:
// include/svga.h, include/module.modulemap, lib/libsvga.a, and LICENSE.
const portable_packages = [_]PortablePackage{
    .{ .name = "android-aarch64", .target = "aarch64-linux-android" },
    .{ .name = "android-armv7", .target = "arm-linux-androideabi" },
    .{ .name = "android-x86_64", .target = "x86_64-linux-android" },
    .{ .name = "android-x86", .target = "x86-linux-android" },
    .{ .name = "wasm32-wasi", .target = "wasm32-wasi" },
    .{ .name = "wasm32-freestanding", .target = "wasm32-freestanding" },
    .{ .name = "wasm32-emscripten", .target = "wasm32-emscripten" },
};

/// Wire the `zig build package-release` step.
///
/// The step intentionally builds each target through a nested `zig build`
/// invocation so the normal install layout remains the single source of truth.
fn addReleasePackages(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    release_version: []const u8,
    release_dir: []const u8,
    skip_apple_package: bool,
    macos_min_version: []const u8,
    ios_min_version: []const u8,
) void {
    const package_step = b.step("package-release", "Build release tarballs for GitHub releases");
    const safe_version = sanitizePackageVersion(b, release_version);
    const optimize_arg = optimizeName(optimize);

    const mkdir_release = sideEffectCommand(b, &.{ "mkdir", "-p", release_dir });

    if (!skip_apple_package) {
        if (b.findProgram(&.{"xcodebuild"}, &.{})) |_| {
            addApplePackage(
                b,
                package_step,
                &mkdir_release.step,
                release_dir,
                safe_version,
                optimize_arg,
                macos_min_version,
                ios_min_version,
            );
        } else |_| {}
    }

    for (portable_packages) |package| {
        addPortablePackage(b, package_step, &mkdir_release.step, release_dir, safe_version, optimize_arg, package);
    }
}

/// Add a static-library tarball for one portable target.
fn addPortablePackage(
    b: *std.Build,
    package_step: *std.Build.Step,
    mkdir_release_step: *std.Build.Step,
    release_dir: []const u8,
    safe_version: []const u8,
    optimize_arg: []const u8,
    package: PortablePackage,
) void {
    const build_prefix = b.pathJoin(&.{ release_dir, "build", package.name });
    const package_root = b.pathJoin(&.{ release_dir, "pkg" });
    const package_dir = b.pathJoin(&.{ package_root, package.name });
    const include_dir = b.pathJoin(&.{ package_dir, "include" });
    const lib_dir = b.pathJoin(&.{ package_dir, "lib" });
    const archive = b.fmt("{s}/libsvga-{s}-{s}.tar.gz", .{ release_dir, package.name, safe_version });

    const build_target = sideEffectCommand(b, &.{
        b.graph.zig_exe,
        "build",
        b.fmt("-Dtarget={s}", .{package.target}),
        b.fmt("-Doptimize={s}", .{optimize_arg}),
        "-Dsystem-zlib=false",
        "-Dbuild-probe=false",
        "-p",
        build_prefix,
    });
    build_target.step.dependOn(mkdir_release_step);

    const mkdir_package = sideEffectCommand(b, &.{ "mkdir", "-p", include_dir, lib_dir });
    mkdir_package.step.dependOn(mkdir_release_step);

    const copy_header = sideEffectCommand(b, &.{
        "cp",
        b.pathJoin(&.{ build_prefix, "include", "svga.h" }),
        b.pathJoin(&.{ include_dir, "svga.h" }),
    });
    copy_header.step.dependOn(&build_target.step);
    copy_header.step.dependOn(&mkdir_package.step);

    const copy_modulemap = sideEffectCommand(b, &.{
        "cp",
        "include/module.modulemap",
        b.pathJoin(&.{ include_dir, "module.modulemap" }),
    });
    copy_modulemap.step.dependOn(&mkdir_package.step);

    const copy_library = sideEffectCommand(b, &.{
        "cp",
        b.pathJoin(&.{ build_prefix, "lib", "libsvga.a" }),
        b.pathJoin(&.{ lib_dir, "libsvga.a" }),
    });
    copy_library.step.dependOn(&build_target.step);
    copy_library.step.dependOn(&mkdir_package.step);

    const copy_license = sideEffectCommand(b, &.{ "cp", "LICENSE", b.pathJoin(&.{ package_dir, "LICENSE" }) });
    copy_license.step.dependOn(&mkdir_package.step);

    const tar_package = sideEffectCommand(b, &.{ "tar", "-C", package_root, "-czf", archive, package.name });
    tar_package.step.dependOn(&copy_header.step);
    tar_package.step.dependOn(&copy_modulemap.step);
    tar_package.step.dependOn(&copy_library.step);
    tar_package.step.dependOn(&copy_license.step);
    package_step.dependOn(&tar_package.step);
}

/// Add Apple release artifacts for Apple consumers.
///
/// The slices are still built by Zig. xcodebuild is only used for the final
/// XCFramework directory layout that Apple tools expect. The `.xcframework.zip`
/// places the XCFramework at the zip root, which is the layout SwiftPM binary
/// targets require.
fn addApplePackage(
    b: *std.Build,
    package_step: *std.Build.Step,
    mkdir_release_step: *std.Build.Step,
    release_dir: []const u8,
    safe_version: []const u8,
    optimize_arg: []const u8,
    macos_min_version: []const u8,
    ios_min_version: []const u8,
) void {
    const package_name = "apple-xcframework";
    const build_dir = b.pathJoin(&.{ release_dir, "build", "apple" });
    const package_root = b.pathJoin(&.{ release_dir, "pkg" });
    const package_dir = b.pathJoin(&.{ package_root, package_name });
    const xcframework = b.pathJoin(&.{ package_dir, "libsvga-static.xcframework" });
    const archive = b.fmt("{s}/libsvga-{s}-{s}.tar.gz", .{ release_dir, package_name, safe_version });
    const spm_archive = b.fmt("{s}/libsvga-static-{s}.xcframework.zip", .{ release_dir, safe_version });

    const mkdir_package = sideEffectCommand(b, &.{ "mkdir", "-p", package_dir });
    mkdir_package.step.dependOn(mkdir_release_step);

    const macos_slice = addAppleSlice(
        b,
        &mkdir_package.step,
        build_dir,
        "macos-arm64",
        b.fmt("aarch64-macos.{s}", .{macos_min_version}),
        optimize_arg,
    );
    const ios_slice = addAppleSlice(
        b,
        &mkdir_package.step,
        build_dir,
        "ios-arm64",
        b.fmt("aarch64-ios.{s}", .{ios_min_version}),
        optimize_arg,
    );
    const ios_simulator_slice = addAppleSlice(
        b,
        &mkdir_package.step,
        build_dir,
        "ios-simulator-arm64",
        b.fmt("aarch64-ios.{s}-simulator", .{ios_min_version}),
        optimize_arg,
    );

    const build_xcframework = sideEffectCommand(b, &.{
        "xcodebuild",
        "-create-xcframework",
        "-library",
        b.pathJoin(&.{ build_dir, "macos-arm64", "lib", "libsvga.a" }),
        "-headers",
        b.pathJoin(&.{ build_dir, "macos-arm64", "include" }),
        "-library",
        b.pathJoin(&.{ build_dir, "ios-arm64", "lib", "libsvga.a" }),
        "-headers",
        b.pathJoin(&.{ build_dir, "ios-arm64", "include" }),
        "-library",
        b.pathJoin(&.{ build_dir, "ios-simulator-arm64", "lib", "libsvga.a" }),
        "-headers",
        b.pathJoin(&.{ build_dir, "ios-simulator-arm64", "include" }),
        "-output",
        xcframework,
    });
    build_xcframework.step.dependOn(macos_slice);
    build_xcframework.step.dependOn(ios_slice);
    build_xcframework.step.dependOn(ios_simulator_slice);

    const copy_license = sideEffectCommand(b, &.{ "cp", "LICENSE", b.pathJoin(&.{ package_dir, "LICENSE" }) });
    copy_license.step.dependOn(&mkdir_package.step);

    const tar_package = sideEffectCommand(b, &.{ "tar", "-C", package_root, "-czf", archive, package_name });
    tar_package.step.dependOn(&build_xcframework.step);
    tar_package.step.dependOn(&copy_license.step);
    package_step.dependOn(&tar_package.step);

    const zip_xcframework = sideEffectCommand(b, &.{
        "ditto",
        "-c",
        "-k",
        "--sequesterRsrc",
        "--keepParent",
        xcframework,
        spm_archive,
    });
    zip_xcframework.step.dependOn(&build_xcframework.step);
    package_step.dependOn(&zip_xcframework.step);
}

/// Build one Apple slice and add the modulemap next to the installed header.
fn addAppleSlice(
    b: *std.Build,
    parent_step: *std.Build.Step,
    build_dir: []const u8,
    name: []const u8,
    target: []const u8,
    optimize_arg: []const u8,
) *std.Build.Step {
    const prefix = b.pathJoin(&.{ build_dir, name });

    const build_slice = sideEffectCommand(b, &.{
        b.graph.zig_exe,
        "build",
        b.fmt("-Dtarget={s}", .{target}),
        b.fmt("-Doptimize={s}", .{optimize_arg}),
        "-Dsystem-zlib=false",
        "-Dbuild-probe=false",
        "-p",
        prefix,
    });
    build_slice.step.dependOn(parent_step);

    const library = b.pathJoin(&.{ prefix, "lib", "libsvga.a" });
    const rearchive_library = sideEffectCommand(b, &.{
        "sh",
        "tools/rearchive_macos.sh",
        library,
    });
    rearchive_library.step.dependOn(&build_slice.step);

    const verify_library = sideEffectCommand(b, &.{
        "python3",
        "tools/verify_macho_archive_alignment.py",
        library,
    });
    verify_library.step.dependOn(&rearchive_library.step);

    const copy_modulemap = sideEffectCommand(b, &.{
        "cp",
        "include/module.modulemap",
        b.pathJoin(&.{ prefix, "include", "module.modulemap" }),
    });
    copy_modulemap.step.dependOn(&verify_library.step);

    return &copy_modulemap.step;
}

/// System commands used for packaging write files outside Zig's cache, so mark
/// them as side effects to force execution when the package step is requested.
fn sideEffectCommand(b: *std.Build, argv: []const []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(argv);
    run.setCwd(b.path("."));
    run.has_side_effects = true;
    return run;
}

fn optimizeName(optimize: std.builtin.OptimizeMode) []const u8 {
    return switch (optimize) {
        .Debug => "Debug",
        .ReleaseSafe => "ReleaseSafe",
        .ReleaseFast => "ReleaseFast",
        .ReleaseSmall => "ReleaseSmall",
    };
}

fn sanitizePackageVersion(b: *std.Build, version: []const u8) []const u8 {
    const safe = b.allocator.dupe(u8, version) catch @panic("OOM");
    for (safe) |*byte| {
        switch (byte.*) {
            '/', '\\', ' ' => byte.* = '-',
            else => {},
        }
    }
    return safe;
}
