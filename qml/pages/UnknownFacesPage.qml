import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Unmapped faces model
    ListModel {
        id: unmappedFacesModel
    }

    function refreshUnmappedFaces() {
        if (!faceManager || !faceManager.initialized) return

        unmappedFacesModel.clear()
        var faces = faceManager.getUnmappedFaces()
        for (var i = 0; i < faces.length; i++) {
            unmappedFacesModel.append(faces[i])
        }
    }

    Component.onCompleted: {
        refreshUnmappedFaces()
    }

    Connections {
        target: faceManager
        onScanCompleted: refreshUnmappedFaces()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Unknown Faces")
            }

            // Info banner
            Item {
                width: parent.width
                height: infoBanner.height

                Rectangle {
                    id: infoBanner
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: infoColumn.height + 2 * Theme.paddingMedium
                    x: Theme.horizontalPageMargin
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                    Column {
                        id: infoColumn
                        width: parent.width - 2 * Theme.paddingMedium
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            width: parent.width
                            text: qsTr("Identify people")
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.highlightColor
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            width: parent.width
                            text: qsTr("Tap on a face to give it a name. Faces from the same person will be grouped together automatically.")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryHighlightColor
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // Face count
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: unmappedFacesModel.count === 0
                    ? qsTr("No faces to identify")
                    : (unmappedFacesModel.count === 1
                        ? qsTr("1 face found")
                        : qsTr("%n faces found", "", unmappedFacesModel.count))
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                visible: unmappedFacesModel.count > 0
            }

            // Grid of faces
            Grid {
                id: faceGrid
                width: parent.width
                columns: 3
                spacing: Theme.paddingSmall

                Repeater {
                    model: unmappedFacesModel

                    delegate: BackgroundItem {
                        id: faceItem
                        width: faceGrid.width / 3
                        height: width

                        // Card-like container
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Theme.paddingSmall / 2
                            radius: Theme.paddingSmall
                            color: Theme.rgba(Theme.highlightBackgroundColor, faceItem.highlighted ? 0.2 : 0.05)
                            border.color: Theme.rgba(Theme.highlightColor, 0.2)
                            border.width: 1

                            // Face image (cropped from photo)
                            Image {
                                id: faceImage
                                anchors.fill: parent
                                anchors.margins: 1
                                source: model.photo_path ? "file://" + model.photo_path : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                clip: true

                                // Crop to face region using sourceClipRect
                                property int imgWidth: sourceSize.width
                                property int imgHeight: sourceSize.height

                                // Calculate crop rectangle
                                sourceClipRect: Qt.rect(
                                    model.bbox_x * imgWidth,
                                    model.bbox_y * imgHeight,
                                    model.bbox_width * imgWidth,
                                    model.bbox_height * imgHeight
                                )

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    size: BusyIndicatorSize.Small
                                    running: parent.status === Image.Loading
                                }

                                // Error state
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)
                                    visible: parent.status === Image.Error

                                    Image {
                                        anchors.centerIn: parent
                                        source: "image://theme/icon-m-person"
                                        opacity: 0.3
                                    }
                                }
                            }

                            // Detection quality indicator (subtle)
                            Rectangle {
                                anchors {
                                    top: parent.top
                                    right: parent.right
                                    margins: Theme.paddingSmall
                                }
                                width: Theme.iconSizeExtraSmall
                                height: width
                                radius: width / 2

                                // Color based on confidence: green > 0.7, yellow > 0.5, red otherwise
                                color: model.confidence > 0.7
                                    ? Theme.rgba("#4CAF50", 0.9)  // Green
                                    : (model.confidence > 0.5
                                        ? Theme.rgba("#FFC107", 0.9)  // Yellow
                                        : Theme.rgba("#F44336", 0.9))  // Red

                                visible: faceImage.status === Image.Ready
                            }
                        }

                        onClicked: {
                            var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/IdentifyFaceDialog.qml"), {
                                faceId: model.face_id,
                                photoPath: model.photo_path,
                                faceBbox: Qt.rect(model.bbox_x, model.bbox_y, model.bbox_width, model.bbox_height)
                            })
                            dialog.accepted.connect(function() {
                                refreshUnmappedFaces()
                            })
                        }
                    }
                }
            }

            // Empty state
            ViewPlaceholder {
                enabled: unmappedFacesModel.count === 0
                text: qsTr("No unknown faces")
                hintText: qsTr("All detected faces have been identified")
            }
        }
    }
}
