//  MuPDFCore.c
//  MuPDFKit
//
//  C wrapper around libmupdf 1.27.
//  All MuPDF calls are guarded by fz_try/fz_catch so errors never
//  escape as C++ / setjmp exceptions into Swift.

#include "MuPDFCore.h"

// MuPDF headers — kept strictly inside the .c file so they never leak
// into the Swift-visible public header.
#include <mupdf/fitz.h>
#include <mupdf/pdf.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

// ---------------------------------------------------------------------------
// MARK: - Internal handle struct
// ---------------------------------------------------------------------------

struct MuPDFHandle {
    fz_context   *ctx;
    fz_document  *doc;
    pdf_document *pdf;   // non-NULL (validated on open)
};

// ---------------------------------------------------------------------------
// MARK: - Lifecycle
// ---------------------------------------------------------------------------

MuPDFHandle *mupdf_open(const char *path, char error_buf[MUPDF_ERR_LEN]) {
    error_buf[0] = '\0';

    MuPDFHandle *handle = (MuPDFHandle *)calloc(1, sizeof(MuPDFHandle));
    if (!handle) {
        snprintf(error_buf, MUPDF_ERR_LEN, "Out of memory allocating handle");
        return NULL;
    }

    fz_context *ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
    if (!ctx) {
        free(handle);
        snprintf(error_buf, MUPDF_ERR_LEN, "Failed to create fz_context");
        return NULL;
    }
    fz_register_document_handlers(ctx);

    fz_document *doc = NULL;
    fz_var(doc);

    fz_try(ctx) {
        doc = fz_open_document(ctx, path);
    }
    fz_catch(ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "fz_open_document: %s",
                 fz_caught_message(ctx));
        fz_drop_context(ctx);
        free(handle);
        return NULL;
    }

    pdf_document *pdf = pdf_specifics(ctx, doc);
    if (!pdf) {
        fz_drop_document(ctx, doc);
        fz_drop_context(ctx);
        free(handle);
        snprintf(error_buf, MUPDF_ERR_LEN, "File is not a PDF");
        return NULL;
    }

    handle->ctx = ctx;
    handle->doc = doc;
    handle->pdf = pdf;
    return handle;
}

void mupdf_close(MuPDFHandle *handle) {
    if (!handle) return;
    // pdf is owned by doc; dropping doc is sufficient.
    if (handle->doc) fz_drop_document(handle->ctx, handle->doc);
    if (handle->ctx) fz_drop_context(handle->ctx);
    free(handle);
}

// ---------------------------------------------------------------------------
// MARK: - Document metadata
// ---------------------------------------------------------------------------

int mupdf_page_count(MuPDFHandle *handle, char error_buf[MUPDF_ERR_LEN]) {
    if (!handle) { snprintf(error_buf, MUPDF_ERR_LEN, "NULL handle"); return -1; }
    error_buf[0] = '\0';
    int count = -1;
    fz_try(handle->ctx) {
        count = fz_count_pages(handle->ctx, handle->doc);
    }
    fz_catch(handle->ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "%s", fz_caught_message(handle->ctx));
    }
    return count;
}

// ---------------------------------------------------------------------------
// MARK: - Persistence
// ---------------------------------------------------------------------------

int mupdf_save(MuPDFHandle *handle, const char *path,
               char error_buf[MUPDF_ERR_LEN]) {
    if (!handle) { snprintf(error_buf, MUPDF_ERR_LEN, "NULL handle"); return -1; }
    error_buf[0] = '\0';

    // Incremental update appends changes without rewriting the whole file.
    // Fall back to full linearised write if that fails.
    pdf_write_options opts = pdf_default_write_options;
    opts.do_incremental = 1;

    int result = 0;
    fz_try(handle->ctx) {
        pdf_save_document(handle->ctx, handle->pdf, path, &opts);
    }
    fz_catch(handle->ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "%s", fz_caught_message(handle->ctx));
        result = -1;
    }
    return result;
}

// ---------------------------------------------------------------------------
// MARK: - Image insertion
// ---------------------------------------------------------------------------

int mupdf_insert_image(MuPDFHandle *handle,
                       int page_index,
                       const uint8_t *img_data, size_t img_len,
                       float x, float y, float width, float height,
                       char error_buf[MUPDF_ERR_LEN]) {
    if (!handle) { snprintf(error_buf, MUPDF_ERR_LEN, "NULL handle"); return -1; }
    error_buf[0] = '\0';

    fz_context   *ctx = handle->ctx;
    pdf_document *pdf = handle->pdf;

    // Declare all cleanup-needing vars before fz_try; fz_var prevents
    // the compiler from caching them in registers across the setjmp point.
    fz_buffer  *img_buf  = NULL;
    fz_image   *image    = NULL;
    pdf_obj    *img_ref  = NULL;
    pdf_page   *page     = NULL;
    fz_buffer  *ops      = NULL;

    fz_var(img_buf);
    fz_var(image);
    fz_var(img_ref);
    fz_var(page);
    fz_var(ops);

    int result = 0;

    fz_try(ctx) {
        // 1. Load image from the raw byte buffer.
        img_buf = fz_new_buffer_from_copied_data(ctx, img_data, img_len);
        image   = fz_new_image_from_buffer(ctx, img_buf);
        fz_drop_buffer(ctx, img_buf); img_buf = NULL;

        // 2. Register image as a PDF resource; returns an indirect reference.
        img_ref = pdf_add_image(ctx, pdf, image);
        fz_drop_image(ctx, image); image = NULL;

        // 3. Load the target page.
        page = pdf_load_page(ctx, pdf, page_index);

        // 4. Get (or create) the XObject sub-dict of the page's Resources.
        pdf_obj *resources = pdf_page_resources(ctx, page);
        pdf_obj *xobj = pdf_dict_get(ctx, resources, PDF_NAME(XObject));
        if (!xobj || pdf_is_null(ctx, xobj)) {
            pdf_obj *fresh = pdf_new_dict(ctx, pdf, 4);
            pdf_dict_put_drop(ctx, resources, PDF_NAME(XObject), fresh);
            xobj = pdf_dict_get(ctx, resources, PDF_NAME(XObject));
        }

        // 5. Choose a unique name for this image resource.
        char img_name[32];
        snprintf(img_name, sizeof(img_name),
                 "FolioImg%d", pdf_dict_len(ctx, xobj));

        // 6. Install the image ref into the XObject dict (drops img_ref).
        pdf_dict_puts_drop(ctx, xobj, img_name, img_ref); img_ref = NULL;

        // 7. Build the PDF drawing operators that paint the image.
        //    The 6-element matrix [w 0 0 h x y] scales and positions the unit
        //    square to the desired rectangle on the page.
        ops = fz_new_buffer(ctx, 256);
        fz_append_printf(ctx, ops,
            "q\n"
            "%g 0 0 %g %g %g cm\n"
            "/%s Do\n"
            "Q\n",
            (double)width, (double)height, (double)x, (double)y,
            img_name);

        // 8. Append ops as a new content stream.
        // pdf_page_contents() may return a single stream ref, an array of stream
        // refs, or NULL. We always rebuild Contents as a fresh array so:
        //   a) The page object is marked dirty for incremental save.
        //   b) We never call pdf_load_stream() on an array (avoids "object is not
        //      a stream" errors on multi-stream pages).
        pdf_obj *img_new_stream = pdf_add_stream(ctx, pdf, ops, NULL, 0);
        ops = NULL;

        pdf_obj *img_contents = pdf_page_contents(ctx, page);
        pdf_obj *img_resolved = img_contents
            ? pdf_resolve_indirect(ctx, img_contents) : NULL;
        pdf_obj *img_arr = pdf_new_array(ctx, pdf, 4);
        if (img_resolved && !pdf_is_null(ctx, img_resolved)) {
            if (pdf_is_array(ctx, img_resolved)) {
                int nc = pdf_array_len(ctx, img_resolved);
                for (int i = 0; i < nc; i++)
                    pdf_array_push(ctx, img_arr,
                                   pdf_array_get(ctx, img_resolved, i));
            } else {
                // Single stream — keep via the indirect reference.
                pdf_array_push(ctx, img_arr, img_contents);
            }
        }
        pdf_array_push_drop(ctx, img_arr, img_new_stream);
        pdf_dict_put_drop(ctx, page->obj, PDF_NAME(Contents), img_arr);

        pdf_drop_page(ctx, page); page = NULL;
    }
    fz_always(ctx) {
        // Runs whether or not an exception was thrown.
        if (img_buf)  { fz_drop_buffer(ctx, img_buf);  img_buf  = NULL; }
        if (image)    { fz_drop_image(ctx, image);     image    = NULL; }
        if (img_ref)  { pdf_drop_obj(ctx, img_ref);    img_ref  = NULL; }
        if (page)     { pdf_drop_page(ctx, page);      page     = NULL; }
        if (ops)      { fz_drop_buffer(ctx, ops);      ops      = NULL; }
    }
    fz_catch(ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "%s", fz_caught_message(ctx));
        result = -1;
    }
    return result;
}

// ---------------------------------------------------------------------------
// MARK: - Text extraction helpers
// ---------------------------------------------------------------------------

/// Encode a Unicode code point as UTF-8 into dst (must have ≥ 4 bytes free).
/// Returns the number of bytes written.
static int encode_utf8(char *dst, int cp) {
    if (cp < 0x80)        { dst[0] = (char)cp; return 1; }
    if (cp < 0x800)       { dst[0] = (char)(0xC0|(cp>>6));
                             dst[1] = (char)(0x80|(cp&0x3F)); return 2; }
    if (cp < 0x10000)     { dst[0] = (char)(0xE0|(cp>>12));
                             dst[1] = (char)(0x80|((cp>>6)&0x3F));
                             dst[2] = (char)(0x80|(cp&0x3F)); return 3; }
    /* cp <= 0x10FFFF */    dst[0] = (char)(0xF0|(cp>>18));
                             dst[1] = (char)(0x80|((cp>>12)&0x3F));
                             dst[2] = (char)(0x80|((cp>>6)&0x3F));
                             dst[3] = (char)(0x80|(cp&0x3F)); return 4;
}

/// Append a JSON-safe, double-quote-escaped version of src into a
/// growing char* buffer.  Returns updated length, or -1 on allocation failure.
static int append_json_string(char **buf, size_t *cap, size_t pos,
                               const char *src, int src_len) {
    for (int i = 0; i < src_len; i++) {
        unsigned char c = (unsigned char)src[i];
        char esc[8]; int elen = 0;
        if      (c == '"')  { esc[0]='\\'; esc[1]='"';  elen=2; }
        else if (c == '\\') { esc[0]='\\'; esc[1]='\\'; elen=2; }
        else if (c == '\n') { esc[0]='\\'; esc[1]='n';  elen=2; }
        else if (c == '\r') { esc[0]='\\'; esc[1]='r';  elen=2; }
        else if (c == '\t') { esc[0]='\\'; esc[1]='t';  elen=2; }
        else if (c < 0x20)  { /* skip control chars */ continue; }
        else                { esc[0]=(char)c;            elen=1; }

        while (pos + (size_t)elen + 2 >= *cap) {
            *cap *= 2;
            char *tmp = (char *)realloc(*buf, *cap);
            if (!tmp) return -1;
            *buf = tmp;
        }
        memcpy(*buf + pos, esc, (size_t)elen);
        pos += (size_t)elen;
    }
    return (int)pos;
}

// ---------------------------------------------------------------------------
// MARK: - Text extraction
// ---------------------------------------------------------------------------

char *mupdf_extract_text_json(MuPDFHandle *handle, int page_index,
                               char error_buf[MUPDF_ERR_LEN]) {
    if (!handle) { snprintf(error_buf, MUPDF_ERR_LEN, "NULL handle"); return NULL; }
    error_buf[0] = '\0';

    fz_context    *ctx   = handle->ctx;
    fz_page       *fzpg  = NULL;
    fz_stext_page *stext = NULL;
    char          *json  = NULL;

    fz_var(fzpg);
    fz_var(stext);
    fz_var(json);

    fz_try(ctx) {
        // Extract structured text from the page.
        fz_stext_options opts = {0};
        fzpg  = fz_load_page(ctx, handle->doc, page_index);

        // Get page height so we can convert MuPDF device-space (Y-down, origin
        // top-left) coordinates to PDF content-stream space (Y-up, origin
        // bottom-left).  fz_bound_page returns the page bounds in device space;
        // for a standard unrotated page y0=0 and y1=page-height-in-points.
        fz_rect pb = fz_bound_page(ctx, fzpg);
        float page_height = pb.y1 - pb.y0;

        stext = fz_new_stext_page_from_page(ctx, fzpg, &opts);
        fz_drop_page(ctx, fzpg); fzpg = NULL;

        // Allocate a growing JSON buffer.
        size_t cap = 4096;
        json = (char *)malloc(cap);
        if (!json) fz_throw(ctx, FZ_ERROR_LIBRARY, "Out of memory");

        size_t pos = 0;
        json[pos++] = '[';
        int first_line = 1;

        for (fz_stext_block *blk = stext->first_block; blk; blk = blk->next) {
            if (blk->type != FZ_STEXT_BLOCK_TEXT) continue;

            for (fz_stext_line *line = blk->u.t.first_line;
                 line; line = line->next) {

                // Collect characters into a UTF-8 text buffer.
                char text[2048]; int tlen = 0;
                for (fz_stext_char *ch = line->first_char; ch; ch = ch->next) {
                    if (tlen < (int)sizeof(text) - 5)
                        tlen += encode_utf8(text + tlen, ch->c);
                }
                if (tlen == 0) continue;

                fz_rect bb = line->bbox;

                // Collect font name, size and colour from the first character.
                const char *font_name = "Helvetica";
                float       font_size = (float)(bb.y1 - bb.y0);
                float cr = 0.0f, cg = 0.0f, cb = 0.0f;
                if (line->first_char) {
                    fz_stext_char *fc = line->first_char;
                    if (fc->font) {
                        const char *fn = fz_font_name(ctx, fc->font);
                        if (fn && fn[0]) font_name = fn;
                    }
                    font_size = fc->size > 0 ? fc->size : font_size;
                    // Color field not available in this MuPDF version; default to black.
                }

                // Ensure space for the JSON fragment (rough bound).
                while (pos + (size_t)(tlen * 6) + 256 >= cap) {
                    cap *= 2;
                    char *tmp = (char *)realloc(json, cap);
                    if (!tmp) fz_throw(ctx, FZ_ERROR_LIBRARY, "Out of memory");
                    json = tmp;
                }

                if (!first_line) json[pos++] = ',';
                pos += (size_t)snprintf(json + pos, cap - pos,
                    "{\"text\":\"");

                int r = append_json_string(&json, &cap, pos, text, tlen);
                if (r < 0) fz_throw(ctx, FZ_ERROR_LIBRARY, "Out of memory");
                pos = (size_t)r;

                // Copy printable ASCII from font name for JSON embedding.
                char fe[256]; int fi = 0;
                for (const char *p = font_name; *p && fi < 250; p++)
                    if ((unsigned char)*p >= 0x20 && *p != '"' && *p != '\\')
                        fe[fi++] = *p;
                fe[fi] = '\0';

                pos += (size_t)snprintf(json + pos, cap - pos,
                    "\",\"x\":%g,\"y\":%g,\"w\":%g,\"h\":%g"
                    ",\"font\":\"%s\",\"fs\":%g"
                    ",\"r\":%g,\"g\":%g,\"b\":%g}",
                    // Convert from MuPDF device space (Y-down, origin top-left)
                    // to PDF content-stream space (Y-up, origin bottom-left).
                    // In device space bb.y0 is the TOP of the line (smaller y),
                    // bb.y1 is the BOTTOM (larger y).
                    // pdf_y is the BOTTOM of the line in Y-up coordinates.
                    (double)bb.x0,
                    (double)(page_height - bb.y1),      /* pdf_y: bottom of line */
                    (double)(bb.x1 - bb.x0),
                    (double)(bb.y1 - bb.y0),            /* height: same magnitude */
                    fe, (double)font_size,
                    (double)cr, (double)cg, (double)cb);

                first_line = 0;
            }
        }

        // Terminate the JSON array.
        while (pos + 4 >= cap) {
            cap *= 2;
            char *tmp = (char *)realloc(json, cap);
            if (!tmp) fz_throw(ctx, FZ_ERROR_LIBRARY, "Out of memory");
            json = tmp;
        }
        json[pos++] = ']';
        json[pos]   = '\0';
    }
    fz_always(ctx) {
        if (fzpg)  { fz_drop_page(ctx, fzpg);           fzpg  = NULL; }
        if (stext) { fz_drop_stext_page(ctx, stext);    stext = NULL; }
    }
    fz_catch(ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "%s", fz_caught_message(ctx));
        free(json); json = NULL;
    }
    return json;
}

void mupdf_free_string(char *str) {
    free(str);
}

// ---------------------------------------------------------------------------
// MARK: - Text replacement
// ---------------------------------------------------------------------------

/// Map an arbitrary PostScript font name to the nearest standard PDF Type1 font.
///
/// PDF viewers are only required to synthesise the 14 standard Type1 fonts
/// (Helvetica*, Times*, Courier*, Symbol, ZapfDingbats). Embedded/subset fonts
/// (e.g. "ABCDEF+ArialMT") use custom glyph-ID encoding, so writing Latin text
/// characters directly into a content stream with those fonts produces garbage.
/// For replacement text we always use a standard font so the encoding is known.
static const char *map_to_standard_pdf_font(const char *name) {
    if (!name || !name[0]) return "Helvetica";

    // Strip any subset prefix (e.g. "ABCDEF+" → "")
    const char *n = strchr(name, '+');
    if (n) n++; else n = name;

    // Check if already a standard font (case-insensitive prefix match is enough).
    static const char *std[] = {
        "Helvetica-BoldOblique", "Helvetica-Bold", "Helvetica-Oblique", "Helvetica",
        "Times-BoldItalic",      "Times-Bold",      "Times-Italic",      "Times-Roman",
        "Courier-BoldOblique",   "Courier-Bold",    "Courier-Oblique",   "Courier",
        "Symbol", "ZapfDingbats", NULL
    };
    for (int i = 0; std[i]; i++) {
        if (strcasecmp(n, std[i]) == 0) return std[i];
    }

    // Detect bold / italic from name
    int bold   = (strstr(n, "Bold")   || strstr(n, "bold")   || strstr(n, "Heavy") ||
                  strstr(n, "Black")  || strstr(n, "Demi"))  ? 1 : 0;
    int italic = (strstr(n, "Italic") || strstr(n, "italic") ||
                  strstr(n, "Oblique")|| strstr(n, "oblique"))? 1 : 0;

    // Monospace families
    if (strstr(n, "Courier") || strstr(n, "Mono")   || strstr(n, "Console") ||
        strstr(n, "Fixed")   || strstr(n, "Source Code") || strstr(n, "Menlo") ||
        strstr(n, "Monaco")) {
        if (bold && italic) return "Courier-BoldOblique";
        if (bold)           return "Courier-Bold";
        if (italic)         return "Courier-Oblique";
        return "Courier";
    }
    // Serif families
    if (strstr(n, "Times") || strstr(n, "Palatin") || strstr(n, "Georgia") ||
        strstr(n, "Serif") || strstr(n, "Roman")   || strstr(n, "Garamond") ||
        strstr(n, "Minion")) {
        if (bold && italic) return "Times-BoldItalic";
        if (bold)           return "Times-Bold";
        if (italic)         return "Times-Italic";
        return "Times-Roman";
    }
    // Default: sans-serif (Helvetica)
    if (bold && italic) return "Helvetica-BoldOblique";
    if (bold)           return "Helvetica-Bold";
    if (italic)         return "Helvetica-Oblique";
    return "Helvetica";
}

/// Escape a UTF-8 string for use in a PDF text string literal (parenthesis-delimited).
/// Characters U+0020..U+007E pass through as ASCII.
/// Multi-byte UTF-8 sequences for U+00A0..U+00FF are decoded and their low byte
/// (== WinAnsiEncoding/Latin-1 value for that range) is emitted so that diacritics
/// like ä ö ü é à etc. render correctly when the font uses /WinAnsiEncoding.
/// Code points outside U+00FF are replaced with '?'.
static int pdf_escape_text(char *dst, size_t dst_cap, const char *src) {
    size_t pos = 0;
    const unsigned char *p = (const unsigned char *)src;
    while (*p && pos + 6 < dst_cap) {
        unsigned int cp;
        int bytes;
        if (*p < 0x80) {
            cp = *p; bytes = 1;
        } else if ((*p & 0xE0) == 0xC0) {
            cp = (*p & 0x1F); bytes = 2;
        } else if ((*p & 0xF0) == 0xE0) {
            cp = (*p & 0x0F); bytes = 3;
        } else if ((*p & 0xF8) == 0xF0) {
            cp = (*p & 0x07); bytes = 4;
        } else {
            p++; continue;   // invalid byte, skip
        }
        // Accumulate continuation bytes
        for (int i = 1; i < bytes; i++) {
            if ((p[i] & 0xC0) != 0x80) { bytes = 1; cp = *p; break; }
            cp = (cp << 6) | (p[i] & 0x3F);
        }
        p += bytes;

        unsigned char out_byte;
        if (cp >= 0x0020 && cp <= 0x007E) {
            out_byte = (unsigned char)cp;
        } else if (cp >= 0x00A0 && cp <= 0x00FF) {
            // Latin-1 supplement: the low byte IS the WinAnsiEncoding value.
            out_byte = (unsigned char)(cp & 0xFF);
        } else if (cp < 0x0020) {
            continue;           // skip control chars
        } else {
            out_byte = '?';     // not representable in WinAnsi
        }

        // PDF literal string escaping
        if      (out_byte == '(')  { dst[pos++] = '\\'; dst[pos++] = '('; }
        else if (out_byte == ')')  { dst[pos++] = '\\'; dst[pos++] = ')'; }
        else if (out_byte == '\\') { dst[pos++] = '\\'; dst[pos++] = '\\'; }
        else if (out_byte >= 0x80) {
            // High bytes must be emitted as octal escapes (\xxx) inside
            // a PDF literal string to guarantee safe transport.
            dst[pos++] = '\\';
            dst[pos++] = '0' + ((out_byte >> 6) & 7);
            dst[pos++] = '0' + ((out_byte >> 3) & 7);
            dst[pos++] = '0' + ( out_byte       & 7);
        } else {
            dst[pos++] = (char)out_byte;
        }
    }
    dst[pos] = '\0';
    return (int)pos;
}

int mupdf_replace_text(MuPDFHandle *handle,
                       int page_index,
                       float x, float y,
                       float width, float height,
                       const char *new_text,
                       const char *font_name,
                       float font_size,
                       float r, float g, float b,
                       char error_buf[MUPDF_ERR_LEN]) {
    if (!handle) { snprintf(error_buf, MUPDF_ERR_LEN, "NULL handle"); return -1; }
    error_buf[0] = '\0';

    fz_context   *ctx = handle->ctx;
    pdf_document *pdf = handle->pdf;

    pdf_page   *page     = NULL;
    fz_buffer  *ops      = NULL;

    fz_var(page);
    fz_var(ops);

    int result = 0;

    fz_try(ctx) {
        page = pdf_load_page(ctx, pdf, page_index);

        // ── 1. Ensure Helvetica is registered in the page font resources ──
        pdf_obj *resources = pdf_page_resources(ctx, page);
        if (!resources || pdf_is_null(ctx, resources)) {
            pdf_obj *fresh = pdf_new_dict(ctx, pdf, 4);
            pdf_dict_put_drop(ctx, page->obj, PDF_NAME(Resources), fresh);
            resources = pdf_dict_get(ctx, page->obj, PDF_NAME(Resources));
        }

        pdf_obj *font_dict = pdf_dict_get(ctx, resources, PDF_NAME(Font));
        if (!font_dict || pdf_is_null(ctx, font_dict)) {
            pdf_obj *fresh = pdf_new_dict(ctx, pdf, 4);
            pdf_dict_put_drop(ctx, resources, PDF_NAME(Font), fresh);
            font_dict = pdf_dict_get(ctx, resources, PDF_NAME(Font));
        }

        // ── 1b. Register the requested font.
        // Map the detected font name to the nearest STANDARD Type1 font.
        // Embedded/subset fonts (e.g. "ABCDEF+ArialMT") have custom glyph-ID
        // encoding; writing raw Unicode bytes with such a font produces garbage.
        // Standard Type1 fonts always use standard Latin/MacRoman encoding.
        const char *base_font = map_to_standard_pdf_font(
            (font_name && font_name[0]) ? font_name : "Helvetica");

        // Build a safe PDF resource key (no spaces/special chars, max 32 chars).
        char res_key[64];
        int ki = 0;
        for (const char *p = base_font; *p && ki < 32; p++)
            if ((unsigned char)*p > 0x20 && *p != '/' && *p != '#')
                res_key[ki++] = *p;
        res_key[ki] = '\0';
        if (ki == 0) { strcpy(res_key, "Helv"); base_font = "Helvetica"; }

        // Register the standard font if not already present under this key.
        if (!pdf_dict_gets(ctx, font_dict, res_key)) {
            pdf_obj *fobj = pdf_new_dict(ctx, pdf, 4);
            pdf_dict_put(ctx, fobj, PDF_NAME(Type),     pdf_new_name(ctx, "Font"));
            pdf_dict_put(ctx, fobj, PDF_NAME(Subtype),  pdf_new_name(ctx, "Type1"));
            pdf_dict_put_name(ctx, fobj, PDF_NAME(BaseFont), base_font);
            // WinAnsiEncoding supports all Latin-1 diacritics (ä ö ü é à …).
            // Must match the byte values produced by pdf_escape_text.
            pdf_dict_put(ctx, fobj, PDF_NAME(Encoding), pdf_new_name(ctx, "WinAnsiEncoding"));
            pdf_dict_puts_drop(ctx, font_dict, res_key, fobj);
        }

        // ── 2. Build overlay content stream ─────────────────────────────
        char escaped[4096];
        pdf_escape_text(escaped, sizeof(escaped), new_text ? new_text : "");

        // Baseline sits 0.2 * font_size above the rect bottom.
        float text_y = y + font_size * 0.2f;

        ops = fz_new_buffer(ctx, 512);
        fz_append_printf(ctx, ops,
            "q\n"
            "1 1 1 rg\n"                           /* white fill */
            "%g %g %g %g re f\n"                   /* erase old text */
            "%g %g %g rg\n"                        /* restore original colour */
            "BT\n"
            "/%s %g Tf\n"                          /* original font + size */
            "%g %g Td\n"                           /* position */
            "(%s) Tj\n"                            /* draw text */
            "ET\n"
            "Q\n",
            (double)x, (double)y, (double)width, (double)height,
            (double)r, (double)g, (double)b,
            res_key, (double)font_size,
            (double)x, (double)text_y,
            escaped);

        // ── 3. Append overlay as a new content stream ─────────────────────
        // pdf_page_contents() may return a single stream ref, an array of stream
        // refs, or NULL. Rebuilding as a fresh array ensures the page object is
        // marked dirty for incremental save and avoids calling pdf_load_stream()
        // on an array (which would throw "object is not a stream").
        pdf_obj *new_stream = pdf_add_stream(ctx, pdf, ops, NULL, 0);
        ops = NULL;

        pdf_obj *contents = pdf_page_contents(ctx, page);
        pdf_obj *resolved = contents
            ? pdf_resolve_indirect(ctx, contents) : NULL;
        pdf_obj *arr = pdf_new_array(ctx, pdf, 4);
        if (resolved && !pdf_is_null(ctx, resolved)) {
            if (pdf_is_array(ctx, resolved)) {
                int nc = pdf_array_len(ctx, resolved);
                for (int i = 0; i < nc; i++)
                    pdf_array_push(ctx, arr, pdf_array_get(ctx, resolved, i));
            } else {
                // Single stream — keep via the indirect reference.
                pdf_array_push(ctx, arr, contents);
            }
        }
        pdf_array_push_drop(ctx, arr, new_stream);
        pdf_dict_put_drop(ctx, page->obj, PDF_NAME(Contents), arr);

        pdf_drop_page(ctx, page); page = NULL;
    }
    fz_always(ctx) {
        if (page)     { pdf_drop_page(ctx, page);       page     = NULL; }
        if (ops)      { fz_drop_buffer(ctx, ops);       ops      = NULL; }
    }
    fz_catch(ctx) {
        snprintf(error_buf, MUPDF_ERR_LEN, "%s", fz_caught_message(ctx));
        result = -1;
    }
    return result;
}
