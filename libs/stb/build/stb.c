#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_STDIO
#include "../src/stb/stb_image.h"

// stb_image_write: enables stbi_write_png(...) (file variant; STBI_WRITE_NO_STDIO is intentionally
// left undefined so the path-based writer is available). Used by Zinc's screenshot path.
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../src/stb/stb_image_write.h"
