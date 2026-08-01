import QtQuick 2.0
import Sailfish.Silica 1.0

// Reused for both naming a new trip and renaming an existing one
Dialog {
    id: dialog

    property string titleText: qsTr("Name this trip")
    property string currentName: ""
    // Result read by the caller on accepted
    property string newName: ""

    canAccept: nameField.text.trim().length > 0

    onAccepted: newName = nameField.text.trim()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Save")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: dialog.titleText
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            TextField {
                id: nameField
                width: parent.width
                label: qsTr("Trip name")
                placeholderText: qsTr("e.g. Rome, Summer holidays")
                text: currentName
                focus: true

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
