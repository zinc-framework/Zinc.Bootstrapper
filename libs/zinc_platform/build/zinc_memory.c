// zinc_memory.c — portable virtual-memory primitives for Zinc.
//
// Thin cross-platform wrapper over the OS virtual-memory API: reserve an address range,
// commit/decommit physical pages on demand, release, and guard-protect. This is the foundation
// for arena / bump allocators (per-frame scratch, transient load buffers) where you want a large
// reserved range but only pay for the pages you actually touch.
//
//   Windows : VirtualAlloc (MEM_RESERVE / MEM_COMMIT / MEM_DECOMMIT / MEM_RELEASE) + VirtualProtect
//   POSIX   : mmap + madvise(MADV_DONTNEED) + mprotect            (Linux, macOS)
//   Console : add an #if branch here calling the platform SDK's VM API
//
// requires_commit() reports whether reserve() hands back uncommitted pages (Windows: yes; POSIX:
// no — pages back themselves on first touch) so callers can skip a no-op commit step.
//
// These live in C rather than managed P/Invoke so console ports — where the VM API is only exposed
// through the platform's native SDK, not kernel32/libc — are one more #if branch instead of a
// managed/native rewrite.

#include <stddef.h>
#include <stdint.h>
#include "../../zinc_export.h"

#if defined(_WIN32)
// -----------------------------------------------------------------------------------------------
// Windows: VirtualAlloc / VirtualFree / VirtualProtect from kernel32.
// -----------------------------------------------------------------------------------------------
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

ZINC_EXPORT int32_t zinc_mem_requires_commit(void) { return 1; }

ZINC_EXPORT int64_t zinc_mem_page_size(void) {
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return (int64_t)si.dwPageSize;
}

ZINC_EXPORT void* zinc_mem_reserve(int64_t size) {
    // MEM_RESERVE only — caller must follow up with zinc_mem_commit before touching the pages.
    return VirtualAlloc(NULL, (SIZE_T)size, MEM_RESERVE, PAGE_READWRITE);
}

ZINC_EXPORT void zinc_mem_commit(void* ptr, int64_t size) {
    // VirtualAlloc on already-reserved pages with MEM_COMMIT transitions them to committed.
    (void)VirtualAlloc(ptr, (SIZE_T)size, MEM_COMMIT, PAGE_READWRITE);
}

ZINC_EXPORT void zinc_mem_decommit(void* ptr, int64_t size) {
    // MEM_DECOMMIT releases the physical pages back to the OS but keeps the address range reserved.
    (void)VirtualFree(ptr, (SIZE_T)size, MEM_DECOMMIT);
}

ZINC_EXPORT void zinc_mem_release(void* ptr, int64_t size) {
    // size must be 0 for MEM_RELEASE per Win32 spec; the OS knows the reserved region's extent.
    (void)size;
    (void)VirtualFree(ptr, 0, MEM_RELEASE);
}

ZINC_EXPORT void zinc_mem_protect(void* ptr, int64_t size) {
    // Guard page: PAGE_GUARD | PAGE_READWRITE traps the first access. Useful for poison/overrun
    // detection in debug allocator builds.
    DWORD old_protect;
    (void)VirtualProtect(ptr, (SIZE_T)size, PAGE_GUARD | PAGE_READWRITE, &old_protect);
}

#else
// -----------------------------------------------------------------------------------------------
// POSIX (Linux, macOS, anything else with mmap): mmap / munmap / mprotect / madvise.
// -----------------------------------------------------------------------------------------------
#include <sys/mman.h>
#include <unistd.h>

// Commit-on-first-touch is the POSIX norm; we don't proactively commit. Callers branch on
// requires_commit() to skip the no-op commit call entirely.
ZINC_EXPORT int32_t zinc_mem_requires_commit(void) { return 0; }

ZINC_EXPORT int64_t zinc_mem_page_size(void) { return (int64_t)sysconf(_SC_PAGESIZE); }

ZINC_EXPORT void* zinc_mem_reserve(int64_t size) {
    // PROT_READ|WRITE with MAP_PRIVATE|MAP_ANONYMOUS gives a freshly-zeroed COW region. Pages
    // aren't physically backed until first write, which is the closest POSIX analog to Windows'
    // "reserve without commit." Returns NULL (not MAP_FAILED) on failure for a simple null check.
    void* p = mmap(NULL, (size_t)size,
                   PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS,
                   -1, 0);
    return (p == MAP_FAILED) ? NULL : p;
}

ZINC_EXPORT void zinc_mem_commit(void* ptr, int64_t size) {
    // No-op: pages commit on first touch.
    (void)ptr; (void)size;
}

ZINC_EXPORT void zinc_mem_decommit(void* ptr, int64_t size) {
    if (ptr == NULL) return;
    // MADV_DONTNEED tells the kernel it may reclaim these pages; their contents reset to
    // anonymous-zero on next touch. MADV_FREE is faster on newer kernels but not portable across
    // glibc/musl/darwin versions, so we use the widely-supported MADV_DONTNEED.
    (void)madvise(ptr, (size_t)size, MADV_DONTNEED);
}

ZINC_EXPORT void zinc_mem_release(void* ptr, int64_t size) {
    if (ptr == NULL) return;
    (void)munmap(ptr, (size_t)size);
}

ZINC_EXPORT void zinc_mem_protect(void* ptr, int64_t size) {
    // PROT_NONE traps on any access — equivalent to Windows' guard page.
    (void)mprotect(ptr, (size_t)size, PROT_NONE);
}

#endif
