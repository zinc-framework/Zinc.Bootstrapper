// zinc_window.c — desktop-companion window controls for Zinc (Windows).
//
// sokol_app.h has no concept of an undecorated window: it always creates a normal
// WS_CAPTION frame, and the only place it uses WS_POPUP is the internal fullscreen path.
// It does however hand out the native handle (sapp_win32_get_hwnd), which is all we need
// to restyle the window from outside. Doing it here rather than patching sokol keeps the
// zinc-framework/sokol fork free of divergence, and these knobs (always-on-top, drag by
// content, hide from the taskbar) are app policy that sokol has no business owning.
//
// Pair this with RunOptions.transparentWindow to get the actual "desktop companion" shape:
// a see-through, frameless, always-on-top window that draws a character on the desktop.
//
// The macOS counterpart lives in zinc_window.m. Everything here is a no-op returning 0 on
// platforms that aren't Windows, so the managed side can call unconditionally.
//
// KNOWN INTERACTION: sokol's _sapp_win32_set_fullscreen() rewrites GWL_STYLE wholesale, so
// toggling fullscreen after going borderless restores the frame. Re-apply borderless after
// any fullscreen transition.

#include <stdint.h>
#include "../../zinc_export.h"

#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

// Style bits that make up a normal decorated window frame.
#define ZINC_DECORATION_BITS (WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU)

// Remove (or restore) the OS title bar and frame while keeping the *client* area the same
// size, so the rendered surface doesn't jump when toggling. WS_POPUP replaces the frame
// styles; WS_SIZEBOX is deliberately not kept, a frameless window has no grab handles and
// resizing is the app's business (see zinc_window_begin_drag for the same reasoning).
ZINC_EXPORT int32_t zinc_window_set_borderless(void* handle, int32_t borderless) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }

    LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_STYLE);
    const LONG_PTR ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);

    // remember the client size so the drawable area survives the frame change
    RECT client;
    if (!GetClientRect(hwnd, &client)) { return 0; }
    const int client_w = client.right - client.left;
    const int client_h = client.bottom - client.top;

    if (borderless) {
        style &= ~(LONG_PTR)ZINC_DECORATION_BITS;
        style |= WS_POPUP;
    } else {
        style &= ~(LONG_PTR)WS_POPUP;
        style |= ZINC_DECORATION_BITS;
    }
    SetWindowLongPtrW(hwnd, GWL_STYLE, style);

    // grow/shrink the window rect so the client area keeps its size under the new frame
    RECT want = { 0, 0, client_w, client_h };
    AdjustWindowRectEx(&want, (DWORD)style, FALSE, (DWORD)ex_style);

    POINT origin = { 0, 0 };
    ClientToScreen(hwnd, &origin);

    SetWindowPos(hwnd, NULL,
        origin.x + want.left,
        origin.y + want.top,
        want.right - want.left,
        want.bottom - want.top,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    return 1;
}

// Keep the window above normal windows (what you want for a companion that sits on the
// desktop). Not sticky across every shell event, but good enough in practice.
ZINC_EXPORT int32_t zinc_window_set_topmost(void* handle, int32_t topmost) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }
    SetWindowPos(hwnd, topmost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return 1;
}

// Hide the window from the taskbar and Alt-Tab by making it a tool window. The ex-style
// only takes effect on a hidden window, so this cycles visibility if the window is up.
ZINC_EXPORT int32_t zinc_window_set_taskbar_visible(void* handle, int32_t visible) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }

    LONG_PTR ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (visible) {
        ex_style &= ~(LONG_PTR)WS_EX_TOOLWINDOW;
        ex_style |= WS_EX_APPWINDOW;
    } else {
        ex_style &= ~(LONG_PTR)WS_EX_APPWINDOW;
        ex_style |= WS_EX_TOOLWINDOW;
    }

    const BOOL was_visible = IsWindowVisible(hwnd);
    if (was_visible) { ShowWindow(hwnd, SW_HIDE); }
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style);
    if (was_visible) { ShowWindow(hwnd, SW_SHOWNA); }
    return 1;
}

// Start an OS-driven window drag from inside the client area. A frameless window has no
// title bar to grab, so the app decides what counts as a drag handle (e.g. "left mouse
// down anywhere that isn't a UI widget") and calls this. Telling the window manager to run
// its own move loop, rather than repositioning the window per mouse-move, is what makes the
// drag feel native: it snaps, it works across DPI boundaries, and it doesn't lag the cursor.
ZINC_EXPORT int32_t zinc_window_begin_drag(void* handle) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }
    // the button is currently down and captured by our client area; hand it to the frame
    ReleaseCapture();
    SendMessageW(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);

    // SendMessageW only returns once the modal move loop has ended -- and that loop consumed
    // the button release that ended the drag, so the app never sees WM_LBUTTONUP. Left alone,
    // its input layer believes the left button is held for the rest of the process's life:
    // every later hover reads as a mouse-down, which for the drag handler that called us
    // means the drag re-arms itself on every hover. Synthesize the release the loop ate.
    // sokol's wndproc turns WM_LBUTTONUP into SAPP_EVENTTYPE_MOUSE_UP through its ordinary
    // path without consulting physical button state, so the app just sees a normal release.
    POINT release_at;
    if (GetCursorPos(&release_at) && ScreenToClient(hwnd, &release_at)) {
        PostMessageW(hwnd, WM_LBUTTONUP, 0,
            MAKELPARAM((WORD)(short)release_at.x, (WORD)(short)release_at.y));
    }
    return 1;
}

// Click-through: let mouse input fall through to whatever is behind the window, including
// other applications, so a companion can be purely decorative.
//
// This needs WS_EX_LAYERED | WS_EX_TRANSPARENT *together*. Neither half works alone:
//   - WS_EX_TRANSPARENT by itself does nothing for input.
//   - WM_NCHITTEST/HTTRANSPARENT only forwards to windows in the SAME THREAD (see the
//     WM_NCHITTEST docs), so it cannot pass clicks to another process -- which is the
//     entire point here. An earlier version of this used it and appeared to do nothing.
//
// WS_EX_LAYERED normally wants SetLayeredWindowAttributes to define how the window is
// composited, so we set fully-opaque alpha; on a DirectComposition window the visual
// content still comes from the swapchain.
//
// VERIFIED on Windows 11: this coexists fine with the WS_EX_NOREDIRECTIONBITMAP that a
// composited window carries. The concern that WS_EX_LAYERED, being the legacy GDI
// compositing path, would blank a DirectComposition window turns out to be unfounded --
// click-through works in both opaque and transparent modes, and the window keeps
// rendering and compositing normally while it is on.
static BOOL _zinc_click_through = FALSE;

ZINC_EXPORT int32_t zinc_window_set_click_through(void* handle, int32_t enable) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }

    LONG_PTR ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (enable) {
        ex_style |= (WS_EX_LAYERED | WS_EX_TRANSPARENT);
    } else {
        ex_style &= ~(LONG_PTR)(WS_EX_LAYERED | WS_EX_TRANSPARENT);
    }
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style);

    if (enable) {
        // fully opaque: the layered flag is here for hit-testing, not to fade the window
        SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    }
    _zinc_click_through = enable ? TRUE : FALSE;
    return 1;
}

// Where the mouse is right now, asked of the OS rather than of the window: client-relative,
// top-left origin. Also reports the client size, because the two only mean anything together
// -- the caller needs the ratio to map this into whatever coordinate space its input events
// use, and getting both from one call keeps that conversion free of a second platform query.
// Units are physical pixels here; the macOS counterpart reports points. Either way the ratio
// against the client size is what the managed side actually consumes.
//
// This exists because a click-through window receives no mouse messages AT ALL, so the event
// stream freezes exactly when an app most needs to know whether the cursor has come back:
// the callback that would turn click-through off again can never fire off frozen coordinates.
// Being a global query it is also immune to another window covering ours -- which cuts both
// ways, since it cannot tell an occluded cursor from one over our own content.
ZINC_EXPORT int32_t zinc_window_get_cursor_pos(void* handle, int32_t* x, int32_t* y, int32_t* client_w, int32_t* client_h) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }

    POINT p;
    if (!GetCursorPos(&p)) { return 0; }
    if (!ScreenToClient(hwnd, &p)) { return 0; }

    RECT client;
    if (!GetClientRect(hwnd, &client)) { return 0; }

    if (x) { *x = (int32_t)p.x; }
    if (y) { *y = (int32_t)p.y; }
    if (client_w) { *client_w = (int32_t)(client.right - client.left); }
    if (client_h) { *client_h = (int32_t)(client.bottom - client.top); }
    return 1;
}

// Retained so the managed API keeps its shape; the WM_NCHITTEST subclass this used to undo
// is gone (it only ever worked within one thread). Nothing to restore.
ZINC_EXPORT int32_t zinc_window_restore_wndproc(void* handle) {
    (void)handle;
    return 1;
}

// Move the window's top-left to a screen position, in physical pixels.
ZINC_EXPORT int32_t zinc_window_set_position(void* handle, int32_t x, int32_t y) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }
    SetWindowPos(hwnd, NULL, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    return 1;
}

// Usable desktop area (excludes the taskbar) of the monitor the window is on, in physical
// pixels. Lets a companion park itself in a corner without guessing at screen metrics.
ZINC_EXPORT int32_t zinc_window_get_work_area(void* handle, int32_t* x, int32_t* y, int32_t* w, int32_t* h) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }
    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi;
    mi.cbSize = sizeof(mi);
    if (!GetMonitorInfoW(mon, &mi)) { return 0; }
    if (x) { *x = (int32_t)mi.rcWork.left; }
    if (y) { *y = (int32_t)mi.rcWork.top; }
    if (w) { *w = (int32_t)(mi.rcWork.right - mi.rcWork.left); }
    if (h) { *h = (int32_t)(mi.rcWork.bottom - mi.rcWork.top); }
    return 1;
}

#elif !defined(__APPLE__)

// Non-Windows, non-Apple (Linux/X11/Wayland): not implemented yet. Stubs return 0 so the
// managed side can call unconditionally and treat 0 as "unsupported on this platform".
ZINC_EXPORT int32_t zinc_window_set_borderless(void* handle, int32_t borderless) { (void)handle; (void)borderless; return 0; }
ZINC_EXPORT int32_t zinc_window_set_topmost(void* handle, int32_t topmost) { (void)handle; (void)topmost; return 0; }
ZINC_EXPORT int32_t zinc_window_set_taskbar_visible(void* handle, int32_t visible) { (void)handle; (void)visible; return 0; }
ZINC_EXPORT int32_t zinc_window_begin_drag(void* handle) { (void)handle; return 0; }
ZINC_EXPORT int32_t zinc_window_set_click_through(void* handle, int32_t enable) { (void)handle; (void)enable; return 0; }
ZINC_EXPORT int32_t zinc_window_restore_wndproc(void* handle) { (void)handle; return 0; }
ZINC_EXPORT int32_t zinc_window_set_position(void* handle, int32_t x, int32_t y) { (void)handle; (void)x; (void)y; return 0; }
ZINC_EXPORT int32_t zinc_window_get_work_area(void* handle, int32_t* x, int32_t* y, int32_t* w, int32_t* h) {
    (void)handle; (void)x; (void)y; (void)w; (void)h; return 0;
}
ZINC_EXPORT int32_t zinc_window_get_cursor_pos(void* handle, int32_t* x, int32_t* y, int32_t* client_w, int32_t* client_h) {
    (void)handle; (void)x; (void)y; (void)client_w; (void)client_h; return 0;
}

#endif // _WIN32 / !__APPLE__
