import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property int personId
    property string personName

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Photos model
    ListModel {
        id: photosModel
    }

    function refreshPhotos() {
        if (!faceManager || !faceManager.ready) return

        faceManager.getPersonPhotos(personId, function(photos) {
            photosModel.clear()
            for (var i = 0; i < photos.length; i++) {
                photosModel.append(photos[i])
            }
        })
    }

    Component.onCompleted: {
        refreshPhotos()
    }

    SilicaGridView {
        id: gridView
        anchors.fill: parent

        cellWidth: width / 3
        cellHeight: cellWidth

        model: photosModel

        header: PageHeader {
            title: personName
        }

        delegate: BackgroundItem {
            width: gridView.cellWidth
            height: gridView.cellHeight

            Image {
                anchors.fill: parent
                anchors.margins: Theme.paddingSmall
                source: "image://nothumb/" + model.path
                fillMode: Image.PreserveAspectCrop
                clip: true
                asynchronous: true

                // Fallback for missing images
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

            onClicked: {
                // Open photo viewer
                pageStack.push(Qt.resolvedUrl("PhotoViewPage.qml"), {
                    photoPath: model.path,
                    photoId: model.id
                })
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No photos")
            hintText: qsTr("This person has no photos yet")
        }

        VerticalScrollDecorator {}
    }
}
