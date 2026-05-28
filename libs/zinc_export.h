// zinc_export.h — single source of truth for "this function is exported from the DLL".
//
// Mirrors sokol's SOKOL_DLL / SOKOL_<MODULE>_API_DECL convention so every native lib we ship
// uses one consistent dllexport story instead of each .c file rolling its own dllexport block:
//
//   - Build side (compiling the .dll/.dylib/.so): build.zig passes -DZINC_BUILDING_DLL, which
//     makes ZINC_EXPORT expand to __declspec(dllexport) on Windows and
//     __attribute__((visibility("default"))) on Mach-O/ELF.
//   - Consumer side: we don't currently consume zinc_* symbols from another native lib (it's
//     all .NET DllImport from the managed side, which only cares about the DLL's export table),
//     so ZINC_EXPORT on the import side is plain `extern`. If we ever do, set
//     ZINC_DLL on the consumer to get dllimport on Windows.
//
// Why this matters on Windows specifically: lld-mingw's implicit "export every non-static
// extern" pass switches off per-object as soon as ANY symbol in that translation unit is marked
// dllexport — so a single tagged function in screenshot_other.c silently dropped every other
// extern in the same TU from the PE export table. On Mach-O / ELF, default visibility is already
// "exported from the shared library", so this whole macro collapses to a no-op.

#ifndef ZINC_EXPORT_H
#define ZINC_EXPORT_H

#if defined(_WIN32)
  #if defined(ZINC_BUILDING_DLL)
    #define ZINC_EXPORT __declspec(dllexport)
  #elif defined(ZINC_DLL)
    #define ZINC_EXPORT __declspec(dllimport)
  #else
    #define ZINC_EXPORT extern
  #endif
#elif defined(__GNUC__) || defined(__clang__)
  #if defined(ZINC_BUILDING_DLL)
    #define ZINC_EXPORT __attribute__((visibility("default")))
  #else
    #define ZINC_EXPORT extern
  #endif
#else
  #define ZINC_EXPORT extern
#endif

#endif // ZINC_EXPORT_H
