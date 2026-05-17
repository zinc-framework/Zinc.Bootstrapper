const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;

// box2d v3 — pure C library with a stable C ABI. Compiles every .c in src/box2d/src.
// API export macro: BOX2D_EXPORT is enabled via `box2d_EXPORTS` (MSVC) or the
// __attribute__((visibility("default"))) path on Clang/GCC. We define
// `box2d_EXPORTS` unconditionally for the DLL build to match CMake's behavior.

const box2d_sources = [_][]const u8{
    "../src/box2d/src/aabb.c",
    "../src/box2d/src/arena_allocator.c",
    "../src/box2d/src/array.c",
    "../src/box2d/src/bitset.c",
    "../src/box2d/src/body.c",
    "../src/box2d/src/broad_phase.c",
    "../src/box2d/src/constraint_graph.c",
    "../src/box2d/src/contact.c",
    "../src/box2d/src/contact_solver.c",
    "../src/box2d/src/core.c",
    "../src/box2d/src/distance.c",
    "../src/box2d/src/distance_joint.c",
    "../src/box2d/src/dynamic_tree.c",
    "../src/box2d/src/geometry.c",
    "../src/box2d/src/hull.c",
    "../src/box2d/src/id_pool.c",
    "../src/box2d/src/island.c",
    "../src/box2d/src/joint.c",
    "../src/box2d/src/manifold.c",
    "../src/box2d/src/math_functions.c",
    "../src/box2d/src/motor_joint.c",
    "../src/box2d/src/mouse_joint.c",
    "../src/box2d/src/mover.c",
    "../src/box2d/src/prismatic_joint.c",
    "../src/box2d/src/revolute_joint.c",
    "../src/box2d/src/sensor.c",
    "../src/box2d/src/shape.c",
    "../src/box2d/src/solver.c",
    "../src/box2d/src/solver_set.c",
    "../src/box2d/src/table.c",
    "../src/box2d/src/timer.c",
    "../src/box2d/src/types.c",
    "../src/box2d/src/weld_joint.c",
    "../src/box2d/src/wheel_joint.c",
    "../src/box2d/src/world.c",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "box2d",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    var cflags = std.ArrayList([]const u8).init(b.allocator);
    defer cflags.deinit();
    cflags.append("-std=c17") catch unreachable;
    cflags.append("-fvisibility=hidden") catch unreachable;
    cflags.append("-Dbox2d_EXPORTS") catch unreachable;
    if (target.result.os.tag == .windows) {
        cflags.append("-D_CRT_SECURE_NO_WARNINGS") catch unreachable;
    }

    inline for (box2d_sources) |src| {
        lib.addCSourceFile(.{ .file = .{ .path = src }, .flags = cflags.items });
    }

    lib.addIncludePath(.{ .path = "../src/box2d/include" });
    lib.addIncludePath(.{ .path = "../src/box2d/src" });

    const file_path = b.option([]const u8, "file-path", "Path to the file") orelse "./out";
    b.lib_dir = std.mem.concat(std.heap.page_allocator, u8, &[_][]const u8{
        file_path,
        if (target.result.isWasm())
            "/libs/runtimes/browser-wasm/native"
        else if (target.result.isDarwin())
            "/libs/runtimes/osx-arm64/native"
        else if (lib.rootModuleTarget().os.tag == .linux)
            "/libs/runtimes/linux-x64/native"
        else if (lib.rootModuleTarget().os.tag == .windows)
            "/libs/runtimes/win-x64/native"
        else
            "/libs/runtimes/unknown/native",
    }) catch |err| {
        std.debug.print("Failed to concatenate strings: {}\n", .{err});
        return;
    };

    b.installArtifact(lib);
}
