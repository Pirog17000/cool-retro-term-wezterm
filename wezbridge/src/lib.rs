//! C ABI bridge that lets cool-retro-term (qmltermwidget, C++/Qt) use the
//! wezterm-term emulation core instead of Konsole's Vt102Emulation.
//!
//! See `include/wezbridge.h` for the C declarations.  Every exported function
//! is wrapped in `catch_unwind` so a panic inside the model can never unwind
//! across the FFI boundary into Qt.

use std::ffi::c_void;
use std::io::Write;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use termwiz::color::ColorAttribute;
use termwiz::surface::{CursorShape, CursorVisibility};
use wezterm_bidi::ParagraphDirectionHint;
use wezterm_term::color::ColorPalette;
use wezterm_term::config::{BidiMode, NewlineCanon};
use wezterm_term::{
    Alert, AlertHandler, Blink, Intensity, KeyCode, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind, Terminal, TerminalConfiguration, TerminalSize, Underline, UnicodeVersion,
};

// ---------------------------------------------------------------------------
// C layout types (must match include/wezbridge.h)

const WT_CELL_MAX_CP: usize = 6;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct WtCell {
    cp: [u32; WT_CELL_MAX_CP],
    ncp: u8,
    width: u8,
    flags: u16,
    fg_kind: u8,
    bg_kind: u8,
    _pad: u16,
    fg: u32,
    bg: u32,
}

#[repr(C)]
#[derive(Default)]
pub struct WtInfo {
    rows: i64,
    cols: i64,
    total_lines: i64,
    top_stable: i64,
    first_visible_stable: i64,
    cursor_x: i64,
    cursor_y: i64,
    seqno: u64,
    cursor_visible: u8,
    cursor_shape: u8,
    alt_screen: u8,
    mouse_grabbed: u8,
    bracketed_paste: u8,
    reverse_video: u8,
    _pad: [u8; 2],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct WtConfig {
    scrollback: u32,
    csi_u_keys: u8,
    kitty_keyboard: u8,
    unicode_version: u8,
    ambiguous_wide: u8,
    paste_newlines: u8,
    normalize_nfc: u8,
    bidi_enabled: u8,
    bidi_hint: u8,
    title_reporting: u8,
    _pad: [u8; 3],
    answerback: [u8; 64],
}

impl Default for WtConfig {
    fn default() -> Self {
        Self {
            scrollback: 10000,
            csi_u_keys: 0,
            kitty_keyboard: 0,
            unicode_version: 9,
            ambiguous_wide: 0,
            paste_newlines: 0,
            normalize_nfc: 0,
            bidi_enabled: 0,
            bidi_hint: 0,
            title_reporting: 0,
            _pad: [0; 3],
            answerback: [0; 64],
        }
    }
}

const WT_COLOR_DEFAULT: u8 = 0;
const WT_COLOR_PALETTE: u8 = 1;
const WT_COLOR_RGB: u8 = 2;

const WT_ATTR_BOLD: u16 = 1 << 0;
const WT_ATTR_FAINT: u16 = 1 << 1;
const WT_ATTR_ITALIC: u16 = 1 << 2;
const WT_ATTR_UNDERLINE: u16 = 1 << 3;
const WT_ATTR_BLINK: u16 = 1 << 4;
const WT_ATTR_REVERSE: u16 = 1 << 5;
const WT_ATTR_INVISIBLE: u16 = 1 << 6;
const WT_ATTR_STRIKE: u16 = 1 << 7;
const WT_ATTR_OVERLINE: u16 = 1 << 8;

const WT_MOD_SHIFT: u32 = 1 << 0;
const WT_MOD_ALT: u32 = 1 << 1;
const WT_MOD_CTRL: u32 = 1 << 2;
const WT_MOD_SUPER: u32 = 1 << 3;

// ---------------------------------------------------------------------------
// Configuration

#[derive(Debug)]
struct Config {
    scrollback: usize,
    csi_u_keys: bool,
    kitty_keyboard: bool,
    unicode_version: u8,
    ambiguous_wide: bool,
    paste_newlines: Option<NewlineCanon>,
    normalize_nfc: bool,
    bidi: BidiMode,
    title_reporting: bool,
    answerback: String,
}

impl From<&WtConfig> for Config {
    fn from(c: &WtConfig) -> Self {
        let end = c
            .answerback
            .iter()
            .position(|b| *b == 0)
            .unwrap_or(c.answerback.len());
        Config {
            scrollback: c.scrollback as usize,
            csi_u_keys: c.csi_u_keys != 0,
            kitty_keyboard: c.kitty_keyboard != 0,
            unicode_version: c.unicode_version.clamp(9, 16),
            ambiguous_wide: c.ambiguous_wide != 0,
            paste_newlines: match c.paste_newlines {
                1 => Some(NewlineCanon::None),
                2 => Some(NewlineCanon::LineFeed),
                3 => Some(NewlineCanon::CarriageReturn),
                4 => Some(NewlineCanon::CarriageReturnAndLineFeed),
                _ => None,
            },
            normalize_nfc: c.normalize_nfc != 0,
            bidi: BidiMode {
                enabled: c.bidi_enabled != 0,
                hint: match c.bidi_hint {
                    1 => ParagraphDirectionHint::RightToLeft,
                    2 => ParagraphDirectionHint::AutoLeftToRight,
                    3 => ParagraphDirectionHint::AutoRightToLeft,
                    _ => ParagraphDirectionHint::LeftToRight,
                },
            },
            title_reporting: c.title_reporting != 0,
            answerback: String::from_utf8_lossy(&c.answerback[..end]).into_owned(),
        }
    }
}

impl TerminalConfiguration for Config {
    fn scrollback_size(&self) -> usize {
        self.scrollback
    }
    fn color_palette(&self) -> ColorPalette {
        ColorPalette::default()
    }
    fn enable_csi_u_key_encoding(&self) -> bool {
        self.csi_u_keys
    }
    fn enable_kitty_keyboard(&self) -> bool {
        self.kitty_keyboard
    }
    fn unicode_version(&self) -> UnicodeVersion {
        UnicodeVersion {
            version: self.unicode_version,
            ambiguous_are_wide: self.ambiguous_wide,
            cell_widths: None,
        }
    }
    fn canonicalize_pasted_newlines(&self) -> NewlineCanon {
        self.paste_newlines.unwrap_or_default()
    }
    fn normalize_output_to_unicode_nfc(&self) -> bool {
        self.normalize_nfc
    }
    fn bidi_mode(&self) -> BidiMode {
        self.bidi
    }
    fn enable_title_reporting(&self) -> bool {
        self.title_reporting
    }
    fn enq_answerback(&self) -> String {
        self.answerback.clone()
    }
}

// ---------------------------------------------------------------------------
// Model plumbing

/// Called (from wezterm's writer thread) when output for the child process
/// is ready to be collected with wt_take_output().
pub type WtOutputCallback = Option<extern "C" fn(user: *mut c_void)>;

#[derive(Default)]
struct Notify {
    cb: WtOutputCallback,
    user: usize,
}

/// wezterm-term writes through a BufWriter feeding a background thread, so
/// data shows up here asynchronously; flush() pokes the host to collect it.
#[derive(Clone, Default)]
struct OutBuf {
    data: Arc<Mutex<Vec<u8>>>,
    notify: Arc<Mutex<Notify>>,
}

impl Write for OutBuf {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.data.lock().unwrap().extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        if self.data.lock().unwrap().is_empty() {
            return Ok(());
        }
        // The lock is held during the call so that clearing the callback is
        // a hard barrier for the host's teardown.
        let n = self.notify.lock().unwrap();
        if let Some(cb) = n.cb {
            cb(n.user as *mut c_void);
        }
        Ok(())
    }
}

struct Alerts {
    bells: Arc<AtomicU32>,
}

impl AlertHandler for Alerts {
    fn alert(&mut self, alert: Alert) {
        if let Alert::Bell = alert {
            self.bells.fetch_add(1, Ordering::Relaxed);
        }
    }
}

pub struct WtTerminal {
    term: Terminal,
    out: OutBuf,
    bells: Arc<AtomicU32>,
    config: WtConfig,
}

fn guard<R: Default, F: FnOnce() -> R>(f: F) -> R {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_default()
}

unsafe fn term_mut<'a>(t: *mut WtTerminal) -> Option<&'a mut WtTerminal> {
    t.as_mut()
}

// ---------------------------------------------------------------------------
// Lifecycle / configuration

#[no_mangle]
pub extern "C" fn wt_default_config(out: *mut WtConfig) {
    if let Some(out) = unsafe { out.as_mut() } {
        *out = WtConfig::default();
    }
}

#[no_mangle]
pub unsafe extern "C" fn wt_new(
    rows: u32,
    cols: u32,
    config: *const WtConfig,
    conpty_quirks: u8,
) -> *mut WtTerminal {
    let cfg = config.as_ref().copied().unwrap_or_default();
    let r = catch_unwind(move || {
        let out = OutBuf::default();
        let bells = Arc::new(AtomicU32::new(0));
        let size = TerminalSize {
            rows: rows.max(1) as usize,
            cols: cols.max(1) as usize,
            pixel_width: 0,
            pixel_height: 0,
            dpi: 96,
        };
        let mut term = Terminal::new(
            size,
            Arc::new(Config::from(&cfg)),
            "cool-retro-term",
            env!("CARGO_PKG_VERSION"),
            Box::new(out.clone()),
        );
        if conpty_quirks != 0 {
            term.enable_conpty_quirks();
        }
        term.set_notification_handler(Box::new(Alerts {
            bells: Arc::clone(&bells),
        }));
        Box::into_raw(Box::new(WtTerminal {
            term,
            out,
            bells,
            config: cfg,
        }))
    });
    r.unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn wt_free(t: *mut WtTerminal) {
    if !t.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(t))));
    }
}

#[no_mangle]
pub unsafe extern "C" fn wt_set_config(t: *mut WtTerminal, config: *const WtConfig) {
    guard(|| {
        if let (Some(t), Some(cfg)) = (term_mut(t), config.as_ref()) {
            t.config = *cfg;
            t.term.set_config(Arc::new(Config::from(&t.config)));
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_set_scrollback(t: *mut WtTerminal, scrollback: u32) {
    guard(|| {
        if let Some(t) = term_mut(t) {
            t.config.scrollback = scrollback;
            t.term.set_config(Arc::new(Config::from(&t.config)));
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_set_output_callback(
    t: *mut WtTerminal,
    cb: WtOutputCallback,
    user: *mut c_void,
) {
    guard(|| {
        if let Some(t) = term_mut(t) {
            let mut n = t.out.notify.lock().unwrap();
            n.cb = cb;
            n.user = user as usize;
        }
    })
}

// ---------------------------------------------------------------------------
// I/O

#[no_mangle]
pub unsafe extern "C" fn wt_advance(t: *mut WtTerminal, data: *const u8, len: usize) {
    guard(|| {
        if let (Some(t), false) = (term_mut(t), data.is_null()) {
            let bytes = std::slice::from_raw_parts(data, len);
            t.term.advance_bytes(bytes);
        }
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_output_len(t: *mut WtTerminal) -> usize {
    guard(|| {
        term_mut(t)
            .map(|t| t.out.data.lock().unwrap().len())
            .unwrap_or(0)
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_take_output(t: *mut WtTerminal, buf: *mut u8, cap: usize) -> usize {
    guard(|| {
        let Some(t) = term_mut(t) else { return 0 };
        if buf.is_null() || cap == 0 {
            return 0;
        }
        let mut pending = t.out.data.lock().unwrap();
        let n = pending.len().min(cap);
        std::ptr::copy_nonoverlapping(pending.as_ptr(), buf, n);
        pending.drain(..n);
        n
    })
}

// ---------------------------------------------------------------------------
// Geometry / state

#[no_mangle]
pub unsafe extern "C" fn wt_resize(t: *mut WtTerminal, rows: u32, cols: u32, pw: u32, ph: u32) {
    guard(|| {
        if let Some(t) = term_mut(t) {
            t.term.resize(TerminalSize {
                rows: rows.max(1) as usize,
                cols: cols.max(1) as usize,
                pixel_width: pw as usize,
                pixel_height: ph as usize,
                dpi: 96,
            });
        }
    })
}

fn cursor_shape_code(shape: CursorShape) -> u8 {
    match shape {
        CursorShape::Default => 0,
        CursorShape::BlinkingBlock => 1,
        CursorShape::SteadyBlock => 2,
        CursorShape::BlinkingUnderline => 3,
        CursorShape::SteadyUnderline => 4,
        CursorShape::BlinkingBar => 5,
        CursorShape::SteadyBar => 6,
    }
}

#[no_mangle]
pub unsafe extern "C" fn wt_info(t: *mut WtTerminal, out: *mut WtInfo) {
    guard(|| {
        let (Some(t), Some(out)) = (term_mut(t), out.as_mut()) else {
            return;
        };
        let term = &t.term;
        let screen = term.screen();
        let total = screen.scrollback_rows();
        let rows = screen.physical_rows;
        let cursor = term.cursor_pos();
        *out = WtInfo {
            rows: rows as i64,
            cols: screen.physical_cols as i64,
            total_lines: total as i64,
            top_stable: screen.phys_to_stable_row_index(0) as i64,
            first_visible_stable: screen.visible_row_to_stable_row(0) as i64,
            cursor_x: cursor.x as i64,
            cursor_y: cursor.y,
            seqno: term.current_seqno() as u64,
            cursor_visible: (cursor.visibility == CursorVisibility::Visible) as u8,
            cursor_shape: cursor_shape_code(cursor.shape),
            alt_screen: term.is_alt_screen_active() as u8,
            mouse_grabbed: term.is_mouse_grabbed() as u8,
            bracketed_paste: term.bracketed_paste_enabled() as u8,
            reverse_video: term.get_reverse_video() as u8,
            _pad: [0; 2],
        };
    })
}

fn encode_color(c: ColorAttribute) -> (u8, u32) {
    match c {
        ColorAttribute::Default => (WT_COLOR_DEFAULT, 0),
        ColorAttribute::PaletteIndex(i) => (WT_COLOR_PALETTE, i as u32),
        ColorAttribute::TrueColorWithPaletteFallback(rgb, _)
        | ColorAttribute::TrueColorWithDefaultFallback(rgb) => {
            let (r, g, b, _) = rgb.to_srgb_u8();
            (
                WT_COLOR_RGB,
                ((r as u32) << 16) | ((g as u32) << 8) | b as u32,
            )
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn wt_line(
    t: *mut WtTerminal,
    phys: i64,
    cells: *mut WtCell,
    cap: usize,
    wrapped: *mut u8,
) -> usize {
    guard(|| {
        let Some(t) = term_mut(t) else { return 0 };
        if cells.is_null() || cap == 0 || phys < 0 {
            return 0;
        }
        let screen = t.term.screen();
        let phys = phys as usize;
        if phys >= screen.scrollback_rows() {
            return 0;
        }
        let cols = screen.physical_cols.min(cap);
        let out = std::slice::from_raw_parts_mut(cells, cols);
        for c in out.iter_mut() {
            *c = WtCell {
                cp: [b' ' as u32, 0, 0, 0, 0, 0],
                ncp: 1,
                width: 1,
                ..Default::default()
            };
        }

        let mut was_wrapped = false;
        screen.with_phys_lines(phys..phys + 1, |lines| {
            let Some(line) = lines.first() else { return };
            was_wrapped = line.last_cell_was_wrapped();
            for cell in line.visible_cells() {
                let idx = cell.cell_index();
                if idx >= cols {
                    break;
                }
                let attrs = cell.attrs();
                let mut flags = 0u16;
                match attrs.intensity() {
                    Intensity::Bold => flags |= WT_ATTR_BOLD,
                    Intensity::Half => flags |= WT_ATTR_FAINT,
                    Intensity::Normal => {}
                }
                if attrs.italic() {
                    flags |= WT_ATTR_ITALIC;
                }
                if attrs.underline() != Underline::None {
                    flags |= WT_ATTR_UNDERLINE;
                }
                if attrs.blink() != Blink::None {
                    flags |= WT_ATTR_BLINK;
                }
                if attrs.reverse() {
                    flags |= WT_ATTR_REVERSE;
                }
                if attrs.invisible() {
                    flags |= WT_ATTR_INVISIBLE;
                }
                if attrs.strikethrough() {
                    flags |= WT_ATTR_STRIKE;
                }
                if attrs.overline() {
                    flags |= WT_ATTR_OVERLINE;
                }
                let (fg_kind, fg) = encode_color(attrs.foreground());
                let (bg_kind, bg) = encode_color(attrs.background());

                let mut cp = [0u32; WT_CELL_MAX_CP];
                let mut ncp = 0usize;
                for ch in cell.str().chars() {
                    if ncp == WT_CELL_MAX_CP {
                        break;
                    }
                    cp[ncp] = ch as u32;
                    ncp += 1;
                }
                if ncp == 0 {
                    cp[0] = b' ' as u32;
                    ncp = 1;
                }
                let width = cell.width().clamp(1, 2);
                out[idx] = WtCell {
                    cp,
                    ncp: ncp as u8,
                    width: width as u8,
                    flags,
                    fg_kind,
                    bg_kind,
                    _pad: 0,
                    fg,
                    bg,
                };
                // Continuation half of a double-width glyph keeps the colors
                // so the background is painted consistently.
                for k in 1..width {
                    if idx + k < cols {
                        out[idx + k] = WtCell {
                            cp: [0; WT_CELL_MAX_CP],
                            ncp: 0,
                            width: 0,
                            flags,
                            fg_kind,
                            bg_kind,
                            _pad: 0,
                            fg,
                            bg,
                        };
                    }
                }
            }
        });
        if let Some(w) = wrapped.as_mut() {
            *w = was_wrapped as u8;
        }
        cols
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_title(t: *mut WtTerminal, buf: *mut u8, cap: usize) -> usize {
    guard(|| {
        let Some(t) = term_mut(t) else { return 0 };
        let title = t.term.get_title();
        let bytes = title.as_bytes();
        if !buf.is_null() && cap > 0 {
            // never cut a UTF-8 sequence in half
            let mut n = bytes.len().min(cap);
            while n > 0 && n < bytes.len() && (bytes[n] & 0xC0) == 0x80 {
                n -= 1;
            }
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf, n);
        }
        bytes.len()
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_take_bells(t: *mut WtTerminal) -> u32 {
    guard(|| {
        term_mut(t)
            .map(|t| t.bells.swap(0, Ordering::Relaxed))
            .unwrap_or(0)
    })
}

// ---------------------------------------------------------------------------
// Input

fn mods_from(m: u32) -> KeyModifiers {
    let mut mods = KeyModifiers::NONE;
    if m & WT_MOD_SHIFT != 0 {
        mods |= KeyModifiers::SHIFT;
    }
    if m & WT_MOD_ALT != 0 {
        mods |= KeyModifiers::ALT;
    }
    if m & WT_MOD_CTRL != 0 {
        mods |= KeyModifiers::CTRL;
    }
    if m & WT_MOD_SUPER != 0 {
        mods |= KeyModifiers::SUPER;
    }
    mods
}

fn special_key(v: u32) -> Option<KeyCode> {
    Some(match v {
        1 => KeyCode::Backspace,
        2 => KeyCode::Tab,
        3 => KeyCode::Enter,
        4 => KeyCode::Escape,
        5 => KeyCode::Insert,
        6 => KeyCode::Delete,
        7 => KeyCode::Home,
        8 => KeyCode::End,
        9 => KeyCode::PageUp,
        10 => KeyCode::PageDown,
        11 => KeyCode::LeftArrow,
        12 => KeyCode::RightArrow,
        13 => KeyCode::UpArrow,
        14 => KeyCode::DownArrow,
        100..=123 => KeyCode::Function((v - 99) as u8),
        _ => return None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_key(t: *mut WtTerminal, kind: u8, value: u32, mods: u32) {
    guard(|| {
        let Some(t) = term_mut(t) else { return };
        let key = if kind == 0 {
            match char::from_u32(value) {
                Some(c) => KeyCode::Char(c),
                None => return,
            }
        } else {
            match special_key(value) {
                Some(k) => k,
                None => return,
            }
        };
        let _ = t.term.key_down(key, mods_from(mods));
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_paste(t: *mut WtTerminal, utf8: *const u8, len: usize) {
    guard(|| {
        let Some(t) = term_mut(t) else { return };
        if utf8.is_null() {
            return;
        }
        let bytes = std::slice::from_raw_parts(utf8, len);
        let text = String::from_utf8_lossy(bytes);
        let _ = t.term.send_paste(&text);
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_mouse(
    t: *mut WtTerminal,
    kind: u8,
    button: u8,
    x: i64,
    y: i64,
    mods: u32,
) {
    guard(|| {
        let Some(t) = term_mut(t) else { return };
        if x < 0 || y < 0 {
            return;
        }
        let kind = match kind {
            0 => MouseEventKind::Press,
            1 => MouseEventKind::Move,
            _ => MouseEventKind::Release,
        };
        let button = match button {
            0 => MouseButton::Left,
            1 => MouseButton::Middle,
            2 => MouseButton::Right,
            3 => MouseButton::WheelUp(1),
            4 => MouseButton::WheelDown(1),
            _ => MouseButton::None,
        };
        let _ = t.term.mouse_event(MouseEvent {
            kind,
            x: x as usize,
            y,
            x_pixel_offset: 0,
            y_pixel_offset: 0,
            button,
            modifiers: mods_from(mods),
        });
    })
}

#[no_mangle]
pub unsafe extern "C" fn wt_focus(t: *mut WtTerminal, focused: u8) {
    guard(|| {
        if let Some(t) = term_mut(t) {
            t.term.focus_changed(focused != 0);
        }
    })
}
