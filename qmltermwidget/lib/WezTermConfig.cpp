/*
    WezTermConfig - process wide settings for the wezterm-term core.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
*/

#include "WezTermConfig.h"

#include <QCoreApplication>
#include <QFileInfo>

#include <cstring>

#include "wezbridge.h"

using namespace Konsole;

WezTermConfig::WezTermConfig(QObject* parent)
    : QObject(parent)
{
}

WezTermConfig* WezTermConfig::instance()
{
    static WezTermConfig* s_instance = new WezTermConfig();
    return s_instance;
}

void WezTermConfig::toWtConfig(WtConfig* out) const
{
    wt_default_config(out);
    out->scrollback = static_cast<uint32_t>(qMax(0, m_scrollbackLines));
    out->csi_u_keys = m_csiUKeys;
    out->kitty_keyboard = m_kittyKeyboard;
    out->unicode_version = static_cast<uint8_t>(qBound(9, m_unicodeVersion, 16));
    out->ambiguous_wide = m_ambiguousWide;
    out->paste_newlines = static_cast<uint8_t>(qBound(0, m_pasteNewlines, 4));
    out->normalize_nfc = m_normalizeNfc;
    out->bidi_enabled = m_bidiEnabled;
    out->bidi_hint = static_cast<uint8_t>(qBound(0, m_bidiHint, 3));
    out->title_reporting = m_titleReporting;

    const QByteArray ab = m_answerback.toUtf8().left(sizeof(out->answerback) - 1);
    std::memset(out->answerback, 0, sizeof(out->answerback));
    std::memcpy(out->answerback, ab.constData(), static_cast<size_t>(ab.size()));
}

bool WezTermConfig::sideloadedConptyAvailable() const
{
#ifdef Q_OS_WIN
    const QString dir = QCoreApplication::applicationDirPath();
    return QFileInfo::exists(dir + QStringLiteral("/conpty.dll"))
        && QFileInfo::exists(dir + QStringLiteral("/OpenConsole.exe"));
#else
    return false;
#endif
}

void WezTermConfig::resetToDefaults()
{
    QSignalBlocker blocker(this);
    setUseWeztermCore(true);
    setSideloadConpty(true);
    setConptyPassthrough(false);
    setScrollbackLines(10000);
    setCsiUKeys(false);
    setKittyKeyboard(false);
    setUnicodeVersion(9);
    setAmbiguousWide(false);
    setPasteNewlines(0);
    setNormalizeNfc(false);
    setBidiEnabled(false);
    setBidiHint(0);
    setTitleReporting(false);
    setAnswerback(QString());
    blocker.unblock();
    emit configChanged();
}
