const std = @import("std");
const builtin = @import("builtin");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

pub const SokolBackend = enum {
    auto, // Windows: D3D11, macOS/iOS: Metal, otherwise: GL
    d3d11,
    metal,
    gl,
    gles3,
    wgpu,
};

pub fn resolveSokolBackend(backend: SokolBackend, target: std.Target) SokolBackend {
    if (backend != .auto) return backend;
    if (target.os.tag.isDarwin()) return .metal;
    if (target.os.tag == .windows) return .d3d11;
    if (target.cpu.arch.isWasm()) return .gles3;
    if (target.abi.isAndroid()) return .gles3;
    return .gl;
}

pub fn build(b: *Build) !void {
    const opt_use_gl = b.option(bool, "gl", "Force OpenGL (default: false)") orelse false;
    const opt_use_wgpu = b.option(bool, "wgpu", "Force WebGPU (default: false, web only)") orelse false;
    const opt_use_x11 = b.option(bool, "x11", "Force X11 (default: true, Linux only)") orelse true;
    const opt_use_wayland = b.option(bool, "wayland", "Force Wayland (default: false, Linux only)") orelse false;
    const opt_use_egl = b.option(bool, "egl", "Force EGL (default: false, Linux only)") orelse false;
    const sokol_backend: SokolBackend = if (opt_use_gl) .gl else if (opt_use_wgpu) .wgpu else .auto;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const file_path = b.option([]const u8, "file-path", "Output root for installed artifacts") orelse "./out";

    const target_result = target.result;
    const is_wasm = target_result.cpu.arch.isWasm();

    // wasm uses static linkage; everything else builds a shared library
    const linkage: std.builtin.LinkMode = if (is_wasm) .static else .dynamic;

    // module holds all compile-time settings; the library is built from it
    const mod = b.addModule("sokol_clib", .{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });

    const lib = b.addLibrary(.{
        .name = "sokol",
        .root_module = mod,
        .linkage = linkage,
    });

    try buildLibSokol(b, mod, lib, .{
        .target = target,
        .optimize = optimize,
        .backend = sokol_backend,
        .use_wayland = opt_use_wayland,
        .use_x11 = opt_use_x11,
        .use_egl = opt_use_egl,
    });

    // redirect install dir to out/libs/runtimes/<rid>/native
    const native_dir = std.mem.concat(b.allocator, u8, &.{
        file_path,
        if (is_wasm) "/libs/runtimes/browser-wasm/native"
        else if (target_result.os.tag.isDarwin()) "/libs/runtimes/osx-arm64/native"
        else if (target_result.os.tag == .linux) "/libs/runtimes/linux-x64/native"
        else if (target_result.os.tag == .windows) "/libs/runtimes/win-x64/native"
        else "/libs/runtimes/unknown/native",
    }) catch @panic("install path concat failed");
    b.lib_dir = native_dir;
    // On Windows zig installs the .dll into `bin/` and the import .lib into `lib/`. We want
    // everything in one `native/` directory so DllImport finds the dll alongside the lib at
    // runtime — point both at the same path.
    b.exe_dir = native_dir;

    b.installArtifact(lib);
}

pub const LibSokolOptions = struct {
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
    backend: SokolBackend = .auto,
    use_egl: bool = false,
    use_x11: bool = true,
    use_wayland: bool = false,
};

pub fn buildLibSokol(b: *Build, mod: *Build.Module, lib: *Build.Step.Compile, options: LibSokolOptions) !void {
    _ = lib;
    const tgt = options.target.result;
    const backend = resolveSokolBackend(options.backend, tgt);

    var cflags = std.ArrayList([]const u8).initCapacity(b.allocator, 16) catch @panic("OOM");
    var cppflags = std.ArrayList([]const u8).initCapacity(b.allocator, 16) catch @panic("OOM");

    cflags.append(b.allocator, "-DIMPL") catch @panic("OOM");
    cppflags.append(b.allocator, "-DIMPL") catch @panic("OOM");

    const backend_define: []const u8 = switch (backend) {
        .d3d11 => "-DSOKOL_D3D11",
        .metal => "-DSOKOL_METAL",
        .gl    => "-DSOKOL_GLCORE",
        .gles3 => "-DSOKOL_GLES3",
        .wgpu  => "-DSOKOL_WGPU",
        else => @panic("unknown sokol backend"),
    };
    cflags.append(b.allocator, backend_define) catch @panic("OOM");
    cppflags.append(b.allocator, backend_define) catch @panic("OOM");

    if (tgt.os.tag.isDarwin()) {
        cflags.append(b.allocator, "-ObjC") catch @panic("OOM");
        cppflags.append(b.allocator, "-ObjC++") catch @panic("OOM");
        mod.linkFramework("Foundation", .{});
        mod.linkFramework("AudioToolbox", .{});
        mod.linkFramework("QuartzCore", .{});
        if (backend == .metal) {
            mod.linkFramework("Metal", .{});
            mod.linkFramework("MetalKit", .{});
        }
        if (tgt.os.tag == .ios) {
            mod.linkFramework("UIKit", .{});
            mod.linkFramework("AVFoundation", .{});
            if (backend == .gl) {
                mod.linkFramework("OpenGLES", .{});
                mod.linkFramework("GLKit", .{});
            }
        } else if (tgt.os.tag == .macos) {
            mod.linkFramework("Cocoa", .{});
            mod.linkFramework("AppKit", .{});
            if (backend == .gl) {
                mod.linkFramework("OpenGL", .{});
            }
        }
    } else if (tgt.abi.isAndroid()) {
        if (backend != .gles3) @panic("Android target requires GLES3 backend");
        mod.linkSystemLibrary("GLESv3", .{});
        mod.linkSystemLibrary("EGL", .{});
        mod.linkSystemLibrary("android", .{});
        mod.linkSystemLibrary("log", .{});
    } else if (tgt.os.tag == .linux) {
        if (options.use_egl) {
            cflags.append(b.allocator, "-DSOKOL_FORCE_EGL") catch @panic("OOM");
            cppflags.append(b.allocator, "-DSOKOL_FORCE_EGL") catch @panic("OOM");
        }
        if (!options.use_x11) {
            cflags.append(b.allocator, "-DSOKOL_DISABLE_X11") catch @panic("OOM");
            cppflags.append(b.allocator, "-DSOKOL_DISABLE_X11") catch @panic("OOM");
        }
        if (!options.use_wayland) {
            cflags.append(b.allocator, "-DSOKOL_DISABLE_WAYLAND") catch @panic("OOM");
            cppflags.append(b.allocator, "-DSOKOL_DISABLE_WAYLAND") catch @panic("OOM");
        }
        const link_egl = options.use_egl or options.use_wayland;
        mod.linkSystemLibrary("asound", .{});
        mod.linkSystemLibrary("GL", .{});
        if (options.use_x11) {
            mod.linkSystemLibrary("X11", .{});
            mod.linkSystemLibrary("Xi", .{});
            mod.linkSystemLibrary("Xcursor", .{});
        }
        if (options.use_wayland) {
            mod.linkSystemLibrary("wayland-client", .{});
            mod.linkSystemLibrary("wayland-cursor", .{});
            mod.linkSystemLibrary("wayland-egl", .{});
            mod.linkSystemLibrary("xkbcommon", .{});
        }
        if (link_egl) mod.linkSystemLibrary("EGL", .{});
    } else if (tgt.os.tag == .windows) {
        mod.linkSystemLibrary("kernel32", .{});
        mod.linkSystemLibrary("user32", .{});
        mod.linkSystemLibrary("gdi32", .{});
        mod.linkSystemLibrary("ole32", .{});
        if (backend == .d3d11) {
            mod.linkSystemLibrary("d3d11", .{});
            mod.linkSystemLibrary("dxgi", .{});
        }
        // dcimgui leaves CIMGUI_API empty unless overridden, so on a Windows shared-library build
        // none of the ig*/Im* C-API symbols would land in the PE export table — the C# binding
        // looks them up by name and fails at runtime. (lld-mingw's implicit auto-export gets us
        // sg_*/sapp_*/sgp_* in sokol.c, but not these from a separately-compiled translation unit.)
        // Force CIMGUI_API to __declspec(dllexport) at compile time for both the .c (cflags) and
        // .cpp (cppflags) sources so every `CIMGUI_API` declaration becomes an export.
        cflags.append(b.allocator, "-DCIMGUI_API=__declspec(dllexport)") catch @panic("OOM");
        cppflags.append(b.allocator, "-DCIMGUI_API=__declspec(dllexport)") catch @panic("OOM");
    }

    // dcimgui sources (docking branch). v1.92+ split out cimgui_internal.cpp/h
    // for the symbols sokol_imgui's font-atlas path uses internally.
    const cpp_sources = [_][]const u8{
        "../../dcimgui/src/dcimgui/src-docking/cimgui.cpp",
        "../../dcimgui/src/dcimgui/src-docking/cimgui_internal.cpp",
        "../../dcimgui/src/dcimgui/src-docking/imgui.cpp",
        "../../dcimgui/src/dcimgui/src-docking/imgui_demo.cpp",
        "../../dcimgui/src/dcimgui/src-docking/imgui_draw.cpp",
        "../../dcimgui/src/dcimgui/src-docking/imgui_tables.cpp",
        "../../dcimgui/src/dcimgui/src-docking/imgui_widgets.cpp",
    };
    const c_sources = [_][]const u8{"sokol.c"};

    inline for (c_sources) |csrc| {
        mod.addCSourceFile(.{ .file = b.path(csrc), .flags = cflags.items });
    }
    inline for (cpp_sources) |csrc| {
        mod.addCSourceFile(.{ .file = b.path(csrc), .flags = cppflags.items });
    }
}
