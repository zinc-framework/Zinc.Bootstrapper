// screenshot_other.c — GPU->CPU readback + PNG write for the non-Metal backends (Windows D3D11,
// Linux desktop GL, web/emscripten GLES3). Companion to screenshot.m (Metal). sokol_gfx has no portable
// readback (floooh/sokol#282), so each backend does its own copy then hands bytes to stb_image_write.
//
// IMPORTANT: only the macOS/Metal path has been run. These paths are written from the documented APIs
// and compile-checked via zig cross-compile, but have NOT been executed on real hardware. In particular
// the GL vertical-flip convention and the exact swapchain pixel format are the most likely things to
// need a tweak on first run. The C# side (Screenshot.cs) degrades gracefully if a symbol is missing.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// declarations only; the implementation is compiled in stb.c (STB_IMAGE_WRITE_IMPLEMENTATION)
#include "../src/stb/stb_image_write.h"

// Pack a backend-read scanline buffer into tight top-left RGBA and write the PNG.
//   bgra      : swap R/B (Metal/D3D swapchains are usually BGRA)
//   bottom_up : src row 0 is the BOTTOM of the image (true for glReadPixels)
//   flip_y    : caller requested a vertical flip (source was rendered flipped)
__attribute__((unused))
static int zinc__pack_and_write(const uint8_t* src, int w, int h, int srcPitch,
                                int bgra, int bottom_up, int flip_y, const char* path) {
    if (!src || w <= 0 || h <= 0) return 0;
    uint8_t* out = (uint8_t*)malloc((size_t)w * h * 4);
    if (!out) return 0;
    int flip = (bottom_up ? 1 : 0) ^ (flip_y ? 1 : 0); // produce top-left origin
    for (int y = 0; y < h; y++) {
        int sy = flip ? (h - 1 - y) : y;
        const uint8_t* srow = src + (size_t)sy * srcPitch;
        uint8_t* drow = out + (size_t)y * w * 4;
        for (int x = 0; x < w; x++) {
            const uint8_t* s = srow + x * 4;
            uint8_t* d = drow + x * 4;
            if (bgra) { d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; }
            else      { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; }
            d[3] = 255; // force opaque to match the composited on-screen result
        }
    }
    int ok = stbi_write_png(path, w, h, 4, out, w * 4);
    free(out);
    return ok;
}

// ====================================================================================================
#if defined(_WIN32)
#define COBJMACROS
#include <d3d11.h>

// Copy the render-target texture into a STAGING texture, Map it, write the PNG. `tex2d` is sokol's
// ID3D11Texture2D (sg_d3d11_query_image_info(...).tex2d); device/context are sokol's D3D11 objects.
int zinc_write_d3d11_texture_png(const void* device_, const void* context_, const void* tex2d_,
                                 int w, int h, const char* path, int flip_y) {
    ID3D11Device* device = (ID3D11Device*)device_;
    ID3D11DeviceContext* ctx = (ID3D11DeviceContext*)context_;
    ID3D11Texture2D* src = (ID3D11Texture2D*)tex2d_;
    if (!device || !ctx || !src || !path) return 0;

    D3D11_TEXTURE2D_DESC desc;
    ID3D11Texture2D_GetDesc(src, &desc);

    D3D11_TEXTURE2D_DESC sd = desc;
    sd.Usage = D3D11_USAGE_STAGING;
    sd.BindFlags = 0;
    sd.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    sd.MiscFlags = 0;
    sd.SampleDesc.Count = 1; // staging textures can't be multisampled (read the resolve image)
    sd.SampleDesc.Quality = 0;

    ID3D11Texture2D* staging = NULL;
    if (FAILED(ID3D11Device_CreateTexture2D(device, &sd, NULL, &staging)) || !staging) return 0;

    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource*)staging, (ID3D11Resource*)src);

    D3D11_MAPPED_SUBRESOURCE map;
    if (FAILED(ID3D11DeviceContext_Map(ctx, (ID3D11Resource*)staging, 0, D3D11_MAP_READ, 0, &map))) {
        ID3D11Texture2D_Release(staging);
        return 0;
    }

    int bgra = (desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM ||
                desc.Format == DXGI_FORMAT_B8G8R8A8_UNORM_SRGB);
    int ok = zinc__pack_and_write((const uint8_t*)map.pData, w, h, (int)map.RowPitch,
                                  bgra, /*bottom_up*/0, flip_y, path); // D3D is top-left origin

    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource*)staging, 0);
    ID3D11Texture2D_Release(staging);
    return ok;
}

// ====================================================================================================
#elif defined(__EMSCRIPTEN__) || defined(__linux__)

#if defined(__EMSCRIPTEN__)
#include <GLES3/gl3.h>
#else
// Resolve the few GL entry points at runtime (already loaded in-process by sokol's GL backend) so we
// don't need GL dev headers at build time.
#include <dlfcn.h>
typedef unsigned int GLenum;
typedef unsigned int GLuint;
typedef int GLint;
typedef int GLsizei;
#define GL_FRAMEBUFFER        0x8D40
#define GL_COLOR_ATTACHMENT0  0x8CE0
#define GL_TEXTURE_2D         0x0DE1
#define GL_RGBA               0x1908
#define GL_UNSIGNED_BYTE      0x1401
typedef void (*PFN_glGenFramebuffers)(GLsizei, GLuint*);
typedef void (*PFN_glBindFramebuffer)(GLenum, GLuint);
typedef void (*PFN_glFramebufferTexture2D)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef void (*PFN_glReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*);
typedef void (*PFN_glDeleteFramebuffers)(GLsizei, const GLuint*);
#endif

// Attach the texture to a temporary FBO and glReadPixels it. `glTexture` is sokol's GL texture name
// (sg_gl_query_image_info(...).tex[active_slot]). The GL context must be current on this thread (it is —
// the engine calls this from the frame callback).
int zinc_write_gl_texture_png(unsigned int glTexture, int w, int h, const char* path, int flip_y) {
    if (!path || w <= 0 || h <= 0) return 0;

#if defined(__EMSCRIPTEN__)
    #define ZGL_GenFramebuffers      glGenFramebuffers
    #define ZGL_BindFramebuffer      glBindFramebuffer
    #define ZGL_FramebufferTexture2D glFramebufferTexture2D
    #define ZGL_ReadPixels           glReadPixels
    #define ZGL_DeleteFramebuffers   glDeleteFramebuffers
#else
    PFN_glGenFramebuffers      ZGL_GenFramebuffers      = (PFN_glGenFramebuffers)      dlsym(RTLD_DEFAULT, "glGenFramebuffers");
    PFN_glBindFramebuffer      ZGL_BindFramebuffer      = (PFN_glBindFramebuffer)      dlsym(RTLD_DEFAULT, "glBindFramebuffer");
    PFN_glFramebufferTexture2D ZGL_FramebufferTexture2D = (PFN_glFramebufferTexture2D) dlsym(RTLD_DEFAULT, "glFramebufferTexture2D");
    PFN_glReadPixels           ZGL_ReadPixels           = (PFN_glReadPixels)           dlsym(RTLD_DEFAULT, "glReadPixels");
    PFN_glDeleteFramebuffers   ZGL_DeleteFramebuffers   = (PFN_glDeleteFramebuffers)   dlsym(RTLD_DEFAULT, "glDeleteFramebuffers");
    if (!ZGL_GenFramebuffers || !ZGL_BindFramebuffer || !ZGL_FramebufferTexture2D ||
        !ZGL_ReadPixels || !ZGL_DeleteFramebuffers) return 0;
#endif

    GLuint fbo = 0;
    ZGL_GenFramebuffers(1, &fbo);
    ZGL_BindFramebuffer(GL_FRAMEBUFFER, fbo);
    ZGL_FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, glTexture, 0);

    uint8_t* buf = (uint8_t*)malloc((size_t)w * h * 4);
    if (!buf) { ZGL_BindFramebuffer(GL_FRAMEBUFFER, 0); ZGL_DeleteFramebuffers(1, &fbo); return 0; }
    ZGL_ReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, buf);

    ZGL_BindFramebuffer(GL_FRAMEBUFFER, 0);
    ZGL_DeleteFramebuffers(1, &fbo);

    // glReadPixels is bottom-up and returns RGBA already; pack to top-left.
    int ok = zinc__pack_and_write(buf, w, h, w * 4, /*bgra*/0, /*bottom_up*/1, flip_y, path);
    free(buf);
    return ok;
}

// ====================================================================================================
#else // unknown backend — graceful stubs so the symbols still resolve

int zinc_write_d3d11_texture_png(const void* d, const void* c, const void* t,
                                 int w, int h, const char* path, int flip_y) {
    (void)d;(void)c;(void)t;(void)w;(void)h;(void)path;(void)flip_y; return 0;
}
int zinc_write_gl_texture_png(unsigned int tex, int w, int h, const char* path, int flip_y) {
    (void)tex;(void)w;(void)h;(void)path;(void)flip_y; return 0;
}

#endif
