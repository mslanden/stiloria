import QtQuick
import QtQuick.Controls as QQC2

import org.kde.coreaddons as KCoreAddons
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

import "../code/name.js" as Name

KCMUtils.SimpleKCM {
    property alias cfg_nameOverride: nameField.text
    property alias cfg_showHint: hintCheck.checked
    property string cfg_textColor
    // Plasma sets these too.
    property string cfg_nameOverrideDefault
    property bool cfg_showHintDefault
    property string cfg_textColorDefault

    KCoreAddons.KUser {
        id: user
    }

    Kirigami.FormLayout {
        QQC2.TextField {
            id: nameField
            Kirigami.FormData.label: i18nc("@label:textbox", "Name:")
            // Empty means the account's first name, which the placeholder shows.
            placeholderText: Name.firstName(user.fullName, user.loginName)
        }

        QQC2.CheckBox {
            id: hintCheck
            Kirigami.FormData.label: i18nc("@label", "Hint:")
            text: i18nc("@option:check", "Show how to talk to Achilles")
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18nc("@label:listbox", "Text:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18nc("@item:inlistbox text color", "Follows day and night"), value: "auto" },
                { text: i18nc("@item:inlistbox text color", "Always light, for a dark wallpaper"), value: "light" },
                { text: i18nc("@item:inlistbox text color", "Always dark, for a light wallpaper"), value: "dark" },
            ]
            Component.onCompleted: currentIndex = Math.max(0, indexOfValue(cfg_textColor))
            onActivated: cfg_textColor = currentValue
        }
    }
}
