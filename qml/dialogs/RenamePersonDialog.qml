import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property int personId
    property string currentName
    // Result read by the caller on accepted
    property string newName: ""

    // Overridable, so the same dialog can rename anything else with a name.
    // The defaults are what the people list has always shown.
    property string titleText: qsTr("Rename Person")
    property string fieldPlaceholder: qsTr("Enter person name")

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
                label: qsTr("Name")
                placeholderText: dialog.fieldPlaceholder
                text: currentName
                focus: true

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
