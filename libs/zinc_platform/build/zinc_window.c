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
    return 1;
}

// Click-through: let mouse input fall through to whatever is behind the window, so a
// companion can be purely decorative.
//
// The usual Win32 recipe is WS_EX_LAYERED | WS_EX_TRANSPARENT, but that is unavailable
// here: WS_EX_LAYERED is the legacy GDI compositing path and is incompatible with the
// WS_EX_NOREDIRECTIONBITMAP that a DirectComposition (transparent) window requires -- a
// window with no redirection bitmap has nothing for the layered path to composite. And
// WS_EX_TRANSPARENT on its own does nothing for input.
//
// So instead we answer WM_NCHITTEST with HTTRANSPARENT, which tells the system to keep
// hit-testing into the windows underneath (across processes). That's an ordinary window
// message, unaffected by how the window is composited, so it works in both modes. sokol
// owns the winproc, so the window is subclassed and only this one message is intercepted;
// everything else is forwarded untouched.
//
// sokol_app is single-window, so one static original-winproc slot is sufficient.
static WNDPROC _zinc_orig_wndproc = NULL;
static BOOL _zinc_click_through = FALSE;

static LRESULT CALLBACK _zinc_wndproc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (_zinc_click_through && (msg == WM_NCHITTEST)) {
        // the whole window, client area included, is transparent to the mouse
        return HTTRANSPARENT;
    }
    return CallWindowProcW(_zinc_orig_wndproc, hwnd, msg, wp, lp);
}

ZINC_EXPORT int32_t zinc_window_set_click_through(void* handle, int32_t enable) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd)) { return 0; }

    if (enable && (NULL == _zinc_orig_wndproc)) {
        _zinc_orig_wndproc = (WNDPROC)(LONG_PTR)SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)_zinc_wndproc);
        if (NULL == _zinc_orig_wndproc) { return 0; }
    }
    _zinc_click_through = enable ? TRUE : FALSE;

    // Also flip WS_EX_TRANSPARENT. It isn't sufficient on its own, but it is the correct
    // hint for a non-composited window and costs nothing here.
    LONG_PTR ex_style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (enable) {
        ex_style |= WS_EX_TRANSPARENT;
    } else {
        ex_style &= ~(LONG_PTR)WS_EX_TRANSPARENT;
    }
    SetWindowLongPtrW(hwnd, GWL_EXSTYLE, ex_style);
    return 1;
}

// Undo the subclass. Worth calling before the process tears down: if zinc_platform were
// ever unloaded while the window still pointed at _zinc_wndproc, the next message would
// jump into freed code.
ZINC_EXPORT int32_t zinc_window_restore_wndproc(void* handle) {
    HWND hwnd = (HWND)handle;
    if (!IsWindow(hwnd) || (NULL == _zinc_orig_wndproc)) { return 0; }
    SetWindowLongPtrW(hwnd, GWLP_WNDPROC, (LONG_PTR)_zinc_orig_wndproc);
    _zinc_orig_wndproc = NULL;
    _zinc_click_through = FALSE;
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

#endif // _WIN32 / !__APPLE__
