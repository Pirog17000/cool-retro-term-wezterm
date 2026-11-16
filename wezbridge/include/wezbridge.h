/*
 * wezbridge - C ABI over the wezterm-term terminal emulation core.
 *
 * The bridge owns a wezterm `Terminal` model.  Bytes coming from the pty are
 * fed in with wt_advance(); anything the model wants to send back to the
 * child process (key encodings, mouse reports, query answers) accumulates in
 * an output buffer drained with wt_take_output().
 */
#ifndef WEZBRIDGE_H
#define WEZBRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct WtTerminal WtTerminal;

/* Color kinds for WtCell.fg_kind / bg_kind */
#define WT_COLOR_DEFAULT 0
#define WT_COLOR_PALETTE 1 /* value = palette index 0..255 */
#define WT_COLOR_RGB     2 /* value = 0x00RRGGBB */

/* WtCell.flags */
#define WT_ATTR_BOLD      (1u << 0)
#define WT_ATTR_FAINT     (1u << 1)
#define WT_ATTR_ITALIC    (1u << 2)
#define WT_ATTR_UNDERLINE (1u << 3)
#define WT_ATTR_BLINK     (1u << 4)
#define WT_ATTR_REVERSE   (1u << 5)
#define WT_ATTR_INVISIBLE (1u << 6)
#define WT_ATTR_STRIKE    (1u << 7)
#define WT_ATTR_OVERLINE  (1u << 8)

#define WT_CELL_MAX_CP 6

typedef struct WtCell {
    uint32_t cp[WT_CELL_MAX_CP]; /* grapheme codepoints; ncp==0 => continuation of a wide cell */
    uint8_t ncp;
    uint8_t width;
    uint16_t flags;
    uint8_t fg_kind;
    uint8_t bg_kind;
    uint16_t _pad;
    uint32_t fg;
    uint32_t bg;
} WtCell;

/* Cursor shapes (WtInfo.cursor_shape) */
#define WT_CURSOR_DEFAULT        0
#define WT_CURSOR_BLINK_BLOCK    1
#define WT_CURSOR_STEADY_BLOCK   2
#define WT_CURSOR_BLINK_UNDER    3
#define WT_CURSOR_STEADY_UNDER   4
#define WT_CURSOR_BLINK_BAR      5
#define WT_CURSOR_STEADY_BAR     6

typedef struct WtInfo {
    int64_t rows;
    int64_t cols;
    int64_t total_lines;          /* physical lines held by the active screen (scrollback + visible) */
    int64_t top_stable;           /* stable index of physical line 0 */
    int64_t first_visible_stable; /* stable index of the first visible row */
    int64_t cursor_x;
    int64_t cursor_y;
    uint64_t seqno;
    uint8_t cursor_visible;
    uint8_t cursor_shape;
    uint8_t alt_screen;
    uint8_t mouse_grabbed;
    uint8_t bracketed_paste;
    uint8_t reverse_video;
    uint8_t _pad[2];
} WtInfo;

/* Special keys for wt_key(kind = WT_KEYKIND_SPECIAL) */
enum {
    WT_KEY_BACKSPACE = 1,
    WT_KEY_TAB,
    WT_KEY_ENTER,
    WT_KEY_ESCAPE,
    WT_KEY_INSERT,
    WT_KEY_DELETE,
    WT_KEY_HOME,
    WT_KEY_END,
    WT_KEY_PAGEUP,
    WT_KEY_PAGEDOWN,
    WT_KEY_LEFT,
    WT_KEY_RIGHT,
    WT_KEY_UP,
    WT_KEY_DOWN,
    WT_KEY_F1 = 100 /* F1..F24 = WT_KEY_F1 + n - 1 */
};

#define WT_KEYKIND_CHAR    0
#define WT_KEYKIND_SPECIAL 1

#define WT_MOD_SHIFT (1u << 0)
#define WT_MOD_ALT   (1u << 1)
#define WT_MOD_CTRL  (1u << 2)
#define WT_MOD_SUPER (1u << 3)

#define WT_MOUSE_PRESS   0
#define WT_MOUSE_MOVE    1
#define WT_MOUSE_RELEASE 2

#define WT_BUTTON_LEFT       0
#define WT_BUTTON_MIDDLE     1
#define WT_BUTTON_RIGHT      2
#define WT_BUTTON_WHEEL_UP   3
#define WT_BUTTON_WHEEL_DOWN 4
#define WT_BUTTON_NONE       5

WtTerminal* wt_new(uint32_t rows, uint32_t cols, uint32_t scrollback, uint8_t conpty_quirks);
void wt_free(WtTerminal* t);

void wt_advance(WtTerminal* t, const uint8_t* data, size_t len);
size_t wt_output_len(WtTerminal* t);
size_t wt_take_output(WtTerminal* t, uint8_t* buf, size_t cap);

void wt_resize(WtTerminal* t, uint32_t rows, uint32_t cols, uint32_t pixel_w, uint32_t pixel_h);
void wt_set_scrollback(WtTerminal* t, uint32_t scrollback);
void wt_info(WtTerminal* t, WtInfo* out);

/* Copies the physical line `phys` into `cells` (up to `cap` columns).
 * Returns the number of columns written (normally == cols).  *wrapped is set
 * when the line soft-wraps into the next one. */
size_t wt_line(WtTerminal* t, int64_t phys, WtCell* cells, size_t cap, uint8_t* wrapped);

/* Returns the full title length; copies up to cap bytes (UTF-8, not NUL terminated). */
size_t wt_title(WtTerminal* t, uint8_t* buf, size_t cap);
/* Returns and resets the number of BEL characters seen since the last call. */
uint32_t wt_take_bells(WtTerminal* t);

void wt_key(WtTerminal* t, uint8_t kind, uint32_t value, uint32_t mods);
void wt_paste(WtTerminal* t, const uint8_t* utf8, size_t len);
void wt_mouse(WtTerminal* t, uint8_t kind, uint8_t button, int64_t x, int64_t y, uint32_t mods);
void wt_focus(WtTerminal* t, uint8_t focused);

#ifdef __cplusplus
}
#endif

#endif /* WEZBRIDGE_H */
