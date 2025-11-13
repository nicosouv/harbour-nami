import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: appWindow.faceRecognition

    allowedOrientations: Orientation.All

    // Unmapped faces model
    ListModel {
        id: unmappedFacesModel
    }

    function refreshUnmappedFaces() {
        if (!faceManager || !faceManager.ready) return

        faceManager.getUnmappedFaces(function(faces) {
            unmappedFacesModel.clear()
            for (var i = 0; i < faces.length; i++) {
                unmappedFacesModel.append(faces[i])
            }
        })
    }

    Component.onCompleted: {
        refreshUnmappedFaces()
    }

    Connections {
        target: faceManager
        onFaceAssigned: refreshUnmappedFaces()
        onPersonCreated: refreshUnmappedFaces()
    }

    SilicaGridView {
        id: gridView
        anchors.fill: parent

        cellWidth: width / 3
        cellHeight: cellWidth

        model: unmappedFacesModel

        header: Column {
            width: parent.width

            PageHeader {
                title: qsTr("Unknown Faces")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Tap a face to identify the person")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        delegate: BackgroundItem {
            id: delegate
            width: gridView.cellWidth
            height: gridView.cellHeight

            Image {
                id: photoImage
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall
                source: "image://nothumb/" + model.photo_path
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true

                // Overlay to show face region
                Rectangle {
                    x: Math.max(0, model.bbox[0] * parent.paintedWidth / parent.sourceSize.width)
                    y: Math.max(0, model.bbox[1] * parent.paintedHeight / parent.sourceSize.height)
                    width: Math.min(parent.width, model.bbox[2] * parent.paintedWidth / parent.sourceSize.width)
                    height: Math.min(parent.height, model.bbox[3] * parent.paintedHeight / parent.sourceSize.height)
                    color: "transparent"
                    border.color: Theme.highlightColor
                    border.width: 2
                    visible: photoImage.status === Image.Ready
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                    visible: parent.status === Image.Error

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-image"
                        opacity: 0.3
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Small
                    running: parent.status === Image.Loading
                }
            }

            // Confidence badge
            Rectangle {
                anchors {
                    bottom: parent.bottom
                    right: parent.right
                    margins: Theme.paddingSmall
                }
                width: confLabel.width + Theme.paddingSmall
                height: confLabel.height + Theme.paddingSmall / 2
                radius: Theme.paddingSmall / 2
                color: Theme.rgba(Theme.highlightBackgroundColor, 0.8)

                Label {
                    id: confLabel
                    anchors.centerIn: parent
                    text: Math.round(model.confidence * 100) + "%"
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.primaryColor
                }
            }

            onClicked: {
                var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/IdentifyFaceDialog.qml"), {
                    faceId: model.face_id,
                    photoPath: model.photo_path
                })
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No unknown faces")
            hintText: qsTr("All detected faces have been identified")
        }

        VerticalScrollDecorator {}
    }
}
