#define SOKOL_IMPL
#define SOKOL_NO_ENTRY
#define SOKOL_TRACE_HOOKS
#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS
#define FONTSTASH_IMPLEMENTATION

// comment these out to configure build option for sokol
#define DLL_BUILD
// #define STATIC_BUILD

#if defined(DLL_BUILD)
    #define SOKOL_DLL
#endif

#if defined(STATIC_BUILD)
    int __stack_chk_guard = 42;
    #define IMGUI_STATIC
#endif

// #define STB_TRUETYPE_IMPLEMENTATION
// #define STATIC
// #define SOKOL_DEBUG

// #define USE_SOKOL_APP dont need this anymore says floooh - if it breaks uncomment i guess
//
// #if defined(_WIN32)
// #define SOKOL_LOG(s) OutputDebugStringA(s)
// #endif
/* sokol 3D-API defines are provided by build options */
#include "../src/sokol/sokol_app.h"
#include "../src/sokol/sokol_args.h"
#include "../src/sokol/sokol_audio.h"
#include "../src/sokol/sokol_fetch.h"
#include "../src/sokol/sokol_gfx.h"

#include "../src/sokol_gp/sokol_gp.h"

#include "../src/sokol/sokol_glue.h"
#include "../src/sokol/sokol_time.h"
#include "../src/sokol/sokol_log.h"

#include "../src/sokol/util/sokol_color.h"
#include "../src/sokol/util/sokol_debugtext.h"
#include "../src/sokol/util/sokol_gl.h"
#include "../src/fontstash.h"
#include "../src/sokol/util/sokol_fontstash.h"
#include "../../cimgui/src/cimgui/cimgui.h"
#include "../src/sokol/util/sokol_imgui.h"
#include "../src/sokol/util/sokol_gfx_imgui.h"
