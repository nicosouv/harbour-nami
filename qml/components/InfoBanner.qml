import QtQuick 2.0
import Sailfish.Silica 1.0

// Custom info banner component for notifications
Item {
    id: root

    anchors {
        left: parent.left
        right: parent.right
        leftMargin: Theme.horizontalPageMargin
        rightMargin: Theme.horizontalPageMargin
    }
    height: banner.height
    visible: opacity > 0
    opacity: 0

    Behavior on opacity {
        FadeAnimation {}
    }

    function show(message, duration) {
        banner.text = message
        opacity = 1
        hideTimer.interval = duration || 3000
        hideTimer.restart()
    }

    Rectangle {
        id: banner
        anchors {
            left: parent.left
            right: parent.right
        }
        height: bannerText.height + 2 * Theme.paddingMedium
        radius: Theme.paddingSmall
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)

        property alias text: bannerText.text

        Label {
            id: bannerText
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                margins: Theme.paddingMedium
            }
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    Timer {
        id: hideTimer
        onTriggered: root.opacity = 0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.opacity = 0
    }
}
