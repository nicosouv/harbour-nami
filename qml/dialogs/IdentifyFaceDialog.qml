import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    property int faceId
    property string photoPath
    property rect faceBbox

    property var faceManager: facePipeline
    property int selectedPersonId: -1
    property bool createNew: true  // Default to creating new person

    canAccept: (selectedPersonId > 0) || (createNew && newNameField.text.trim().length > 0)

    onAccepted: {
        if (createNew) {
            // Create new person from face
            var newName = newNameField.text.trim()
            facePipeline.identifyFace(faceId, -1, newName)
        } else if (selectedPersonId > 0) {
            // Assign to existing person
            facePipeline.identifyFace(faceId, selectedPersonId, "")
        }
    }

    // People model
    ListModel {
        id: peopleModel
    }

    Component.onCompleted: {
        // Load existing people
        if (facePipeline && facePipeline.initialized) {
            var people = facePipeline.getAllPeople()
            for (var i = 0; i < people.length; i++) {
                peopleModel.append(people[i])
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            DialogHeader {
                acceptText: qsTr("Identify")
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

            // Face preview (cropped)
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.05)
                    border.color: Theme.rgba(Theme.highlightColor, 0.2)
                    border.width: 1

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: photoPath ? "file://" + photoPath : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }

                        // Face bounding box overlay
                        Rectangle {
                            visible: faceImage.status === Image.Ready && faceBbox.width > 0
                            color: "transparent"
                            border.color: "#FF5252"  // Red
                            border.width: 3

                            // Calculate position and size based on image display
                            property real imageDisplayWidth: faceImage.paintedWidth
                            property real imageDisplayHeight: faceImage.paintedHeight
                            property real imageOffsetX: (faceImage.width - imageDisplayWidth) / 2
                            property real imageOffsetY: (faceImage.height - imageDisplayHeight) / 2

                            // Scale factors
                            property real scaleX: imageDisplayWidth / faceImage.sourceSize.width
                            property real scaleY: imageDisplayHeight / faceImage.sourceSize.height

                            x: imageOffsetX + (faceBbox.x * scaleX)
                            y: imageOffsetY + (faceBbox.y * scaleY)
                            width: faceBbox.width * scaleX
                            height: faceBbox.height * scaleY

                            // Corner markers for better visibility
                            Rectangle {
                                anchors { left: parent.left; top: parent.top }
                                width: 12; height: 2
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { left: parent.left; top: parent.top }
                                width: 2; height: 12
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { right: parent.right; top: parent.top }
                                width: 12; height: 2
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { right: parent.right; top: parent.top }
                                width: 2; height: 12
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { left: parent.left; bottom: parent.bottom }
                                width: 12; height: 2
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { left: parent.left; bottom: parent.bottom }
                                width: 2; height: 12
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { right: parent.right; bottom: parent.bottom }
                                width: 12; height: 2
                                color: "#FF5252"
                            }
                            Rectangle {
                                anchors { right: parent.right; bottom: parent.bottom }
                                width: 2; height: 12
                                color: "#FF5252"
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Theme.rgba(Theme.highlightColor, 0.3)
                            border.width: 1
                        }
                    }
                }
            }

            // Create new person (default)
            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            TextField {
                id: newNameField
                width: parent.width
                label: qsTr("Person name")
                placeholderText: qsTr("Enter name (e.g., John, Mom, Friend)")
                focus: true

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (canAccept) dialog.accept()
                }

                onTextChanged: {
                    if (text.trim().length > 0) {
                        createNew = true
                        selectedPersonId = -1
                    }
                }
            }

            // Separator
            Rectangle {
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: 1
                x: Theme.horizontalPageMargin
                color: Theme.rgba(Theme.highlightColor, 0.1)
                visible: peopleModel.count > 0
            }

            // Existing people section
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Or assign to existing person:")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                visible: peopleModel.count > 0
            }

            Repeater {
                model: peopleModel

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
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

                        // Avatar
                        Rectangle {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            radius: width / 2
                            color: Theme.rgba(Theme.highlightBackgroundColor, selectedPersonId === model.person_id ? 0.3 : 0.1)

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-person"
                                width: Theme.iconSizeSmall
                                height: Theme.iconSizeSmall
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.iconSizeMedium - Theme.paddingMedium

                            Label {
                                text: model.name
                                color: selectedPersonId === model.person_id ?
                                       Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }

                            Label {
                                text: model.photo_count + " " + (model.photo_count === 1 ? qsTr("photo") : qsTr("photos"))
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }
                        }
                    }

                    onClicked: {
                        selectedPersonId = model.person_id
                        createNew = false
                        newNameField.text = ""  // Clear name field
                    }
                }
            }

            // Empty state for existing people
            ViewPlaceholder {
                enabled: peopleModel.count === 0
                text: qsTr("No people yet")
                hintText: qsTr("Enter a name above to create the first person")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
