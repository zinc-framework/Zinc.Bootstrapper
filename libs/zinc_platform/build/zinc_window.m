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
#include <string.h>
#include "../../zinc_export.h"
// Declarations only (no SOKOL_IMPL): key state is reported by sokol keycode, see zinc_window.c.
#include "../../sokol/src/sokol/sokol_app.h"

#if defined(__APPLE__)

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

ZINC_EXPORT int32_t zinc_window_set_borderless(void* handle, int32_t borderless) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }

    if (borderless) {
        win.styleMask |= NSWindowStyleMaskFullSizeContentView;
        win.titlebarAppearsTransparent = YES;
        win.titleVisibility = NSWindowTitleHidden;
        win.movableByWindowBackground = YES;
    } else {
        win.styleMask &= ~NSWindowStyleMaskFullSizeContentView;
        win.titlebarAppearsTransparent = NO;
        win.titleVisibility = NSWindowTitleVisible;
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

// Where the mouse is right now, asked of AppKit rather than of the window: content-relative,
// top-left origin, plus the content size so the caller has the ratio it needs to map this
// into its own input coordinate space. Points here, not backing pixels -- the same units the
// content size is reported in, which is all the conversion depends on.
//
// +[NSEvent mouseLocation] is a global query, so unlike the event stream it keeps answering
// while ignoresMouseEvents is on. Without it a click-through window can never observe the
// cursor returning, and the callback that would clear ignoresMouseEvents never runs.
//
// STATUS: written against documented AppKit behaviour, NOT run on hardware -- same caveat as
// the rest of this file.
ZINC_EXPORT int32_t zinc_window_get_cursor_pos(void* handle, int32_t* x, int32_t* y, int32_t* client_w, int32_t* client_h) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    NSView* view = win.contentView;
    if (view == nil) { return 0; }

    // screen -> window -> view, via the rect form of the conversion (the point form is only
    // available from macOS 10.12, and this costs nothing extra)
    const NSPoint screen_pt = [NSEvent mouseLocation];
    const NSPoint win_pt = [win convertRectFromScreen:NSMakeRect(screen_pt.x, screen_pt.y, 0.0, 0.0)].origin;
    const NSPoint view_pt = [view convertPoint:win_pt fromView:nil];
    const NSRect bounds = view.bounds;

    // Cocoa's content origin is bottom-left; Zinc (and the Windows side) speak top-left.
    if (x) { *x = (int32_t)view_pt.x; }
    if (y) { *y = (int32_t)(bounds.size.height - view_pt.y); }
    if (client_w) { *client_w = (int32_t)bounds.size.width; }
    if (client_h) { *client_h = (int32_t)bounds.size.height; }
    return 1;
}

// No subclassing needed on macOS: ignoresMouseEvents above is the whole mechanism, so
// there is no winproc to restore. Present for API symmetry with the Windows side.
ZINC_EXPORT int32_t zinc_window_restore_wndproc(void* handle) {
    (void)handle;
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

// The window's outer frame on the desktop, in points with a top-left origin -- flipped through
// the primary screen the same way zinc_window_set_position does, so the two round-trip.
ZINC_EXPORT int32_t zinc_window_get_bounds(void* handle, int32_t* x, int32_t* y, int32_t* w, int32_t* h) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    NSArray<NSScreen*>* screens = [NSScreen screens];
    if (screens.count == 0) { return 0; }
    const CGFloat primary_h = screens[0].frame.size.height;
    const NSRect frame = win.frame;
    if (x) { *x = (int32_t)frame.origin.x; }
    if (y) { *y = (int32_t)(primary_h - frame.origin.y - frame.size.height); }
    if (w) { *w = (int32_t)frame.size.width; }
    if (h) { *h = (int32_t)frame.size.height; }
    return 1;
}

// The drawable area, in points. On macOS the content view is already the whole window for a
// borderless-styled companion, but it still differs from the frame whenever a title bar exists.
ZINC_EXPORT int32_t zinc_window_get_client_size(void* handle, int32_t* w, int32_t* h) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    const NSRect content = [win contentRectForFrameRect:win.frame];
    if (w) { *w = (int32_t)content.size.width; }
    if (h) { *h = (int32_t)content.size.height; }
    return 1;
}

// Resize so the content area is exactly w x h points, keeping the window's TOP-left corner put.
// -setContentSize: would anchor the bottom-left instead (Cocoa's origin), which reads as the
// window jumping upward; recomputing the frame keeps the behaviour matching the Windows side.
ZINC_EXPORT int32_t zinc_window_set_client_size(void* handle, int32_t w, int32_t h) {
    NSWindow* win = (__bridge NSWindow*)handle;
    if (win == nil) { return 0; }
    if (w <= 0 || h <= 0) { return 0; }

    const NSRect content = [win contentRectForFrameRect:win.frame];
    const CGFloat delta_h = (CGFloat)h - content.size.height;
    const NSRect want_content = NSMakeRect(content.origin.x, content.origin.y - delta_h, (CGFloat)w, (CGFloat)h);
    [win setFrame:[win frameRectForContentRect:want_content] display:YES];
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

// Which keys are physically down right now, one byte per sokol keycode -- see zinc_window.c
// for why. A window with ignoresMouseEvents can't be clicked to activate the app, so once the
// user touches anything else -keyDown: stops arriving; +[NSEvent addGlobalMonitorForEvents]
// would answer but needs Input Monitoring approval. CGEventSourceKeyState reads the session's
// combined key state directly and, as far as the documentation goes, is not gated behind that
// permission. The table is sokol's own macOS one (kVK_* virtual keycodes), which is exactly
// what CGEventSourceKeyState takes.
//
// STATUS: written against documented behaviour, NOT run on hardware -- same caveat as the
// rest of this file. If the OS does prompt for Input Monitoring, this is the call doing it.
static const struct { uint16_t kvk; uint16_t key; } _zinc_macos_keys[] = {
    { 0x1D, SAPP_KEYCODE_0 }, { 0x12, SAPP_KEYCODE_1 }, { 0x13, SAPP_KEYCODE_2 }, { 0x14, SAPP_KEYCODE_3 },
    { 0x15, SAPP_KEYCODE_4 }, { 0x17, SAPP_KEYCODE_5 }, { 0x16, SAPP_KEYCODE_6 }, { 0x1A, SAPP_KEYCODE_7 },
    { 0x1C, SAPP_KEYCODE_8 }, { 0x19, SAPP_KEYCODE_9 },
    { 0x00, SAPP_KEYCODE_A }, { 0x0B, SAPP_KEYCODE_B }, { 0x08, SAPP_KEYCODE_C }, { 0x02, SAPP_KEYCODE_D },
    { 0x0E, SAPP_KEYCODE_E }, { 0x03, SAPP_KEYCODE_F }, { 0x05, SAPP_KEYCODE_G }, { 0x04, SAPP_KEYCODE_H },
    { 0x22, SAPP_KEYCODE_I }, { 0x26, SAPP_KEYCODE_J }, { 0x28, SAPP_KEYCODE_K }, { 0x25, SAPP_KEYCODE_L },
    { 0x2E, SAPP_KEYCODE_M }, { 0x2D, SAPP_KEYCODE_N }, { 0x1F, SAPP_KEYCODE_O }, { 0x23, SAPP_KEYCODE_P },
    { 0x0C, SAPP_KEYCODE_Q }, { 0x0F, SAPP_KEYCODE_R }, { 0x01, SAPP_KEYCODE_S }, { 0x11, SAPP_KEYCODE_T },
    { 0x20, SAPP_KEYCODE_U }, { 0x09, SAPP_KEYCODE_V }, { 0x0D, SAPP_KEYCODE_W }, { 0x07, SAPP_KEYCODE_X },
    { 0x10, SAPP_KEYCODE_Y }, { 0x06, SAPP_KEYCODE_Z },
    { 0x27, SAPP_KEYCODE_APOSTROPHE }, { 0x2A, SAPP_KEYCODE_BACKSLASH }, { 0x2B, SAPP_KEYCODE_COMMA },
    { 0x18, SAPP_KEYCODE_EQUAL }, { 0x32, SAPP_KEYCODE_GRAVE_ACCENT }, { 0x21, SAPP_KEYCODE_LEFT_BRACKET },
    { 0x1B, SAPP_KEYCODE_MINUS }, { 0x2F, SAPP_KEYCODE_PERIOD }, { 0x1E, SAPP_KEYCODE_RIGHT_BRACKET },
    { 0x29, SAPP_KEYCODE_SEMICOLON }, { 0x2C, SAPP_KEYCODE_SLASH }, { 0x0A, SAPP_KEYCODE_WORLD_1 },
    { 0x33, SAPP_KEYCODE_BACKSPACE }, { 0x39, SAPP_KEYCODE_CAPS_LOCK }, { 0x75, SAPP_KEYCODE_DELETE },
    { 0x7D, SAPP_KEYCODE_DOWN }, { 0x77, SAPP_KEYCODE_END }, { 0x24, SAPP_KEYCODE_ENTER },
    { 0x35, SAPP_KEYCODE_ESCAPE },
    { 0x7A, SAPP_KEYCODE_F1 }, { 0x78, SAPP_KEYCODE_F2 }, { 0x63, SAPP_KEYCODE_F3 }, { 0x76, SAPP_KEYCODE_F4 },
    { 0x60, SAPP_KEYCODE_F5 }, { 0x61, SAPP_KEYCODE_F6 }, { 0x62, SAPP_KEYCODE_F7 }, { 0x64, SAPP_KEYCODE_F8 },
    { 0x65, SAPP_KEYCODE_F9 }, { 0x6D, SAPP_KEYCODE_F10 }, { 0x67, SAPP_KEYCODE_F11 }, { 0x6F, SAPP_KEYCODE_F12 },
    { 0x69, SAPP_KEYCODE_F13 }, { 0x6B, SAPP_KEYCODE_F14 }, { 0x71, SAPP_KEYCODE_F15 }, { 0x6A, SAPP_KEYCODE_F16 },
    { 0x40, SAPP_KEYCODE_F17 }, { 0x4F, SAPP_KEYCODE_F18 }, { 0x50, SAPP_KEYCODE_F19 }, { 0x5A, SAPP_KEYCODE_F20 },
    { 0x73, SAPP_KEYCODE_HOME }, { 0x72, SAPP_KEYCODE_INSERT }, { 0x7B, SAPP_KEYCODE_LEFT },
    { 0x3A, SAPP_KEYCODE_LEFT_ALT }, { 0x3B, SAPP_KEYCODE_LEFT_CONTROL }, { 0x38, SAPP_KEYCODE_LEFT_SHIFT },
    { 0x37, SAPP_KEYCODE_LEFT_SUPER }, { 0x6E, SAPP_KEYCODE_MENU }, { 0x47, SAPP_KEYCODE_NUM_LOCK },
    { 0x79, SAPP_KEYCODE_PAGE_DOWN }, { 0x74, SAPP_KEYCODE_PAGE_UP }, { 0x7C, SAPP_KEYCODE_RIGHT },
    { 0x3D, SAPP_KEYCODE_RIGHT_ALT }, { 0x3E, SAPP_KEYCODE_RIGHT_CONTROL }, { 0x3C, SAPP_KEYCODE_RIGHT_SHIFT },
    { 0x36, SAPP_KEYCODE_RIGHT_SUPER }, { 0x31, SAPP_KEYCODE_SPACE }, { 0x30, SAPP_KEYCODE_TAB },
    { 0x7E, SAPP_KEYCODE_UP },
    { 0x52, SAPP_KEYCODE_KP_0 }, { 0x53, SAPP_KEYCODE_KP_1 }, { 0x54, SAPP_KEYCODE_KP_2 }, { 0x55, SAPP_KEYCODE_KP_3 },
    { 0x56, SAPP_KEYCODE_KP_4 }, { 0x57, SAPP_KEYCODE_KP_5 }, { 0x58, SAPP_KEYCODE_KP_6 }, { 0x59, SAPP_KEYCODE_KP_7 },
    { 0x5B, SAPP_KEYCODE_KP_8 }, { 0x5C, SAPP_KEYCODE_KP_9 },
    { 0x45, SAPP_KEYCODE_KP_ADD }, { 0x41, SAPP_KEYCODE_KP_DECIMAL }, { 0x4B, SAPP_KEYCODE_KP_DIVIDE },
    { 0x4C, SAPP_KEYCODE_KP_ENTER }, { 0x51, SAPP_KEYCODE_KP_EQUAL }, { 0x43, SAPP_KEYCODE_KP_MULTIPLY },
    { 0x4E, SAPP_KEYCODE_KP_SUBTRACT },
};

ZINC_EXPORT int32_t zinc_window_get_keys_down(uint8_t* out_down, int32_t count) {
    if (!out_down || count <= 0) { return 0; }
    memset(out_down, 0, (size_t)count);
    for (size_t i = 0; i < sizeof(_zinc_macos_keys) / sizeof(_zinc_macos_keys[0]); i++) {
        const int key = _zinc_macos_keys[i].key;
        if (key < 0 || key >= count) { continue; }
        out_down[key] = CGEventSourceKeyState(kCGEventSourceStateCombinedSessionState, (CGKeyCode)_zinc_macos_keys[i].kvk) ? 1 : 0;
    }
    return 1;
}

#endif // __APPLE__
