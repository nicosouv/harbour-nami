import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property int faceId
    property string photoPath

    property var faceManager: appWindow.faceRecognition
    property int selectedPersonId: -1
    property bool createNew: false

    canAccept: (selectedPersonId > 0) || (createNew && newNameField.text.trim().length > 0)

    onAccepted: {
        if (createNew) {
            // Create new person from face
            var newName = newNameField.text.trim()
            faceManager.createPerson(faceId, newName, null)
        } else if (selectedPersonId > 0) {
            // Assign to existing person
            faceManager.assignFaceToPerson(faceId, selectedPersonId)
        }
    }

    // People model
    ListModel {
        id: peopleModel
    }

    Component.onCompleted: {
        // Load existing people
        faceManager.getAllPeople(function(people) {
            peopleModel.clear()
            for (var i = 0; i < people.length; i++) {
                peopleModel.append(people[i])
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Confirm")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Who is this?")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            // Photo preview
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: width
                source: "image://nothumb/" + photoPath
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }

            SectionHeader {
                text: qsTr("Select Person")
            }

            // Create new person option
            TextSwitch {
                id: createNewSwitch
                text: qsTr("Create new person")
                description: qsTr("This is someone new")
                checked: createNew
                onCheckedChanged: {
                    createNew = checked
                    if (checked) {
                        selectedPersonId = -1
                    }
                }
            }

            // New person name field
            TextField {
                id: newNameField
                width: parent.width
                visible: createNew
                label: qsTr("Name")
                placeholderText: qsTr("Enter person name")

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }

            // Existing people list
            SectionHeader {
                text: qsTr("Existing People")
                visible: !createNew && peopleModel.count > 0
            }

            Repeater {
                model: peopleModel
                visible: !createNew

                delegate: ListItem {
                    width: column.width
                    contentHeight: Theme.itemSizeSmall

                    highlighted: selectedPersonId === model.person_id

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.paddingMedium

                        Rectangle {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            radius: Theme.iconSizeMedium / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-contact"
                                width: Theme.iconSizeSmall
                                height: Theme.iconSizeSmall
                            }
                        }

                        Label {
                            text: model.name
                            color: selectedPersonId === model.person_id ?
                                   Theme.highlightColor : Theme.primaryColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    onClicked: {
                        selectedPersonId = model.person_id
                        createNew = false
                    }
                }
            }

            ViewPlaceholder {
                enabled: !createNew && peopleModel.count === 0
                text: qsTr("No people yet")
                hintText: qsTr("Create a new person to get started")
            }
        }

        VerticalScrollDecorator {}
    }
}
