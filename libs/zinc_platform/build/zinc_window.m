// zinc_window.m — desktop-companion window controls for Zinc (macOS).
//
// Apple-side counterpart to zinc_window.c; see that file for why these live in
// zinc_platform instead of in the sokol fork. The handle passed in is whatever
// sapp_macos_get_window() returned, i.e. an NSWindow*.
//
// STATUS: written against the documented AppKit behaviour but NOT yet run on hardware
// (same situation the D3D11/GL screenshot paths started in). Needs a Zinc.Bootstrapper
// build on a Mac plus a real run before it should be considered verified.
//
// WHY NOT NSWindowStyleMaskBorderless: a borderless NSWindow returns NO from
// -canBecomeKeyWindow unless the subclass overrides it, and sokol's _sapp_macos_window
// does not. Going properly borderless would therefore cost us all keyboard input. The
// approach used here instead is the standard AppKit one for chrome-less windows: keep the
// window titled (so it stays key-capable) but make the title bar transparent, hide its
// text and its traffic-light buttons, and let the content view run full height. Visually
// identical, no input trade-off.

#include <stdint.h>
#include "../../zinc_export.h"

#if defined(__APPLE__)

#import <Cocoa/Cocoa.h>

ZINC_EXPORT int32_t zinc_window_set_borderless(void* handle, int32_t borderless) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }

    if (borderless) {
        win.styleMask |= NSWindowStyleMaskFullSizeContentView;
        win.titlebarAppearsTransparent = YES;
        win.titleVisibility = NSWindowTitleVisibilityHidden;
        win.movableByWindowBackground = YES;
    } else {
        win.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        win.titlebarAppearsTransparent = NO;
        win.titleVisibility = NSWindowTitleVisibilityVisible;
        win.movableByWindowBackground = NO;
    }
    const BOOL hide = borderless ? YES : NO;
    [win standardWindowButton:NSWindowCloseButton].hidden = hide;
    [win standardWindowButton:NSWindowMiniaturizeButton].hidden = hide;
    [win standardWindowButton:NSWindowZoomButton].hidden = hide;
    return 1;
}

ZINC_EXPORT int32_t zinc_window_set_topmost(void* handle, int32_t topmost) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    win.level = topmost ? NSFloatingWindowLevel : NSNormalWindowLevel;
    return 1;
}

// macOS has no per-window taskbar entry; app presence in the Dock is an application-wide
// (LSUIElement / NSApplicationActivationPolicy) decision, not a window one. Reported as
// unsupported rather than silently doing something different from the Windows behaviour.
ZINC_EXPORT int32_t zinc_window_set_taskbar_visible(void* handle, int32_t visible) {
    (void)handle; (void)visible;
    return 0;
}

// movableByWindowBackground (set by set_borderless above) already lets AppKit drag the
// window from anywhere in the content, so there is no explicit drag to begin. Returning 1
// keeps the managed API's contract: "the platform is handling the drag".
ZINC_EXPORT int32_t zinc_window_begin_drag(void* handle) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    return win.movableByWindowBackground ? 1 : 0;
}

ZINC_EXPORT int32_t zinc_window_set_click_through(void* handle, int32_t enable) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    win.ignoresMouseEvents = enable ? YES : NO;
    return 1;
}

// Cocoa's origin is bottom-left of the primary screen; Zinc (and the Windows side) speak
// top-left, so flip through the primary screen's height.
ZINC_EXPORT int32_t zinc_window_set_position(void* handle, int32_t x, int32_t y) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count == 0) { return 0; }
    const CGFloat primary_h = screens[0].frame.size.height;
    const NSRect frame = win.frame;
    // set_position takes the top-left corner, setFrameOrigin takes the bottom-left
    [win setFrameOrigin:NSMakePoint((CGFloat)x, primary_h - (CGFloat)y - frame.size.height)];
    return 1;
}

ZINC_EXPORT int32_t zinc_window_get_work_area(void* handle, int32_t* x, int32_t* y, int32_t* w, int32_t* h) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    NSScreen* screen = win.screen ?: [NSScreen mainScreen];
    if (screen == nil) { return 0; }
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count == 0) { return 0; }
    const CGFloat primary_h = screens[0].frame.size.height;
    const NSRect vf = screen.visibleFrame;   // excludes the menu bar and the Dock
    if (x) { *x = (int32_t)vf.origin.x; }
    if (y) { *y = (int32_t)(primary_h - vf.origin.y - vf.size.height); }
    if (w) { *w = (int32_t)vf.size.width; }
    if (h) { *h = (int32_t)vf.size.height; }
    return 1;
}

#endif // __APPLE__
