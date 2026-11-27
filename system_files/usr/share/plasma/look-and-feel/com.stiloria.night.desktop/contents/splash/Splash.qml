/*
    Stiloria's loading screen after login, in Porcelain Night: the helmet and
    the wordmark in ivory on warm black, with a slate hairline that fills as
    Plasma starts. Day and night both use it (build.sh copies it into
    Stiloria Day): the login screen before it and the Helmet wallpaper after
    it are dark at every hour, so an ivory screen between them would flash.
    The helmet is the logo in ivory, gzipped into images/ by build.sh.

    ksplashqml sets stage from 1 to 5 as Plasma comes up. Durations come from
    Kirigami's units, so Plasma's animation speed setting (off included)
    applies here too.
*/
import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: root
    color: "#131210"

    property int stage

    onStageChanged: {
        if (stage == 2) {
            fadeIn.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        Column {
            anchors.centerIn: parent
            spacing: Kirigami.Units.gridUnit * 1.5

            Image {
                id: helmet
                anchors.horizontalCenter: parent.horizontalCenter
                asynchronous: true
                source: "images/stiloria.svgz"
                sourceSize.width: Kirigami.Units.gridUnit * 7
                sourceSize.height: Kirigami.Units.gridUnit * 7
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Stiloria"
                color: "#f2eee8"
                font.family: "Instrument Serif"
                font.pixelSize: Kirigami.Units.gridUnit * 2.4
                textFormat: Text.PlainText
                Accessible.name: text
                Accessible.role: Accessible.StaticText
            }

            // Progress: a slate hairline on a faint ivory track.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Kirigami.Units.gridUnit * 9
                height: 2
                radius: 1
                color: Qt.alpha("#f2eee8", 0.10)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: "#9fb4c2"
                    width: parent.width * Math.min(root.stage, 5) / 5
                    Behavior on width {
                        NumberAnimation {
                            duration: Kirigami.Units.longDuration
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    OpacityAnimator {
        id: fadeIn
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.longDuration
        easing.type: Easing.OutCubic
    }
}
