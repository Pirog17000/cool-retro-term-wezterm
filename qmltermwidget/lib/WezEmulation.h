/*
    WezEmulation - terminal emulation backed by the wezterm-term core.

    Copyright 2026 cool-retro-term-wezterm contributors

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    The escape-sequence parsing, terminal state machine, key/mouse encoding
    and query responses are all done by wezterm-term (Rust, via wezbridge).
    Konsole's Screen objects are kept only as the display model: after every
    burst of output the visible rows, cursor and scrollback of the wezterm
    model are mirrored into them, so TerminalDisplay, selection, copy and
    the scrollbar keep working unchanged.
*/

#ifndef WEZEMULATION_H
#define WEZEMULATION_H

#include <QVector>
#include <QString>

#include "Emulation.h"
#include "Character.h"

struct WtTerminal;
struct WtCell;

namespace Konsole
{

class WezEmulation : public Emulation
{
    Q_OBJECT

public:
    WezEmulation();
    ~WezEmulation() override;

    void clearEntireScreen() override;
    void reset() override;
    char eraseChar() const override;

    /** true when the wezterm core could be created (wezbridge.dll present) */
    bool isValid() const { return _term != nullptr; }

public slots:
    void setImageSize(int lines, int columns) override;
    void sendText(const QString& text) override;
    void sendKeyEvent(QKeyEvent*, bool fromPaste) override;
    void sendMouseEvent(int buttons, int column, int line, int eventType) override;
    void sendString(const char* string, int length = -1) override;
    void receiveData(const char* buffer, int len) override;

protected:
    void setMode(int mode) override;
    void resetMode(int mode) override;
    void prepareBulkUpdate() override;

private:
    void flushOutput();
    void syncFromModel();
    void syncScrollbackLimit();
    QVector<Character> readLine(qint64 phys, bool* wrapped);
    Character convertCell(const WtCell& cell) const;

    WtTerminal* _term = nullptr;
    QVector<WtCell>* _cellBuf = nullptr;

    qint64 _histNextStable = 0;     // first stable row not yet copied into Konsole history
    qint64 _lastScrollbackCount = 0;
    bool _needHistoryRebuild = false;
    int _scrollbackLimit = -1;

    QString _lastTitle;
    int _lastCursorShape = -1;
    int _lastMouseGrabbed = -1;
};

}

#endif // WEZEMULATION_H
