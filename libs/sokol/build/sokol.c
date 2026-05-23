#define SOKOL_IMPL
#define SOKOL_NO_ENTRY
#define SOKOL_TRACE_HOOKS
#define FONTSTASH_IMPLEMENTATION

// comment these out to configure build option for sokol
#define DLL_BUILD
// #define STATIC_BUILD

#if defined(DLL_BUILD)
    #define SOKOL_DLL
#endif

#if defined(STATIC_BUILD)
    int __stack_chk_guard = 42;
#endif

/* sokol 3D-API defines are provided by build options */
#include "../src/sokol/sokol_app.h"
#include "../src/sokol/sokol_args.h"
#include "../src/sokol/sokol_audio.h"
#include "../src/sokol/sokol_fetch.h"
#include "../src/sokol/sokol_gfx.h"

// Zinc: raise sokol_gp's per-draw caps above the upstream defaults (8 uniform floats / 4 textures)
// so custom shaders can carry larger uniform blocks (up to 256 bytes combined vs+fs) and more
// texture channels. Mirrored C#-side by MaterialComponent.MaxUniformBytes / TextureSlots, which
// bounds-check against these exact values — keep the two in sync if you change them here.
#define SGP_UNIFORM_CONTENT_SLOTS 64
#define SGP_TEXTURE_SLOTS 8
#include "../src/sokol_gp/sokol_gp.h"

#include "../src/sokol/sokol_glue.h"
#include "../src/sokol/sokol_time.h"
#include "../src/sokol/sokol_log.h"

#include "../src/sokol/util/sokol_color.h"
#include "../src/sokol/util/sokol_debugtext.h"
#include "../src/sokol/util/sokol_gl.h"
#include "../src/fontstash.h"
#include "../src/sokol/util/sokol_fontstash.h"

/* dcimgui (dear_bindings) — must be included before sokol_imgui.h / sokol_gfx_imgui.h
   so ImTextureID / ImDrawCmd / ImTextureData are defined. */
#include "../../dcimgui/src/dcimgui/src-docking/cimgui.h"
#include "../src/sokol/util/sokol_imgui.h"
#include "../src/sokol/util/sokol_gfx_imgui.h"
#include "../src/sokol/util/sokol_app_imgui.h"
#include "../src/sokol/util/sokol_letterbox.h"
