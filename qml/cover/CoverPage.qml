import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium

        Image {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            source: "image://theme/icon-l-image"
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
        }

        Label {
            id: appName
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nami"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }

        Label {
            id: statusLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("0 people")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }

        Label {
            id: photosLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("0 photos")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
    }

    CoverActionList {
        id: coverAction

        CoverAction {
            iconSource: "image://theme/icon-cover-refresh"
            onTriggered: {
                // Trigger face recognition refresh
                // TODO: Implement scan trigger from cover
            }
        }
    }
}

