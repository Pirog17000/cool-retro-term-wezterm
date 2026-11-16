/*
    WezTermConfig - process wide settings for the wezterm-term emulation core
    and the ConPTY host.  Exposed to QML as the `WezTermConfig` singleton of
    the QMLTermWidget module; every live WezEmulation follows changes.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
*/

#ifndef WEZTERMCONFIG_H
#define WEZTERMCONFIG_H

#include <QObject>
#include <QString>

struct WtConfig;

namespace Konsole
{

#define WEZ_CONFIG_PROPERTY(Type, name, Setter, defaultValue)                  \
    Q_PROPERTY(Type name READ name WRITE Setter NOTIFY configChanged)          \
public:                                                                         \
    Type name() const { return m_##name; }                                      \
    void Setter(const Type& v)                                                  \
    {                                                                           \
        if (m_##name == v)                                                      \
            return;                                                             \
        m_##name = v;                                                           \
        emit configChanged();                                                   \
    }                                                                           \
private:                                                                        \
    Type m_##name = defaultValue;

class WezTermConfig : public QObject
{
    Q_OBJECT

    // Emulation core / pty host (take effect for new tabs and windows)
    WEZ_CONFIG_PROPERTY(bool, useWeztermCore, setUseWeztermCore, true)
    WEZ_CONFIG_PROPERTY(bool, sideloadConpty, setSideloadConpty, true)
    WEZ_CONFIG_PROPERTY(bool, conptyPassthrough, setConptyPassthrough, false)

    // wezterm-term settings (applied live)
    WEZ_CONFIG_PROPERTY(int, scrollbackLines, setScrollbackLines, 10000)
    WEZ_CONFIG_PROPERTY(bool, csiUKeys, setCsiUKeys, false)
    WEZ_CONFIG_PROPERTY(bool, kittyKeyboard, setKittyKeyboard, false)
    WEZ_CONFIG_PROPERTY(int, unicodeVersion, setUnicodeVersion, 9)
    WEZ_CONFIG_PROPERTY(bool, ambiguousWide, setAmbiguousWide, false)
    WEZ_CONFIG_PROPERTY(int, pasteNewlines, setPasteNewlines, 0)
    WEZ_CONFIG_PROPERTY(bool, normalizeNfc, setNormalizeNfc, false)
    WEZ_CONFIG_PROPERTY(bool, bidiEnabled, setBidiEnabled, false)
    WEZ_CONFIG_PROPERTY(int, bidiHint, setBidiHint, 0)
    WEZ_CONFIG_PROPERTY(bool, titleReporting, setTitleReporting, false)
    WEZ_CONFIG_PROPERTY(QString, answerback, setAnswerback, QString())

    Q_PROPERTY(bool sideloadedConptyAvailable READ sideloadedConptyAvailable CONSTANT)

public:
    static WezTermConfig* instance();

    /** Fills a wezbridge WtConfig from the current values. */
    void toWtConfig(WtConfig* out) const;

    bool sideloadedConptyAvailable() const;

    /** Restores every setting to its default. */
    Q_INVOKABLE void resetToDefaults();

signals:
    void configChanged();

private:
    explicit WezTermConfig(QObject* parent = nullptr);
};

#undef WEZ_CONFIG_PROPERTY

}

#endif // WEZTERMCONFIG_H
