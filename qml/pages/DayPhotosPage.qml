import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/eventsettings.js" as EventSettings

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

    PhotoShareAction { id: shareAction }
    PhotoSelection { id: selection }

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

        // Optionally add photos with no identified person too
        if (EventSettings.includeAllPhotos(facePipeline)) {
            var allPhotos = facePipeline.getAllPhotos()
            for (var ap = 0; ap < allPhotos.length; ap++) {
                var extraPhoto = allPhotos[ap]
                if (!extraPhoto.timestamp || seen[extraPhoto.file_path]) continue
                var extraKey = Qt.formatDate(new Date(extraPhoto.timestamp * 1000), "yyyy-MM-dd")
                if (extraKey === dateKey) {
                    seen[extraPhoto.file_path] = true
                    items.push({
                        file_path: extraPhoto.file_path,
                        timestamp: extraPhoto.timestamp
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
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: selectionBar.top
        }
        clip: true

        cellWidth: width / 3
        cellHeight: cellWidth

        model: photosModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Select photos")
                enabled: photosModel.count > 0 && !selection.active
                onClicked: selection.begin("")
            }
        }

        header: PageHeader {
            title: page.title
            description: gridView.count + " " + (gridView.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        delegate: ListItem {
            id: photoItem
            width: gridView.cellWidth
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

                    // Selection state
                    Rectangle {
                        anchors.fill: parent
                        visible: selection.active
                        color: selection.isSelected(model.file_path)
                               ? Theme.rgba(Theme.highlightBackgroundColor, 0.45)
                               : Theme.rgba("black", 0.35)
                        z: 90

                        Icon {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-acknowledge"
                            opacity: selection.isSelected(model.file_path) ? 1 : 0.25
                        }
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
                if (selection.active) {
                    selection.toggle(model.file_path)
                    return
                }
                pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                    photoPath: model.file_path
                })
            }

            // A SilicaGridView cannot push its next row down for an inline
            // ContextMenu, so long press enters selection mode instead. The
            // per-photo actions live there (share) or on the photo itself.
            onPressAndHold: {
                if (!selection.active) {
                    selection.begin(model.file_path)
                } else {
                    selection.toggle(model.file_path)
                }
            }
        }

        ViewPlaceholder {
            enabled: gridView.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }

    PhotoSelectionBar {
        id: selectionBar
        photoSelection: selection
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        onShareRequested: {
            if (shareAction.sharePhotos(selection.paths)) selection.end()
        }
        // One page-specific action: promote the single selected photo to
        // this day's cover
        extraActionIcon: "image://theme/icon-m-favorite"
        extraActionEnabled: selection.count === 1
        onExtraActionTriggered: {
            facePipeline.setEventCover("day:" + dateKey, selection.paths[0])
            coverPath = selection.paths[0]
            selection.end()
        }
    }
}
