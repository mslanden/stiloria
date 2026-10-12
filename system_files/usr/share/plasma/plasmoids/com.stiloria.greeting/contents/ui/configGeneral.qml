import QtQuick
import QtQuick.Controls as QQC2

import org.kde.coreaddons as KCoreAddons
import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami

import "../code/name.js" as Name

KCMUtils.SimpleKCM {
    property alias cfg_nameOverride: nameField.text
    property alias cfg_showHint: hintCheck.checked
    // Plasma sets these too.
    property string cfg_nameOverrideDefault
    property bool cfg_showHintDefault

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
    }
}
