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