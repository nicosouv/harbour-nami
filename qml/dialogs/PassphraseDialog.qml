import QtQuick 2.0
import Sailfish.Silica 1.0

// Reused for both setting a new backup passphrase (confirmRequired) and
// entering one to restore
Dialog {
    id: dialog

    property string titleText: qsTr("Enter passphrase")
    property string infoText: ""
    property bool confirmRequired: false
    // Result read by the caller on accepted
    property string passphrase: ""

    canAccept: passphraseField.text.length >= 8
               && (!confirmRequired || passphraseField.text === confirmField.text)

    onAccepted: passphrase = passphraseField.text

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: confirmRequired ? qsTr("Create") : qsTr("Restore")
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

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: dialog.infoText
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
                visible: text.length > 0
            }

            TextField {
                id: passphraseField
                width: parent.width
                label: qsTr("Passphrase")
                placeholderText: qsTr("At least 8 characters")
                echoMode: TextInput.Password
                focus: true

                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            TextField {
                id: confirmField
                width: parent.width
                label: qsTr("Confirm passphrase")
                echoMode: TextInput.Password
                visible: confirmRequired

                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Passphrases don't match")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
                visible: confirmRequired && confirmField.text.length > 0
                         && passphraseField.text !== confirmField.text
            }
        }
    }
}
