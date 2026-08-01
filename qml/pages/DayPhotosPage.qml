import QtQuick 2.6
import Sailfish.Silica 1.0

// All photos taken on a given day (opened from the Events page)
Page {
    id: page

    property string dateKey: ""   // yyyy-MM-dd
    property string title: ""
    property string coverPath: ""

    allowedOrientations: Orientation.All

    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || dateKey.length === 0) return

        coverPath = facePipeline.getEventCovers()["day:" + dateKey] || ""
        photosModel.clear()

        // Collect the day's photos across every person, deduplicated
        var seen = {}
        var items = []
        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            var photos = facePipeline.getPersonPhotos(people[i].person_id)
            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp || seen[photo.file_path]) continue
                var key = Qt.formatDate(new Date(photo.timestamp * 1000), "yyyy-MM-dd")
                if (key === dateKey) {
                    seen[photo.file_path] = true
                    items.push({
                        file_path: photo.file_path,
                        timestamp: photo.timestamp
                    })
                }
            }
        }

        items.sort(function(a, b) { return a.timestamp - b.timestamp })
        for (var n = 0; n < items.length; n++) {
            photosModel.append(items[n])
        }
    }

    Component.onCompleted: {
        loadPhotos()
    }

    SilicaGridView {
        id: gridView
        anchors.fill: parent

        cellWidth: width / 3
        cellHeight: cellWidth

        model: photosModel

        header: PageHeader {
            title: page.title
            description: gridView.count + " " + (gridView.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        delegate: ListItem {
            id: photoItem
            width: gridView.cellWidth
            height: gridView.cellHeight
            contentHeight: gridView.cellHeight

            // Wrap content in Item to fix ContextMenu positioning
            contentItem.children: [
                Image {
                    anchors.fill: parent
                    anchors.margins: Theme.paddingSmall / 2
                    source: model.file_path ? "file://" + model.file_path : ""
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    clip: true
                    asynchronous: true
                    sourceSize.width: 400
                    sourceSize.height: 400

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: parent.status === Image.Loading
                        size: BusyIndicatorSize.Small
                    }

                    // Marks the photo currently used as this day's cover
                    Rectangle {
                        visible: model.file_path === coverPath
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: Theme.paddingSmall
                        }
                        width: Theme.iconSizeSmall
                        height: width
                        radius: width / 2
                        color: Theme.rgba("#FFC107", 0.95)
                        border.color: "white"
                        border.width: 2
                        z: 100

                        Label {
                            anchors.centerIn: parent
                            text: "★"
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: "white"
                        }
                    }
                }
            ]

            onClicked: {
                pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                    photoPath: model.file_path
                })
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Set as day cover")
                    onClicked: {
                        facePipeline.setEventCover("day:" + dateKey, model.file_path)
                        coverPath = model.file_path
                    }
                }
                MenuItem {
                    text: qsTr("View full photo")
                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                            photoPath: model.file_path
                        })
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }
}
