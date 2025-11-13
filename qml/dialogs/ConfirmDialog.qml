import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property string title
    property string message

    canAccept: true

    Column {
        width: parent.width
        spacing: Theme.paddingLarge

        DialogHeader {
            acceptText: qsTr("Confirm")
            cancelText: qsTr("Cancel")
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.WordWrap
            text: dialog.title
            color: Theme.highlightColor
            font.pixelSize: Theme.fontSizeLarge
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.WordWrap
            text: dialog.message
            color: Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
