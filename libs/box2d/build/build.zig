const std = @import("std");
const Build = std.Build;

// box2d v3 — pure C library with a stable C ABI. Compiles every .c in src/box2d/src.
// API export macro: BOX2D_EXPORT is wired via the box2d_EXPORTS define on MSVC,
// or __attribute__((visibility("default"))) on Clang/GCC.

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
    const file_path = b.option([]const u8, "file-path", "Output root for installed artifacts") orelse "./out";

    const mod = b.addModule("box2d_clib", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    var cflags = std.ArrayList([]const u8).initCapacity(b.allocator, 8) catch @panic("OOM");
    cflags.append(b.allocator, "-std=c17") catch @panic("OOM");
    cflags.append(b.allocator, "-fvisibility=hidden") catch @panic("OOM");
    cflags.append(b.allocator, "-Dbox2d_EXPORTS") catch @panic("OOM");
    if (target.result.os.tag == .windows) {
        cflags.append(b.allocator, "-D_CRT_SECURE_NO_WARNINGS") catch @panic("OOM");
    }

    inline for (box2d_sources) |csrc| {
        mod.addCSourceFile(.{ .file = b.path(csrc), .flags = cflags.items });
    }
    mod.addIncludePath(b.path("../src/box2d/include"));
    mod.addIncludePath(b.path("../src/box2d/src"));

    const lib = b.addLibrary(.{
        .name = "box2d",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const tgt = target.result;
    b.lib_dir = std.mem.concat(b.allocator, u8, &.{
        file_path,
        if (tgt.cpu.arch.isWasm()) "/libs/runtimes/browser-wasm/native"
        else if (tgt.os.tag.isDarwin()) "/libs/runtimes/osx-arm64/native"
        else if (tgt.os.tag == .linux) "/libs/runtimes/linux-x64/native"
        else if (tgt.os.tag == .windows) "/libs/runtimes/win-x64/native"
        else "/libs/runtimes/unknown/native",
    }) catch @panic("install path concat failed");

    b.installArtifact(lib);
}
