# Zinc.Bootstrapper

This repo builds the dependent libraries and bindings for Zinc

It uses Zig to compile the libraires, and ClangSharpPinvokeGenerator for the bindings.

The only thing you need to install is ClangSharpPInvokeGenerator (and this is only if you want bindings):

`dotnet tool install --global ClangSharpPInvokeGenerator --version 18.1.0`

## Running

This uses [Bullseye/SimpleExec for everything](https://mysticmind.dev/dotnet-build-tool-using-bullseye-and-simpleexec). Targets are split up such that they cascade from least to most specific.

Generally there are four options:
1. Everything (./build with no args or default)
2. Everything for a lib (./build sokol|cute|stb)
2. Everything for bindgen (./build [sokol|cute|stb]:bindgen)
2. Specific bindgen (./build [sokol|cute|stb]:bindgen:[filename])

See all the options by running `./build --help`


## Bindings

Bindings require that your running platform have Visual Studio (or Build Tools for Visual Studio 2022 - select "Desktop Development with C++") installed or Xcode

https://visualstudio.microsoft.com/downloads/#remote-tools-for-visual-studio-2022 (bottom sctoll for "Visual C++ Redistributable for Visual Studio 2022)

NOTE: IMGUI bindings are a little wonky and need to be manually updated
See the "Fix Imgui" commit in the bindings repo to see what needs to change
* _iobuf needs to map to void*
* __arglist needs to map to params string[] args
* the bitfield logic needs to map to proper ints 

## DLL vs. Static
Switch between dynamic and static builds in `libs/sokol/build/sokol.c` by toggling
the `DLL_BUILD` / `STATIC_BUILD` defines at the top of the file. `DLL_BUILD`
enables `SOKOL_DLL`; `STATIC_BUILD` injects the `__stack_chk_guard` shim until
that workaround is no longer needed.

## Sokol
`libs/sokol/src/sokol` points at the [zinc-framework/sokol](https://github.com/zinc-framework/sokol)
fork, branch `zinc`. As of the Aug-2026 bump that branch carries **no patches** — it is a
straight mirror of upstream `floooh/sokol` master. The fork stays in place so we have
somewhere to land a patch if we need one again, not because we currently have one.

The patch it used to carry forced `CAMetalLayer.displaySyncEnabled = NO` to work around
macOS Tahoe input lag (floooh/sokol#1344). It was dropped once upstream shipped the same
knob as a supported option, `sapp_desc.metal.disable_display_sync`, in the Jul-2026
swapchain update — consumers that want the old behaviour set that field to `true`.

To move the fork to a newer upstream, from inside the submodule:

```
git fetch origin                    # origin = floooh/sokol (upstream)
git checkout zinc
git reset --hard origin/master      # or rebase, if the branch has patches again
git push --force-with-lease zinc zinc   # zinc = zinc-framework/sokol (the fork)
```

Note the local remote layout: `origin` is upstream and `zinc` is the fork, matching how
`sokol_gp` is wired. A fresh clone gets `origin` = the fork instead, per `.gitmodules`.

`libs/sokol/src/sokol_gp` points at [zinc-framework/sokol_gp](https://github.com/zinc-framework/sokol_gp)
(`sokol-view-objects`), which is upstream edubart/sokol_gp plus one commit porting it to
sokol's view-object API. That one *is* a real patch — re-port it if upstream sokol_gp moves.

## ImGui
We consume [floooh/dcimgui](https://github.com/floooh/dcimgui) (docking variant)
directly — this provides Dear ImGui + the dear_bindings-generated C API with the
`ig` prefix that sokol_imgui.h expects by default. The previous hand-rolled
cimgui submodule and `imgui.cpp` stub have been removed.