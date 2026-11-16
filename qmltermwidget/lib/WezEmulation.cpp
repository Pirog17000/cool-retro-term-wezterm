/*
    WezEmulation - terminal emulation backed by the wezterm-term core.

    Copyright 2026 cool-retro-term-wezterm contributors

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
*/

#include "WezEmulation.h"

#include <QDebug>
#include <QKeyEvent>

#include "History.h"
#include "KeyboardTranslator.h"
#include "Screen.h"

#include "wezbridge.h"

using namespace Konsole;

namespace
{
constexpr int kUnlimitedScrollback = 100000;

int specialKeyFor(int qtKey)
{
    switch (qtKey) {
    case Qt::Key_Backspace: return WT_KEY_BACKSPACE;
    case Qt::Key_Tab:
    case Qt::Key_Backtab:   return WT_KEY_TAB;
    case Qt::Key_Return:
    case Qt::Key_Enter:     return WT_KEY_ENTER;
    case Qt::Key_Escape:    return WT_KEY_ESCAPE;
    case Qt::Key_Insert:    return WT_KEY_INSERT;
    case Qt::Key_Delete:    return WT_KEY_DELETE;
    case Qt::Key_Home:      return WT_KEY_HOME;
    case Qt::Key_End:       return WT_KEY_END;
    case Qt::Key_PageUp:    return WT_KEY_PAGEUP;
    case Qt::Key_PageDown:  return WT_KEY_PAGEDOWN;
    case Qt::Key_Left:      return WT_KEY_LEFT;
    case Qt::Key_Right:     return WT_KEY_RIGHT;
    case Qt::Key_Up:        return WT_KEY_UP;
    case Qt::Key_Down:      return WT_KEY_DOWN;
    default: break;
    }
    if (qtKey >= Qt::Key_F1 && qtKey <= Qt::Key_F24)
        return WT_KEY_F1 + (qtKey - Qt::Key_F1);
    return 0;
}

uint32_t modsFor(Qt::KeyboardModifiers m)
{
    uint32_t mods = 0;
    if (m & Qt::ShiftModifier)   mods |= WT_MOD_SHIFT;
    if (m & Qt::AltModifier)     mods |= WT_MOD_ALT;
    if (m & Qt::ControlModifier) mods |= WT_MOD_CTRL;
    return mods;
}

// Base (unshifted, layout independent) character for Ctrl+<key> chords, so
// that Ctrl+C works the same with a Russian or any other keyboard layout.
uint32_t ctrlBaseChar(const QKeyEvent* ev)
{
#ifdef Q_OS_WIN
    const quint32 vk = ev->nativeVirtualKey();
    if (vk >= 'A' && vk <= 'Z') return vk - 'A' + 'a';
    if (vk >= '0' && vk <= '9') return vk;
    switch (vk) {
    case 0x20: return ' ';
    case 0xBA: return ';';  // VK_OEM_1
    case 0xBB: return '=';  // VK_OEM_PLUS
    case 0xBC: return ',';  // VK_OEM_COMMA
    case 0xBD: return '-';  // VK_OEM_MINUS
    case 0xBE: return '.';  // VK_OEM_PERIOD
    case 0xBF: return '/';  // VK_OEM_2
    case 0xC0: return '`';  // VK_OEM_3
    case 0xDB: return '[';  // VK_OEM_4
    case 0xDC: return '\\'; // VK_OEM_5
    case 0xDD: return ']';  // VK_OEM_6
    case 0xDE: return '\''; // VK_OEM_7
    default: break;
    }
#endif
    const int key = ev->key();
    if (key >= 0x20 && key < 0x7f) {
        if (key >= 'A' && key <= 'Z')
            return key - 'A' + 'a';
        return static_cast<uint32_t>(key);
    }
    return 0;
}

Emulation::KeyboardCursorShape cursorShapeFor(int wtShape, bool* blinking)
{
    *blinking = (wtShape == WT_CURSOR_BLINK_BLOCK || wtShape == WT_CURSOR_BLINK_UNDER
                 || wtShape == WT_CURSOR_BLINK_BAR);
    switch (wtShape) {
    case WT_CURSOR_BLINK_UNDER:
    case WT_CURSOR_STEADY_UNDER:
        return Emulation::KeyboardCursorShape::UnderlineCursor;
    case WT_CURSOR_BLINK_BAR:
    case WT_CURSOR_STEADY_BAR:
        return Emulation::KeyboardCursorShape::IBeamCursor;
    default:
        return Emulation::KeyboardCursorShape::BlockCursor;
    }
}

CharacterColor colorFor(uint8_t kind, uint32_t value, bool foreground)
{
    switch (kind) {
    case WT_COLOR_PALETTE:
        if (value < 16)
            return CharacterColor(COLOR_SPACE_SYSTEM, static_cast<int>(value));
        return CharacterColor(COLOR_SPACE_256, static_cast<int>(value));
    case WT_COLOR_RGB:
        return CharacterColor(COLOR_SPACE_RGB, static_cast<int>(value & 0xFFFFFF));
    default:
        return CharacterColor(COLOR_SPACE_DEFAULT, foreground ? DEFAULT_FORE_COLOR : DEFAULT_BACK_COLOR);
    }
}
} // namespace

WezEmulation::WezEmulation()
{
    const int lines = _screen[0]->getLines();
    const int columns = _screen[0]->getColumns();
#ifdef Q_OS_WIN
    const uint8_t conptyQuirks = 1;
#else
    const uint8_t conptyQuirks = 0;
#endif
    _term = wt_new(lines, columns, 10000, conptyQuirks);
    _scrollbackLimit = 10000;
    _cellBuf = new QVector<WtCell>(columns);
    if (!_term)
        qWarning() << "WezEmulation: failed to create wezterm terminal model";
}

WezEmulation::~WezEmulation()
{
    if (_term)
        wt_free(_term);
    delete _cellBuf;
}

void WezEmulation::flushOutput()
{
    if (!_term)
        return;
    char buf[4096];
    for (;;) {
        const size_t n = wt_take_output(_term, reinterpret_cast<uint8_t*>(buf), sizeof(buf));
        if (n == 0)
            break;
        emit sendData(buf, static_cast<int>(n));
    }
}

void WezEmulation::receiveData(const char* buffer, int len)
{
    if (!_term || len <= 0)
        return;

    emit stateSet(NOTIFYACTIVITY);

    wt_advance(_term, reinterpret_cast<const uint8_t*>(buffer), static_cast<size_t>(len));

    // Answers to DSR/DA/etc. must reach ConPTY immediately (it blocks on the
    // cursor position report at startup).
    flushOutput();

    if (wt_take_bells(_term) > 0)
        emit stateSet(NOTIFYBELL);

    bufferedUpdate();
}

void WezEmulation::setImageSize(int lines, int columns)
{
    if (lines < 1 || columns < 1)
        return;

    Emulation::setImageSize(lines, columns);

    if (_term) {
        wt_resize(_term, lines, columns, 0, 0);
        flushOutput();
    }
    // wezterm re-wraps the scrollback on resize; rebuild Konsole's mirror.
    _needHistoryRebuild = true;
    syncFromModel();
    bufferedUpdate();
}

void WezEmulation::prepareBulkUpdate()
{
    syncFromModel();
}

void WezEmulation::syncScrollbackLimit()
{
    const HistoryType& type = _screen[0]->getScroll();
    int limit = 0;
    if (type.isEnabled()) {
        limit = type.maximumLineCount();
        if (limit <= 0)
            limit = kUnlimitedScrollback;
    }
    if (limit != _scrollbackLimit) {
        _scrollbackLimit = limit;
        wt_set_scrollback(_term, static_cast<uint32_t>(limit));
    }
}

Character WezEmulation::convertCell(const WtCell& c) const
{
    Character ch;
    ch.rendition = DEFAULT_RENDITION;

    CharacterColor fg = colorFor(c.fg_kind, c.fg, true);
    CharacterColor bg = colorFor(c.bg_kind, c.bg, false);

    if (c.flags & WT_ATTR_REVERSE)
        std::swap(fg, bg);
    if (c.flags & WT_ATTR_BOLD) {
        ch.rendition |= RE_BOLD;
        fg.setIntensive();
    }
    if (c.flags & WT_ATTR_FAINT)     ch.rendition |= RE_FAINT;
    if (c.flags & WT_ATTR_ITALIC)    ch.rendition |= RE_ITALIC;
    if (c.flags & WT_ATTR_UNDERLINE) ch.rendition |= RE_UNDERLINE;
    if (c.flags & WT_ATTR_BLINK)     ch.rendition |= RE_BLINK;
    if (c.flags & WT_ATTR_INVISIBLE) fg = bg;

    ch.foregroundColor = fg;
    ch.backgroundColor = bg;

    if (c.ncp == 0) {
        // right half of a double-width glyph
        ch.character = 0;
        return ch;
    }

    // Convert the grapheme to UTF-16 code units: on Windows wchar_t is 16 bit,
    // so astral characters (emoji, etc.) are stored as surrogate pairs in the
    // extended character table, which TerminalDisplay copies verbatim.
    uint units[WT_CELL_MAX_CP * 2];
    ushort n = 0;
    for (int i = 0; i < c.ncp && i < WT_CELL_MAX_CP; ++i) {
        const char32_t cp = c.cp[i];
        if (cp > 0xFFFF) {
            units[n++] = QChar::highSurrogate(cp);
            units[n++] = QChar::lowSurrogate(cp);
        } else {
            units[n++] = cp;
        }
    }

    if (n == 1) {
        ch.character = static_cast<wchar_t>(units[0]);
    } else {
        const uint hash = ExtendedCharTable::instance.createExtendedChar(units, n);
        if (hash) {
            ch.character = static_cast<wchar_t>(hash);
            ch.rendition |= RE_EXTENDED_CHAR;
        } else {
            ch.character = static_cast<wchar_t>(units[0]);
        }
    }
    return ch;
}

QVector<Character> WezEmulation::readLine(qint64 phys, bool* wrapped)
{
    const int columns = _currentScreen->getColumns();
    if (_cellBuf->size() < columns)
        _cellBuf->resize(columns);

    uint8_t w = 0;
    const size_t n = wt_line(_term, phys, _cellBuf->data(), static_cast<size_t>(_cellBuf->size()), &w);
    *wrapped = (w != 0);

    QVector<Character> line(columns);
    const WtCell* cells = _cellBuf->constData();
    const int count = qMin<int>(static_cast<int>(n), columns);
    for (int i = 0; i < count; ++i)
        line[i] = convertCell(cells[i]);
    return line;
}

void WezEmulation::syncFromModel()
{
    if (!_term)
        return;

    syncScrollbackLimit();

    WtInfo info;
    wt_info(_term, &info);

    const bool alt = info.alt_screen != 0;
    setScreen(alt ? 1 : 0);
    Screen* screen = _currentScreen;

    // --- scrollback (primary screen only) --------------------------------
    if (!alt) {
        const qint64 scrollbackCount = info.first_visible_stable - info.top_stable;
        const bool rebuild = _needHistoryRebuild
                             || scrollbackCount < _lastScrollbackCount
                             || info.first_visible_stable < _histNextStable;
        qint64 from;
        if (rebuild) {
            _screen[0]->clearExternalHistory();
            from = info.top_stable;
        } else {
            from = qMax(_histNextStable, info.top_stable);
        }
        // The column count of the history lines must follow the current width.
        for (qint64 s = from; s < info.first_visible_stable; ++s) {
            bool wrapped = false;
            const QVector<Character> line = readLine(s - info.top_stable, &wrapped);
            _screen[0]->addExternalHistoryLine(line, wrapped);
        }
        _histNextStable = info.first_visible_stable;
        _lastScrollbackCount = scrollbackCount;
        _needHistoryRebuild = false;
    }

    // --- visible rows ----------------------------------------------------
    const int rows = qMin<int>(static_cast<int>(info.rows), screen->getLines());
    const qint64 firstVisiblePhys = info.total_lines - info.rows;
    for (int y = 0; y < rows; ++y) {
        bool wrapped = false;
        const QVector<Character> line = readLine(firstVisiblePhys + y, &wrapped);
        screen->setExternalLine(y, line, wrapped);
    }

    // --- cursor / modes --------------------------------------------------
    screen->setExternalCursor(static_cast<int>(info.cursor_x), static_cast<int>(info.cursor_y));
    if (info.cursor_visible)
        screen->setMode(MODE_Cursor);
    else
        screen->resetMode(MODE_Cursor);
    if (info.reverse_video)
        screen->setMode(MODE_Screen);
    else
        screen->resetMode(MODE_Screen);

    if (info.cursor_shape != _lastCursorShape) {
        _lastCursorShape = info.cursor_shape;
        if (info.cursor_shape != WT_CURSOR_DEFAULT) {
            bool blinking = false;
            const auto shape = cursorShapeFor(info.cursor_shape, &blinking);
            emit cursorChanged(shape, blinking);
        }
    }

    // TerminalDisplay::setUsesMouse(true) means "mouse is used for selection",
    // i.e. the program has NOT grabbed the mouse.
    const int grabbed = info.mouse_grabbed ? 1 : 0;
    if (grabbed != _lastMouseGrabbed) {
        _lastMouseGrabbed = grabbed;
        emit programUsesMouseChanged(!grabbed);
    }

    // --- title -----------------------------------------------------------
    char titleBuf[1024];
    const size_t titleLen = wt_title(_term, reinterpret_cast<uint8_t*>(titleBuf), sizeof(titleBuf));
    const QString title = QString::fromUtf8(titleBuf, static_cast<int>(qMin(titleLen, sizeof(titleBuf))));
    if (title != _lastTitle) {
        _lastTitle = title;
        emit titleChanged(0, title);
    }
}

void WezEmulation::sendKeyEvent(QKeyEvent* ev, bool fromPaste)
{
    if (!_term)
        return;

    emit stateSet(NOTIFYNORMAL);

    if (fromPaste) {
        // TerminalDisplay already converted newlines to CR; wezterm adds the
        // bracketed paste markers when the application asked for them.
        const QByteArray utf8 = ev->text().toUtf8();
        wt_paste(_term, reinterpret_cast<const uint8_t*>(utf8.constData()), static_cast<size_t>(utf8.size()));
        flushOutput();
        emit outputFromKeypressEvent();
        return;
    }

    const Qt::KeyboardModifiers qmods = ev->modifiers();
    const int key = ev->key();
    uint32_t mods = modsFor(qmods);

    // Scrollback navigation (matches Konsole's default keytab) while the
    // primary screen is active.
    if ((qmods & Qt::ShiftModifier) && !(qmods & (Qt::ControlModifier | Qt::AltModifier))
        && _currentScreen == _screen[0]) {
        if (key == Qt::Key_PageUp) {
            emit handleCommandFromKeyboard(KeyboardTranslator::ScrollPageUpCommand);
            return;
        }
        if (key == Qt::Key_PageDown) {
            emit handleCommandFromKeyboard(KeyboardTranslator::ScrollPageDownCommand);
            return;
        }
    }

    const QString text = ev->text();
    const bool ctrl = qmods & Qt::ControlModifier;
    const bool alt = qmods & Qt::AltModifier;
    // AltGr on Windows arrives as Ctrl+Alt with the composed character as text.
    const bool altGrText = ctrl && alt && !text.isEmpty() && text.at(0).unicode() >= 0x20;

    if (const int special = specialKeyFor(key)) {
        if (key == Qt::Key_Backtab)
            mods |= WT_MOD_SHIFT;
        wt_key(_term, WT_KEYKIND_SPECIAL, static_cast<uint32_t>(special), mods);
    } else if (ctrl && !altGrText) {
        const uint32_t base = ctrlBaseChar(ev);
        if (base) {
            wt_key(_term, WT_KEYKIND_CHAR, base, mods);
        } else if (!text.isEmpty()) {
            const QByteArray utf8 = text.toUtf8();
            emit sendData(utf8.constData(), utf8.size());
        } else {
            return; // bare modifier press
        }
    } else if (!text.isEmpty()) {
        // Shift is already applied to the text; AltGr compositions are plain text.
        uint32_t textMods = mods & ~WT_MOD_SHIFT;
        if (altGrText)
            textMods &= ~(WT_MOD_CTRL | WT_MOD_ALT);
        const QList<uint> cps = text.toUcs4();
        for (uint cp : cps)
            wt_key(_term, WT_KEYKIND_CHAR, cp, textMods);
    } else {
        return; // modifier-only or unmapped key
    }

    flushOutput();
    emit outputFromKeypressEvent();
}

void WezEmulation::sendMouseEvent(int cb, int cx, int cy, int eventType)
{
    if (!_term || cx < 1 || cy < 1)
        return;

    uint8_t button;
    switch (cb) {
    case 0: button = WT_BUTTON_LEFT; break;
    case 1: button = WT_BUTTON_MIDDLE; break;
    case 2: button = WT_BUTTON_RIGHT; break;
    case 4: button = WT_BUTTON_WHEEL_UP; break;
    case 5: button = WT_BUTTON_WHEEL_DOWN; break;
    default: button = WT_BUTTON_NONE; break;
    }

    uint8_t kind = WT_MOUSE_PRESS;
    if (button == WT_BUTTON_WHEEL_UP || button == WT_BUTTON_WHEEL_DOWN)
        kind = WT_MOUSE_PRESS;
    else if (eventType == 1)
        kind = WT_MOUSE_MOVE;
    else if (eventType == 2)
        kind = WT_MOUSE_RELEASE;

    wt_mouse(_term, kind, button, cx - 1, cy - 1, 0);
    flushOutput();
}

void WezEmulation::sendText(const QString& text)
{
    if (text.isEmpty())
        return;
    const QByteArray utf8 = text.toUtf8();
    emit sendData(utf8.constData(), utf8.size());
}

void WezEmulation::sendString(const char* string, int length)
{
    if (!string)
        return;
    if (length < 0)
        length = static_cast<int>(qstrlen(string));
    if (length > 0)
        emit sendData(string, length);
}

void WezEmulation::clearEntireScreen()
{
    static const char seq[] = "\x1b[2J\x1b[H";
    if (_term)
        wt_advance(_term, reinterpret_cast<const uint8_t*>(seq), sizeof(seq) - 1);
    bufferedUpdate();
}

void WezEmulation::reset()
{
    static const char seq[] = "\x1b" "c";
    if (_term)
        wt_advance(_term, reinterpret_cast<const uint8_t*>(seq), sizeof(seq) - 1);
    _needHistoryRebuild = true;
    bufferedUpdate();
}

char WezEmulation::eraseChar() const
{
    return '\x7f';
}

// Konsole-level modes are owned by the wezterm model; nothing to do here.
void WezEmulation::setMode(int) {}
void WezEmulation::resetMode(int) {}
