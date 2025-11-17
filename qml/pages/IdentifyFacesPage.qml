import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline
    property int currentIndex: 0
    property var currentFaces: []

    allowedOrientations: Orientation.All

    // Load unmapped faces
    function loadUnmappedFaces() {
        if (!faceManager || !faceManager.initialized) return

        currentFaces = faceManager.getUnmappedFaces()
        currentIndex = 0
    }

    // Skip current face (ignore/false positive)
    function skipFace() {
        if (currentIndex < currentFaces.length - 1) {
            currentIndex++
        } else {
            // No more faces
            pageStack.pop()
        }
    }

    // Identify face as new person or existing
    function identifyFace(personId, personName) {
        if (currentIndex >= currentFaces.length) return

        var faceId = currentFaces[currentIndex].face_id
        facePipeline.identifyFace(faceId, personId, personName)

        // Move to next face
        if (currentIndex < currentFaces.length - 1) {
            currentIndex++
        } else {
            // No more faces
            pageStack.pop()
        }
    }

    // People model for selection
    ListModel {
        id: peopleModel
    }

    Component.onCompleted: {
        loadUnmappedFaces()

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

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Face image card
            Item {
                id: faceCard
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.8
                height: width

                visible: currentIndex < currentFaces.length

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingMedium
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    border.color: Theme.rgba(Theme.highlightColor, 0.3)
                    border.width: 2

                    Image {
                        id: faceImage
                        anchors.fill: parent
                        anchors.margins: 4
                        source: currentIndex < currentFaces.length
                            ? "file://" + currentFaces[currentIndex].photo_path
                            : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true

                        // Limit source size to save memory
                        sourceSize.width: 640
                        sourceSize.height: 640

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                        }

                        // Face bounding box overlay
                        Item {
                            anchors.fill: parent
                            visible: faceImage.status === Image.Ready && currentIndex < currentFaces.length

                            Rectangle {
                                color: "transparent"
                                border.color: "#FF5252"
                                border.width: 4

                                // Calculate position and size based on image display
                                property real imageDisplayWidth: faceImage.paintedWidth > 0 ? faceImage.paintedWidth : faceImage.width
                                property real imageDisplayHeight: faceImage.paintedHeight > 0 ? faceImage.paintedHeight : faceImage.height
                                property real imageOffsetX: (faceImage.width - imageDisplayWidth) / 2
                                property real imageOffsetY: (faceImage.height - imageDisplayHeight) / 2
                                property real srcWidth: faceImage.sourceSize.width > 0 ? faceImage.sourceSize.width : 1
                                property real srcHeight: faceImage.sourceSize.height > 0 ? faceImage.sourceSize.height : 1

                                // Scale factors
                                property real scaleX: imageDisplayWidth / srcWidth
                                property real scaleY: imageDisplayHeight / srcHeight

                                x: currentIndex < currentFaces.length
                                   ? imageOffsetX + (currentFaces[currentIndex].bbox_x * scaleX)
                                   : 0
                                y: currentIndex < currentFaces.length
                                   ? imageOffsetY + (currentFaces[currentIndex].bbox_y * scaleY)
                                   : 0
                                width: currentIndex < currentFaces.length
                                       ? currentFaces[currentIndex].bbox_width * scaleX
                                       : 0
                                height: currentIndex < currentFaces.length
                                        ? currentFaces[currentIndex].bbox_height * scaleY
                                        : 0

                                // Corner markers
                                Repeater {
                                    model: [
                                        {x: 0, y: 0, w: 20, h: 4, a: "left", b: "top"},
                                        {x: 0, y: 0, w: 4, h: 20, a: "left", b: "top"},
                                        {x: 0, y: 0, w: 20, h: 4, a: "right", b: "top"},
                                        {x: 0, y: 0, w: 4, h: 20, a: "right", b: "top"},
                                        {x: 0, y: 0, w: 20, h: 4, a: "left", b: "bottom"},
                                        {x: 0, y: 0, w: 4, h: 20, a: "left", b: "bottom"},
                                        {x: 0, y: 0, w: 20, h: 4, a: "right", b: "bottom"},
                                        {x: 0, y: 0, w: 4, h: 20, a: "right", b: "bottom"}
                                    ]
                                    Rectangle {
                                        anchors[modelData.a]: parent[modelData.a]
                                        anchors[modelData.b]: parent[modelData.b]
                                        width: modelData.w
                                        height: modelData.h
                                        color: "#FF5252"
                                    }
                                }
                            }
                        }
                    }

                    // Confidence indicator
                    Rectangle {
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: Theme.paddingMedium
                        }
                        width: confidenceLabel.width + Theme.paddingMedium * 2
                        height: confidenceLabel.height + Theme.paddingSmall * 2
                        radius: height / 2
                        color: Theme.rgba(
                            currentIndex < currentFaces.length && currentFaces[currentIndex].confidence > 0.7
                                ? "#4CAF50"  // Green
                                : (currentIndex < currentFaces.length && currentFaces[currentIndex].confidence > 0.5
                                    ? "#FFC107"  // Yellow
                                    : "#F44336"),  // Red
                            0.9
                        )

                        Label {
                            id: confidenceLabel
                            anchors.centerIn: parent
                            text: currentIndex < currentFaces.length
                                ? Math.round(currentFaces[currentIndex].confidence * 100) + "%"
                                : ""
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: "white"
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Action buttons row
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge
                visible: currentIndex < currentFaces.length

                // Skip button (left)
                IconButton {
                    icon.source: "image://theme/icon-m-dismiss"
                    onClicked: skipFace()

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: parent.height
                        radius: width / 2
                        color: Theme.rgba("#F44336", 0.2)
                        z: -1
                    }
                }

                // Identify button (right)
                IconButton {
                    icon.source: "image://theme/icon-m-acknowledge"
                    onClicked: {
                        // Open dialog to select person
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
                            peopleModel: peopleModel
                        })
                        dialog.accepted.connect(function() {
                            if (dialog.createNew) {
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
                        color: Theme.rgba("#4CAF50", 0.2)
                        z: -1
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            // Instructions
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("✗ Skip (not a face or low quality)\n✓ Identify (assign to a person)")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: currentIndex < currentFaces.length
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
