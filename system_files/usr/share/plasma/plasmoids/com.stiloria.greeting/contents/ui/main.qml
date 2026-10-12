/*
    Stiloria Greeting: the greeting at the top left of Stiloria's desktop, in
    the Porcelain design. The date and time as an overline, "Good evening,"
    and the user's first name, in italics, in Instrument Serif, and how to
    talk to Achilles. Ink when the color scheme is light (day), ivory when it
    is dark (night), with a soft glow or shadow so it reads over the wallpaper.

    The layout is the design's (porcelain.html) at 1x; the widget scales
    it to fit its size. It wakes once a minute, on the minute, for the clock,
    and its shadow is rendered again only when the text changes.
*/
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

import org.kde.coreaddons as KCoreAddons
import org.kde.kirigami as Kirigami
import org.kde.plasma.clock as PlasmaClock
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid

import "../code/name.js" as Name

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    // Day or night, from the color scheme's window background: Plasma swaps
    // the scheme when it switches between its light and dark themes, and the
    // text follows right away.
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark

    // Porcelain's colors: ink for the text (the date at 78%, the hint at 85%),
    // and for the keys a surface fill with a hairline edge.
    readonly property color ink: dark ? "#f2eee8" : "#1d1b18"
    readonly property color dateInk: Qt.alpha(ink, 0.78)
    readonly property color hintInk: Qt.alpha(ink, 0.85)
    readonly property color keyFill: dark ? "#1c1a17" : "#fbfaf7"
    readonly property color keyEdge: dark ? "#2a2824" : "#e4dfd6"

    // Ticks on the minute, and follows changes to the clock and the time zone.
    PlasmaClock.Clock {
        id: clock
    }

    KCoreAddons.KUser {
        id: user
    }

    readonly property date now: clock.dateTime
    // An int, so the greeting is picked again only when the hour changes.
    readonly property int hour: now.getHours()

    readonly property var greetings: [
        i18nc("@title greeting before the user's name", "Good morning,"),
        i18nc("@title greeting before the user's name", "Good afternoon,"),
        i18nc("@title greeting before the user's name", "Good evening,"),
        i18nc("@title greeting before the user's name, late at night", "Good night,"),
    ]
    // Morning from 5:00, afternoon from 12:00, evening from 17:00, night from 22:00.
    readonly property string greeting: greetings[hour >= 22 || hour < 5 ? 3 : hour >= 17 ? 2 : hour >= 12 ? 1 : 0]

    readonly property string name: {
        const chosen = (Plasmoid.configuration.nameOverride || "").trim();
        const first = chosen || Name.firstName(user.fullName, user.loginName);
        // "Marcelino." but "Marcelino!" stays as it is.
        return /[.!?]$/.test(first) ? first : i18nc("@title the user's name, ending the greeting", "%1.", first);
    }

    readonly property string dateLine: dateLineFor(now)
    function dateLineFor(when: date): string {
        return i18nc("@label weekday · month and day · time, as in Sunday · October 11 · 8:42 PM", "%1 · %2 · %3",
            Qt.locale().dayName(when.getDay(), Locale.LongFormat),
            when.toLocaleDateString(Qt.locale(), i18nc("@label Qt date format: the full month name and the day, as in October 11", "MMMM d")),
            when.toLocaleTimeString(Qt.locale(), Locale.ShortFormat))
    }

    // The hint, split around its two keys: "Hold ", key, " + ", key, " to talk to Achilles."
    readonly property var keys: [i18nc("@info keyboard key", "Super"), "`"]
    readonly property var hintParts: i18nc("@info %1 and %2 are keys, drawn as keycaps", "Hold %1 + %2 to talk to Achilles.", "\u0001", "\u0002")
        .split(/([\u0001\u0002])/).filter(part => part !== "")

    component Label: Text {
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    fullRepresentation: Item {
        id: greeting

        // Margins around the text, at 1x. The desktop lays widgets out on a
        // grid of 16 px cells: at 304 px, 19 cells, the widget's natural
        // height shows the text at exactly the design's size, and a widget
        // placed at (96, 64) puts the text where the design has it, (110, 96).
        readonly property real padX: 14
        readonly property real padTop: 32
        readonly property real padBottom: 32
        // The widest line at 1x, whatever the hour and day: the longest
        // greeting, the name, or about the longest date (in English, a
        // Wednesday in September at 12:59).
        readonly property real textWidth: Math.max(nameMetrics.advanceWidth(root.name),
            ...root.greetings.map(text => greetingMetrics.advanceWidth(text)),
            dateMetrics.advanceWidth(root.dateLineFor(new Date(2026, 8, 30, 12, 59))))
        readonly property real naturalWidth: 2 * padX + textWidth
        readonly property real naturalHeight: padTop + 240 + padBottom
        readonly property real s: Math.max(0.1, Math.min(width / naturalWidth, height / naturalHeight))

        Layout.preferredWidth: naturalWidth
        Layout.preferredHeight: naturalHeight
        Layout.minimumWidth: naturalWidth / 4
        Layout.minimumHeight: naturalHeight / 4

        FontMetrics {
            id: dateMetrics
            font.family: "Instrument Sans"
            font.weight: Font.DemiBold
            font.pixelSize: 12
            font.letterSpacing: 0.18 * 12
            font.capitalization: Font.AllUppercase
        }

        FontMetrics {
            id: greetingMetrics
            font.family: "Instrument Serif"
            font.pixelSize: 72
            font.letterSpacing: -0.02 * 72
        }

        FontMetrics {
            id: nameMetrics
            font.family: "Instrument Serif"
            font.italic: true
            font.pixelSize: 104
            font.letterSpacing: -0.02 * 104
        }

        Item {
            id: content
            // Everything, whatever its size, so the layer that draws the
            // shadow never cuts off a long date.
            width: Math.max(greeting.width, childrenRect.x + childrenRect.width + greeting.padX * greeting.s)
            height: Math.max(greeting.height, childrenRect.y + childrenRect.height + greeting.padBottom * greeting.s)

            // The design's text shadow: an ivory glow by day, a soft dark
            // shadow at night. MultiEffect takes the color premultiplied and
            // blurs more tightly than CSS, so these values are matched to the
            // mock's rendering rather than copied from its CSS. Without a GPU
            // there is no shadow.
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: root.dark ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0.54, 0.539, 0.532, 0.55)
                shadowVerticalOffset: (root.dark ? 2 : 1) * greeting.s
                shadowHorizontalOffset: 0
                blurMax: Math.round((root.dark ? 40 : 36) * greeting.s)
                shadowBlur: 1
            }

            // The design's positions at 1x, from the top left of the text: the
            // baselines of each line and the keys. Boxes sit on
            // whole pixels, as a browser draws them, so their edges stay
            // sharp; text keeps its exact place.
            Item {
                id: layout
                x: Math.round(greeting.padX * greeting.s)
                y: Math.round(greeting.padTop * greeting.s)
                width: childrenRect.width
                height: childrenRect.height

                Label {
                    y: 11 * greeting.s - baselineOffset
                    text: root.dateLine
                    color: root.dateInk
                    font.family: "Instrument Sans"
                    font.weight: Font.DemiBold
                    font.pixelSize: Math.round(12 * greeting.s)
                    font.letterSpacing: 0.18 * 12 * greeting.s
                    font.capitalization: Font.AllUppercase
                }

                Label {
                    y: 86 * greeting.s - baselineOffset
                    text: root.greeting
                    color: root.ink
                    font.family: "Instrument Serif"
                    font.pixelSize: Math.round(72 * greeting.s)
                    font.letterSpacing: -0.02 * 72 * greeting.s
                }

                Label {
                    y: 183 * greeting.s - baselineOffset
                    text: root.name
                    color: root.ink
                    font.family: "Instrument Serif"
                    font.italic: true
                    font.pixelSize: Math.round(104 * greeting.s)
                    font.letterSpacing: -0.02 * 104 * greeting.s
                }

                Row {
                    id: hint
                    // The top of the keys, and the line's baseline below it.
                    readonly property real keyTop: Math.round(218 * greeting.s)
                    readonly property real textBaseline: 234.5 * greeting.s - keyTop

                    visible: Plasmoid.configuration.showHint
                    y: keyTop

                    Repeater {
                        model: root.hintParts

                        delegate: Item {
                            id: part
                            required property string modelData
                            readonly property int key: modelData === "\u0001" ? 0 : modelData === "\u0002" ? 1 : -1
                            readonly property real keyWidth: keyLabel.implicitWidth + 16 * greeting.s

                            width: key < 0 ? words.implicitWidth : keyWidth
                            height: keycap.height

                            Label {
                                id: words
                                visible: part.key < 0
                                y: hint.textBaseline - baselineOffset
                                text: part.key < 0 ? part.modelData : ""
                                color: root.hintInk
                                font.family: "Instrument Sans"
                                font.pixelSize: Math.round(15 * greeting.s)
                            }

                            Rectangle {
                                id: keycap
                                visible: part.key >= 0
                                x: Math.round(part.x) - part.x
                                width: Math.round(part.x + part.keyWidth) - Math.round(part.x)
                                height: Math.round(240 * greeting.s) - hint.keyTop
                                radius: 6 * greeting.s
                                color: root.keyFill

                                // The hairline edge, over the fill as in the design.
                                Rectangle {
                                    anchors.fill: parent
                                    radius: parent.radius
                                    color: "transparent"
                                    border.color: root.keyEdge
                                    border.width: 1
                                }

                                Label {
                                    id: keyLabel
                                    x: part.x - Math.round(part.x) + 8 * greeting.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: part.key >= 0 ? root.keys[part.key] : ""
                                    color: root.ink
                                    font.family: "Instrument Sans"
                                    font.weight: Font.Medium
                                    font.pixelSize: Math.round(11 * greeting.s)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
