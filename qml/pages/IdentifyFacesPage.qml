import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    property var faceManager: facePipeline
    property int currentIndex: 0
    property var currentFaces: []

    allowedOrientations: Orientation.All

    property var currentFace: currentIndex < currentFaces.length ? currentFaces[currentIndex] : null

    // Load unmapped faces
    function loadUnmappedFaces() {
        if (!faceManager || !faceManager.initialized) return

        currentFaces = faceManager.getUnmappedFaces()
        currentIndex = 0
    }

    // Ignore current face permanently (not a face, stranger, low quality)
    function skipFace() {
        if (currentFace) {
            facePipeline.ignoreFace(currentFace.face_id)
        }
        nextFace()
    }

    function nextFace() {
        if (currentIndex < currentFaces.length - 1) {
            currentIndex++
        } else {
            // No more faces. Leaving from here would destroy the very item
            // whose click handler is running (a suggestion row, a dialog),
            // so the page leaves once the handler has returned.
            popTimer.restart()
        }
    }

    Timer {
        id: popTimer
        interval: 0
        onTriggered: {
            pageStack.completeAnimation()
            pageStack.pop()
        }
    }

    // Identify face as new person or existing (optionally linking a contact)
    function identifyFace(personId, personName, contactId) {
        if (!currentFace) return

        facePipeline.identifyFace(currentFace.face_id, personId, personName, contactId || "")
        nextFace()
        // Models are refreshed by refreshTimer, never from here: see the
        // timer's comment
        refreshTimer.restart()
    }

    // Identification can be triggered from deep inside a dialog being torn
    // down - the contact flow accepts SelectContactDialog from one of its
    // delegates, which accepts SelectPersonDialog in turn, while the page
    // transition is still running. Rebuilding peopleModel right there pulls
    // the ground from under the delegates of a dialog that is still alive
    // and bound to that very model. So every model refresh is pushed to the
    // next pass of the event loop, once the dialogs are gone.
    Timer {
        id: refreshTimer
        interval: 0
        onTriggered: {
            // A dialog above us stays alive, and bound to peopleModel, until
            // the stack transition finishes - later than the next event loop
            // pass. Leave it alone; onStatusChanged fires the refresh again
            // once the page is really back in front.
            if (page.status !== PageStatus.Active) {
                return
            }
            loadPeople()
            loadSuggestions()
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Active) {
            refreshTimer.restart()
        }
    }

    // People model for selection
    ListModel {
        id: peopleModel
    }

    // Ranked candidates for the current face: when the top one is right,
    // identifying costs a single tap instead of opening the dialog
    property var suggestions: []

    // Words, not a percentage: a cosine similarity is not a probability and
    // showing it as one would read as far more certain than it is
    function suggestionHint(suggestion) {
        var hint = suggestion.strong ? qsTr("Very likely") : qsTr("Possible match")
        return suggestion.same_day ? hint + " · " + qsTr("photographed the same day") : hint
    }

    function loadSuggestions() {
        suggestions = (currentFace && facePipeline && facePipeline.initialized)
            ? facePipeline.suggestPeopleForFace(currentFace.face_id, 2)
            : []
    }

    onCurrentFaceChanged: refreshTimer.restart()

    // Updated in place rather than cleared and refilled, the same way
    // PeoplePage does it: clear() destroys every delegate at once, including
    // those of a dialog that may still be bound to this model
    function loadPeople() {
        if (!facePipeline || !facePipeline.initialized) return

        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            if (i < peopleModel.count) {
                peopleModel.set(i, people[i])
            } else {
                peopleModel.append(people[i])
            }
        }
        while (peopleModel.count > people.length) {
            peopleModel.remove(peopleModel.count - 1)
        }
    }

    Component.onCompleted: {
        loadUnmappedFaces()
        loadPeople()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Skip all")
                onClicked: pageStack.pop()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Identify Faces")
            }

            // Progress indicator
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: currentFaces.length > 0
                    ? qsTr("%1 of %2").arg(currentIndex + 1).arg(currentFaces.length)
                    : qsTr("No faces to identify")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                horizontalAlignment: Text.AlignHCenter
            }

            // Cropped face card
            Item {
                id: faceCard
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.7
                height: width

                visible: currentFace !== null

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    border.color: Theme.rgba(Theme.highlightColor, 0.3)
                    border.width: 2
                    clip: true

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        anchors.margins: 4
                        source: currentFace
                            ? FaceUtils.cropUrl(currentFace.photo_path,
                                                currentFace.bbox_x, currentFace.bbox_y,
                                                currentFace.bbox_width, currentFace.bbox_height,
                                                false)
                            : ""
                        sourceSize.width: 512
                        sourceSize.height: 512
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }
                    }

                    // Detection confidence badge
                    Rectangle {
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: Theme.paddingMedium
                        }
                        width: confidenceLabel.width + Theme.paddingMedium * 2
                        height: confidenceLabel.height + Theme.paddingSmall * 2
                        radius: height / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.8)

                        Label {
                            id: confidenceLabel
                            anchors.centerIn: parent
                            text: currentFace
                                ? Math.round(currentFace.confidence * 100) + "%"
                                : ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.primaryColor
                        }
                    }
                }
            }

            // One-tap suggestions, best first
            Column {
                width: parent.width
                spacing: Theme.paddingSmall
                visible: currentFace !== null && suggestions.length > 0

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: qsTr("Is this…")
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                }

                Repeater {
                    model: suggestions

                    delegate: BackgroundItem {
                        width: parent.width
                        height: Theme.itemSizeSmall

                        Row {
                            anchors {
                                left: parent.left
                                leftMargin: Theme.horizontalPageMargin
                                right: parent.right
                                rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: Theme.paddingMedium

                            Item {
                                width: Theme.iconSizeMedium
                                height: Theme.iconSizeMedium
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    id: suggestionAvatar
                                    anchors.fill: parent
                                    source: FaceUtils.personAvatarUrl(facePipeline, modelData.person_id)
                                    sourceSize.width: width
                                    sourceSize.height: height
                                    asynchronous: true
                                }

                                Icon {
                                    anchors.centerIn: parent
                                    source: "image://theme/icon-m-person"
                                    visible: suggestionAvatar.status !== Image.Ready
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                Label {
                                    text: modelData.name
                                    color: Theme.primaryColor
                                }

                                Label {
                                    text: suggestionHint(modelData)
                                    font.pixelSize: Theme.fontSizeExtraSmall
                                    color: Theme.secondaryColor
                                }
                            }
                        }

                        onClicked: identifyFace(modelData.person_id, "")
                    }
                }
            }

            // Show the face in its photo context
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("View in photo")
                visible: currentFace !== null
                onClicked: {
                    pageStack.push(Qt.resolvedUrl("FaceInPhotoPage.qml"), {
                        photoPath: currentFace.photo_path,
                        bboxX: currentFace.bbox_x,
                        bboxY: currentFace.bbox_y,
                        bboxWidth: currentFace.bbox_width,
                        bboxHeight: currentFace.bbox_height
                    })
                }
            }

            // Action buttons row
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 2
                visible: currentFace !== null

                // Ignore button (left)
                IconButton {
                    icon.source: "image://theme/icon-m-dismiss"
                    onClicked: skipFace()

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: Theme.rgba(Theme.errorColor, 0.2)
                        z: -1
                    }
                }

                // Identify button (right)
                IconButton {
                    icon.source: "image://theme/icon-m-acknowledge"
                    onClicked: {
                        // Open dialog to select person
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
                            peopleModel: peopleModel,
                            allowContact: true
                        })
                        dialog.accepted.connect(function() {
                            if (dialog.selectedContactId.length > 0) {
                                identifyFace(-1, dialog.selectedContactName, dialog.selectedContactId)
                            } else if (dialog.createNew) {
                                identifyFace(-1, dialog.personName)
                            } else {
                                identifyFace(dialog.selectedPersonId, "")
                            }
                        })
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: Theme.rgba(Theme.highlightColor, 0.2)
                        z: -1
                    }
                }
            }

            // Instructions
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("✗ Ignore (not a face or low quality, won't be shown again)\n✓ Identify (assign to a person)")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: currentFace !== null
            }

            // Completion message
            ViewPlaceholder {
                enabled: currentFaces.length === 0 || currentIndex >= currentFaces.length
                text: currentFaces.length === 0
                    ? qsTr("No faces to identify")
                    : qsTr("All done!")
                hintText: currentFaces.length === 0
                    ? qsTr("All detected faces have been identified")
                    : qsTr("You've reviewed all unknown faces")
            }
        }

        VerticalScrollDecorator {}
    }
}
