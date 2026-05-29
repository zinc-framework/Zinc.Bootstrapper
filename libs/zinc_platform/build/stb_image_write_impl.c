// stb_image_write implementation TU for zinc_platform.
//
// screenshot.m and screenshot_other.c call stbi_write_png. We can't link against the stb DLL
// (separate native lib, separate export table) so we compile a private copy of the
// implementation here. The cost is a few KB of duplicated PNG-encoder code; the gain is that
// zinc_platform has no link-time dependency on the stb DLL.
//
// STBI_WRITE_NO_STDIO is intentionally NOT defined — screenshot.* use the path-based
// stbi_write_png(...) entry point that writes to a FILE*.
//
// Route stbi_write_png and friends through ZINC_EXPORT so we end up with a clean export table
// matching stb's own pattern (see libs/stb/build/stb.c for the why behind the STBIWDEF override:
// lld-mingw's implicit auto-export pass switches off per-object once anything is dllexport'd,
// so we have to be explicit).
#include "../../zinc_export.h"
#define STBIWDEF ZINC_EXPORT

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../../stb/src/stb/stb_image_write.h"
