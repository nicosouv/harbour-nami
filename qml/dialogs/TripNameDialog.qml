import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"

// Reused for naming a single day, naming a new trip and renaming either
Dialog {
    id: dialog

    property string titleText: qsTr("Name this trip")
    property string currentName: ""
    // Result read by the caller on accepted
    property string newName: ""

    // One day rather than several. Changes nothing about what is stored: a
    // named day is a trip of one date, and the words are the user's own
    // either way. It only changes what is offered as a starting point.
    property bool singleDay: false

    // Seeds, not a taxonomy.
    //
    // A stored list of categories would have to be translated, and a
    // memory's title is deliberately kept as raw user words precisely so it
    // never freezes into the language it was created in. It would also be a
    // second name competing with the real one: "Birthday" tells you less
    // than "Lea's birthday", and the keyboard is the slow part, not the
    // vocabulary. So these fill the field and then get out of the way.
    readonly property var suggestions: singleDay
        ? [qsTr("Birthday"), qsTr("Party"), qsTr("Wedding"), qsTr("Outing"),
           qsTr("Concert"), qsTr("Dinner")]
        : [qsTr("Holiday"), qsTr("Weekend"), qsTr("Road trip"), qsTr("Hike"),
           qsTr("Family")]

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
                label: dialog.singleDay ? qsTr("Event name") : qsTr("Trip name")
                placeholderText: dialog.singleDay
                    ? qsTr("e.g. Birthday, Beach day")
                    : qsTr("e.g. Rome, Summer holidays")
                text: currentName
                focus: true

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            // Under the field, so they read as a way of filling it rather
            // than as a choice of their own
            Flow {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Repeater {
                    model: dialog.suggestions

                    delegate: FilterChip {
                        text: modelData
                        selected: nameField.text.trim() === modelData
                        onClicked: {
                            nameField.text = modelData
                            nameField.forceActiveFocus()
                        }
                    }
                }
            }
        }
    }
}
