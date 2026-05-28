// Route stb's own per-function decl macros (STBIDEF, STBIWDEF — see "#ifndef STBIDEF" near the
// top of stb_image.h) through our shared ZINC_EXPORT so every native lib in this repo uses one
// consistent dllexport story. Has to be set *before* the first include because both headers
// freeze their macro on first definition.
//
// On Mach-O/ELF this is a no-op (ZINC_EXPORT collapses to `extern`, the default visibility
// makes the symbols exported from the dylib/so). On Windows it's load-bearing: once anything in
// this DLL is marked dllexport (the zinc_* entry points in screenshot_other.c), lld-mingw's
// implicit auto-export pass switches off per-object and the stbi_* / stbiw_* symbols would
// silently disappear from the PE export table.
#include "../../zinc_export.h"
#define STBIDEF  ZINC_EXPORT
#define STBIWDEF ZINC_EXPORT

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "../src/stb/stb_image.h"

// stb_image_write: enables stbi_write_png(...) (file variant; STBI_WRITE_NO_STDIO is intentionally
// left undefined so the path-based writer is available). Used by Zinc's screenshot path.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../src/stb/stb_image_write.h"
