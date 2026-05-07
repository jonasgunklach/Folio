//  MuPDFCore.h
//  MuPDFKit
//
//  Pure-C public API exposed to Swift.
//  No MuPDF types leak across this boundary — only primitive C types.

#ifndef MuPDFCore_h
#define MuPDFCore_h

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// MARK: - Opaque handle
// ---------------------------------------------------------------------------

/// Represents an open, mutable PDF document backed by libmupdf.
typedef struct MuPDFHandle MuPDFHandle;

/// Length of the caller-supplied error message buffer.
#define MUPDF_ERR_LEN 512

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

/// Open a PDF from an absolute file-system path.
/// Returns a handle on success, NULL on failure (check error_buf).
MuPDFHandle *mupdf_open(const char *path,
                         char error_buf[MUPDF_ERR_LEN]);

/// Close the document and free all resources.
/// Safe to call with NULL.
void mupdf_close(MuPDFHandle *handle);

// ---------------------------------------------------------------------------
// MARK: - Document metadata
// ---------------------------------------------------------------------------

/// Returns the number of pages in the document, or -1 on error.
int mupdf_page_count(MuPDFHandle *handle,
                     char error_buf[MUPDF_ERR_LEN]);

// ---------------------------------------------------------------------------
// MARK: - Persistence
// ---------------------------------------------------------------------------

/// Save the document (including any edits) to a file path.
/// Uses incremental-update mode by default (smaller output, preserves
/// existing content).  Returns 0 on success, -1 on failure.
int mupdf_save(MuPDFHandle *handle,
               const char *path,
               char error_buf[MUPDF_ERR_LEN]);

// ---------------------------------------------------------------------------
// MARK: - Image insertion
// ---------------------------------------------------------------------------

/// Embed a JPEG or PNG image onto a page at the given PDF coordinates.
///
/// Coordinate system: PDF origin is the *bottom-left* corner of the page,
/// units are points (1/72 inch).  x, y mark the bottom-left of the image.
///
/// @param handle      Open document handle.
/// @param page_index  0-based page number.
/// @param img_data    Raw image bytes (JPEG or PNG).
/// @param img_len     Length of img_data in bytes.
/// @param x           Left edge in points (PDF coords, origin = bottom-left).
/// @param y           Bottom edge in points.
/// @param width       Width in points.
/// @param height      Height in points.
/// @param error_buf   Caller-supplied 512-byte buffer for error messages.
/// @return 0 on success, -1 on failure.
int mupdf_insert_image(MuPDFHandle *handle,
                       int page_index,
                       const uint8_t *img_data,
                       size_t img_len,
                       float x,
                       float y,
                       float width,
                       float height,
                       char error_buf[MUPDF_ERR_LEN]);

// ---------------------------------------------------------------------------
// MARK: - Text extraction
// ---------------------------------------------------------------------------

/// Extract all text lines from a page as a malloc'd JSON string.
///
/// JSON format (array of line objects):
/// [{"text":"Hello","x":10.0,"y":20.0,"w":200.0,"h":14.0,
///   "font":"Helvetica","fs":12.0,"r":0.0,"g":0.0,"b":0.0}, ...]
///
/// Coordinates are in PDF points, origin bottom-left.
/// "font" is the PostScript name of the dominant font on the line.
/// "fs" is the font size in points. "r","g","b" are text colour (0-1).
///
/// Caller MUST free the returned string with mupdf_free_string().
/// Returns NULL on failure (check error_buf).
char *mupdf_extract_text_json(MuPDFHandle *handle,
                               int page_index,
                               char error_buf[MUPDF_ERR_LEN]);

/// Free a string previously returned by mupdf_extract_text_json().
void mupdf_free_string(char *str);

// ---------------------------------------------------------------------------
// MARK: - Text replacement
// ---------------------------------------------------------------------------

/// Replace the text inside a bounding rectangle on a page with new_text.
///
/// The original content inside the rect is visually covered by a white-filled
/// rectangle, and the replacement text is drawn on top using Helvetica at the
/// requested font_size (PDF points).
///
/// Coordinate system: PDF origin = bottom-left, units = points.
///
/// @param handle       Open document handle.
/// @param page_index   0-based page number.
/// @param x            Left edge of the text bounding box (PDF coords).
/// @param y            Bottom edge (PDF coords).
/// @param width        Width of the bounding box.
/// @param height       Height of the bounding box.
/// @param new_text     UTF-8 replacement string (ASCII subset rendered correctly).
/// @param font_name    PostScript font name (e.g. "Helvetica", "Times-Roman").
///                     Pass NULL or "" to fall back to Helvetica.
/// @param font_size    Font size in PDF points.
/// @param r,g,b        Text colour components in [0,1] range.
/// @param error_buf    Caller-supplied 512-byte buffer for error messages.
/// @return 0 on success, -1 on failure.
int mupdf_replace_text(MuPDFHandle *handle,
                       int page_index,
                       float x, float y,
                       float width, float height,
                       const char *new_text,
                       const char *font_name,
                       float font_size,
                       float r, float g, float b,
                       char error_buf[MUPDF_ERR_LEN]);

#ifdef __cplusplus
}
#endif

#endif /* MuPDFCore_h */
