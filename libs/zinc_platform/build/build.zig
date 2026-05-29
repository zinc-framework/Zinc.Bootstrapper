const std = @import("std");
const Build = std.Build;

// zinc_platform — Zinc-owned platform abstractions (memory, screenshot readback).
// Mirrors libs/stb/build/build.zig. Outputs zinc_platform.{dll,dylib,so} into
// out/libs/runtimes/<rid>/native/ alongside sokol/stb/box2d.
//
// What lives here:
//   zinc_memory.c          — VirtualAlloc/mmap wrappers (zinc_mem_*). Cross-platform.
//   screenshot.m           — Metal GPU readback + PNG write. Apple only.
//   screenshot_other.c     — D3D11 / GL GPU readback + PNG write. Windows/Linux.
// Both screenshot TUs include their own STB_IMAGE_WRITE implementation (via a
// dedicated stb_image_write_impl.c) so zinc_platform doesn't depend on the stb
// DLL at link time. Doubles up the stb_image_write code (a few KB), but keeps
// the DLLs decoupled.

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const file_path = b.option([]const u8, "file-path", "Output root for installed artifacts") orelse "./out";

    const mod = b.addModule("zinc_platform_clib", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Tell zinc_export.h we're compiling the DLL side (so ZINC_EXPORT becomes dllexport on
    // Windows / default visibility on Mach-O/ELF). Same convention every Zinc native lib uses.
    const c_flags = [_][]const u8{"-DZINC_BUILDING_DLL"};
    const objc_flags = [_][]const u8{ "-DZINC_BUILDING_DLL", "-fobjc-arc" };

    // Always include cross-platform sources.
    mod.addCSourceFile(.{ .file = b.path("zinc_memory.c"), .flags = &c_flags });
    // Single TU that compiles STB_IMAGE_WRITE_IMPLEMENTATION; screenshot.* link against it.
    mod.addCSourceFile(.{ .file = b.path("stb_image_write_impl.c"), .flags = &c_flags });

    // Native GPU->CPU readback used by Zinc's screenshot path (sokol has no portable pixel readback).
    // Backend-specific: Metal (.m, ObjC+ARC) on Apple, D3D11/GL/GLES (.c) elsewhere.
    const os = target.result.os.tag;
    if (os.isDarwin()) {
        mod.addCSourceFile(.{ .file = b.path("screenshot.m"), .flags = &objc_flags });
        mod.linkFramework("Metal", .{});
        mod.linkFramework("Foundation", .{});
        mod.linkFramework("QuartzCore", .{});
    } else {
        mod.addCSourceFile(.{ .file = b.path("screenshot_other.c"), .flags = &c_flags });
        if (os == .windows) {
            mod.linkSystemLibrary("d3d11", .{});
        } else if (os == .linux) {
            mod.linkSystemLibrary("dl", .{}); // dlsym for GL entry points
        }
    }

    const lib = b.addLibrary(.{
        .name = "zinc_platform",
        .root_module = mod,
        .linkage = .dynamic,
    });

    const tgt = target.result;
    const native_dir = std.mem.concat(b.allocator, u8, &.{
        file_path,
        if (tgt.cpu.arch.isWasm()) "/libs/runtimes/browser-wasm/native"
        else if (tgt.os.tag.isDarwin()) "/libs/runtimes/osx-arm64/native"
        else if (tgt.os.tag == .linux) "/libs/runtimes/linux-x64/native"
        else if (tgt.os.tag == .windows) "/libs/runtimes/win-x64/native"
        else "/libs/runtimes/unknown/native",
    }) catch @panic("install path concat failed");
    b.lib_dir = native_dir;
    // Windows separates the .dll (bin) from its import .lib (lib). Force both into the same
    // single "native" directory so consumers don't have to know about that split — the .NET
    // DllImport runtime only looks alongside the import lib, and Zinc bundles everything from
    // libs/runtimes/<rid>/native/ into the published app.
    b.exe_dir = native_dir;

    b.installArtifact(lib);
}
