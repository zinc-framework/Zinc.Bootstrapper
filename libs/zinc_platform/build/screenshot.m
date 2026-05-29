// screenshot.m — native GPU->CPU readback + PNG write for Zinc screenshots (macOS/Metal only).
//
// sokol_gfx exposes no portable pixel readback (floooh/sokol#282), so we do the Metal-specific
// dance here, modeled on the old sokol_gp `sokol_gfx_ext.h`: blit the source MTLTexture into a
// CPU-visible (shared) staging buffer, wait, then hand the bytes to stb_image_write.
//
// The caller passes a raw id<MTLTexture> (e.g. from sg_mtl_query_image_info(img).tex[slot]); this
// file deliberately knows nothing about sokol so the stb lib stays decoupled. Note a CAMetalDrawable's
// texture is framebufferOnly and CANNOT be read this way — capture an offscreen RenderTarget image.
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

// declarations only; the implementation is compiled in stb_image_write_impl.c
// (sibling TU in this same DLL — zinc_platform owns its own copy so it doesn't depend on stb.dll).
#include "../../stb/src/stb/stb_image_write.h"
// ZINC_EXPORT: see zinc_export.h. No-op on Mach-O (default visibility is already exported).
#include "../../zinc_export.h"

// Read `mtl_texture`'s pixels and write them to `path` as an 8-bit RGBA PNG.
//   mtl_queue: the MTLCommandQueue to submit the readback blit on. Pass sokol's queue
//     (sg_mtl_command_queue()) so the blit is FIFO-ordered *after* the frame's render work that
//     was just committed on that same queue. If NULL, a throwaway queue is created (only safe if
//     the source texture's writes have already completed).
//   flip_y != 0 flips vertically (use when the source was rendered with a flipped/sampling projection).
// Returns 1 on success, 0 on failure.
ZINC_EXPORT int zinc_write_texture_png(const void* mtl_texture, const void* mtl_queue, const char* path, int flip_y) {
    @autoreleasepool {
        id<MTLTexture> tex = (__bridge id<MTLTexture>)mtl_texture;
        if (tex == nil || path == NULL) return 0;

        NSUInteger w = tex.width, h = tex.height;
        if (w == 0 || h == 0) return 0;

        id<MTLDevice> dev = tex.device;
        if (dev == nil) return 0;

        // CPU-visible staging buffer. Align the row pitch to 256 bytes (a safe blit-to-buffer
        // destination alignment across Metal GPUs); we de-stride it when packing the output.
        NSUInteger tightBpr = w * 4;
        NSUInteger bpr = (tightBpr + 255) & ~(NSUInteger)255;
        id<MTLBuffer> buf = [dev newBufferWithLength:(bpr * h) options:MTLResourceStorageModeShared];
        if (buf == nil) return 0;

        id<MTLCommandQueue> queue = (mtl_queue != NULL)
            ? (__bridge id<MTLCommandQueue>)mtl_queue
            : [dev newCommandQueue];
        id<MTLCommandBuffer> cb = [queue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit copyFromTexture:tex
                  sourceSlice:0
                  sourceLevel:0
                 sourceOrigin:MTLOriginMake(0, 0, 0)
                   sourceSize:MTLSizeMake(w, h, 1)
                     toBuffer:buf
            destinationOffset:0
       destinationBytesPerRow:bpr
     destinationBytesPerImage:(bpr * h)];
        [blit endEncoding];
        [cb commit];
        [cb waitUntilCompleted];

        const uint8_t* src = (const uint8_t*)buf.contents;
        if (src == NULL) return 0;

        uint8_t* out = (uint8_t*)malloc((size_t)w * h * 4);
        if (out == NULL) return 0;

        // Swapchain/offscreen color is usually BGRA8 on Metal; normalize to RGBA for the PNG.
        bool bgra = (tex.pixelFormat == MTLPixelFormatBGRA8Unorm ||
                     tex.pixelFormat == MTLPixelFormatBGRA8Unorm_sRGB);

        for (NSUInteger y = 0; y < h; y++) {
            NSUInteger sy = flip_y ? (h - 1 - y) : y;
            const uint8_t* srow = src + sy * bpr;
            uint8_t* drow = out + y * tightBpr;
            for (NSUInteger x = 0; x < w; x++) {
                const uint8_t* s = srow + x * 4;
                uint8_t* d = drow + x * 4;
                if (bgra) { d[0] = s[2]; d[1] = s[1]; d[2] = s[0]; }
                else      { d[0] = s[0]; d[1] = s[1]; d[2] = s[2]; }
                d[3] = 255; // force opaque to match the composited on-screen result
            }
        }

        int ok = stbi_write_png(path, (int)w, (int)h, 4, out, (int)tightBpr);
        free(out);
        return ok;
    }
}
