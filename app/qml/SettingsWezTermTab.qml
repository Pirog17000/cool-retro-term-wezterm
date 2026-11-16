/*******************************************************************************
* WezTerm core settings for cool-retro-term.
*
* This file is part of cool-retro-term.
*
* cool-retro-term is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*******************************************************************************/

import QtQuick 2.2
import QtQuick.Controls 2.0
import QtQuick.Layouts 1.1
import QMLTermWidget 2.0

ScrollView {
    id: root
    clip: true
    contentWidth: availableWidth

    ColumnLayout {
        width: root.availableWidth
        spacing: 8

        GroupBox {
            Layout.fillWidth: true
            title: qsTr("Engine (new tabs and windows)")
            padding: appSettings.defaultMargin

            ColumnLayout {
                anchors.fill: parent
                CheckBox {
                    text: qsTr("Use the WezTerm emulation core (off = legacy Konsole emulation)")
                    checked: WezTermConfig.useWeztermCore
                    onToggled: WezTermConfig.useWeztermCore = checked
                }
                CheckBox {
                    text: qsTr("Use bundled ConPTY host (conpty.dll + OpenConsole.exe)")
                    enabled: WezTermConfig.sideloadedConptyAvailable
                    checked: WezTermConfig.sideloadConpty
                    onToggled: WezTermConfig.sideloadConpty = checked
                }
                CheckBox {
                    text: qsTr("ConPTY passthrough mode (experimental)")
                    enabled: WezTermConfig.sideloadConpty && WezTermConfig.sideloadedConptyAvailable
                    checked: WezTermConfig.conptyPassthrough
                    onToggled: WezTermConfig.conptyPassthrough = checked
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: qsTr("Scrollback")
            padding: appSettings.defaultMargin

            RowLayout {
                anchors.fill: parent
                Label { text: qsTr("Scrollback lines") }
                SpinBox {
                    from: 0
                    to: 100000
                    stepSize: 1000
                    editable: true
                    value: WezTermConfig.scrollbackLines
                    onValueModified: WezTermConfig.scrollbackLines = value
                }
                Item { Layout.fillWidth: true }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: qsTr("Keyboard")
            padding: appSettings.defaultMargin

            ColumnLayout {
                anchors.fill: parent
                CheckBox {
                    text: qsTr("CSI-u key encoding (enable_csi_u_key_encoding)")
                    checked: WezTermConfig.csiUKeys
                    onToggled: WezTermConfig.csiUKeys = checked
                }
                CheckBox {
                    text: qsTr("Kitty keyboard protocol (enable_kitty_keyboard)")
                    checked: WezTermConfig.kittyKeyboard
                    onToggled: WezTermConfig.kittyKeyboard = checked
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: qsTr("Text")
            padding: appSettings.defaultMargin

            GridLayout {
                anchors.fill: parent
                columns: 2

                Label { text: qsTr("Unicode version (new tabs)") }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["9", "10", "11", "12", "13", "14", "15", "16"]
                    currentIndex: Math.max(0, WezTermConfig.unicodeVersion - 9)
                    onActivated: (index) => WezTermConfig.unicodeVersion = index + 9
                }

                CheckBox {
                    Layout.columnSpan: 2
                    text: qsTr("Treat ambiguous-width characters as wide (new tabs)")
                    checked: WezTermConfig.ambiguousWide
                    onToggled: WezTermConfig.ambiguousWide = checked
                }
                CheckBox {
                    Layout.columnSpan: 2
                    text: qsTr("Normalize output to Unicode NFC")
                    checked: WezTermConfig.normalizeNfc
                    onToggled: WezTermConfig.normalizeNfc = checked
                }

                CheckBox {
                    id: bidiCheck
                    text: qsTr("Bidirectional text (BiDi)")
                    checked: WezTermConfig.bidiEnabled
                    onToggled: WezTermConfig.bidiEnabled = checked
                }
                ComboBox {
                    Layout.fillWidth: true
                    enabled: bidiCheck.checked
                    model: [qsTr("Left to right"), qsTr("Right to left"),
                            qsTr("Auto, fallback LTR"), qsTr("Auto, fallback RTL")]
                    currentIndex: WezTermConfig.bidiHint
                    onActivated: (index) => WezTermConfig.bidiHint = index
                }
            }
        }

        GroupBox {
            Layout.fillWidth: true
            title: qsTr("Paste & terminal responses")
            padding: appSettings.defaultMargin

            GridLayout {
                anchors.fill: parent
                columns: 2

                Label { text: qsTr("Pasted newlines (without bracketed paste)") }
                ComboBox {
                    Layout.fillWidth: true
                    model: [qsTr("Default (CRLF)"), qsTr("Keep as is"), qsTr("LF"), qsTr("CR"), qsTr("CRLF")]
                    currentIndex: WezTermConfig.pasteNewlines
                    onActivated: (index) => WezTermConfig.pasteNewlines = index
                }

                CheckBox {
                    Layout.columnSpan: 2
                    text: qsTr("Allow title reporting (CSI 21 t)")
                    checked: WezTermConfig.titleReporting
                    onToggled: WezTermConfig.titleReporting = checked
                }

                Label { text: qsTr("ENQ answerback") }
                TextField {
                    Layout.fillWidth: true
                    text: WezTermConfig.answerback
                    maximumLength: 63
                    onEditingFinished: WezTermConfig.answerback = text
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: qsTr("Engine options apply to newly opened tabs; the rest apply immediately.")
            }
            Button {
                text: qsTr("Reset to defaults")
                onClicked: WezTermConfig.resetToDefaults()
            }
        }
    }
}
