import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils
import "../js/eventsettings.js" as EventSettings
import "../js/mosaic.js" as Mosaic

// All photos taken on a given day (opened from the Events page)
Page {
    id: page

    property string dateKey: ""   // yyyy-MM-dd
    property string title: ""
    property string coverPath: ""

    // Plain arrays: the mosaic needs a computed width and height per photo,
    // which are not model roles
    property var photos: []
    property var photoRows: []

    allowedOrientations: Orientation.All

    PhotoShareAction { id: shareAction }
    PhotoSelection { id: selection }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || dateKey.length === 0) return

        coverPath = facePipeline.getEventCovers()["day:" + dateKey] || ""

        // Collect the day's photos across every person, deduplicated
        var seen = {}
        var items = []
        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            var personPhotos = facePipeline.getPersonPhotos(people[i].person_id)
            for (var j = 0; j < personPhotos.length; j++) {
                var photo = personPhotos[j]
                if (!photo.timestamp || seen[photo.file_path]) continue
                var key = Qt.formatDate(new Date(photo.timestamp * 1000), "yyyy-MM-dd")
                if (key === dateKey) {
                    seen[photo.file_path] = true
                    items.push({
                        file_path: photo.file_path,
                        timestamp: photo.timestamp,
                        width: photo.width,
                        height: photo.height,
                        rotation: photo.rotation
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
                        timestamp: extraPhoto.timestamp,
                        width: extraPhoto.width,
                        height: extraPhoto.height,
                        rotation: extraPhoto.rotation
                    })
                }
            }
        }

        items.sort(function(a, b) { return a.timestamp - b.timestamp })
        photos = items
        rebuildRows()
    }

    // Built once per opening: the viewer browses the whole list, so the
    // tapped photo is just where it starts.
    function openViewer(path) {
        var paths = browsePaths()
        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
            photoPaths: paths,
            photoIndex: Math.max(0, paths.indexOf(path))
        })
    }

    function browsePaths() {
        var paths = []
        for (var i = 0; i < photos.length; i++) {
            paths.push(photos[i].file_path)
        }
        return paths
    }

    function rebuildRows() {
        var avail = photoList.width - 2 * Theme.horizontalPageMargin
        if (avail <= 0) {
            photoRows = []
            return
        }
        photoRows = Mosaic.layout(photos, avail, avail / 3, Theme.paddingSmall)
    }

    Component.onCompleted: {
        loadPhotos()
    }

    // A list of mosaic rows rather than a grid of squares: photos keep their
    // own shape, and the view still only builds the rows on screen. A grid
    // could not do this - it lays every cell out on one fixed size.
    SilicaListView {
        id: photoList
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: selectionBar.top
        }
        clip: true
        spacing: Theme.paddingSmall

        model: photoRows
        onWidthChanged: page.rebuildRows()

        PullDownMenu {
            MenuItem {
                text: qsTr("Select photos")
                enabled: photos.length > 0 && !selection.active
                onClicked: selection.begin("")
            }
        }

        header: PageHeader {
            title: page.title
            description: photos.length + " "
                         + (photos.length === 1 ? qsTr("photo") : qsTr("photos"))
        }

        delegate: Row {
            id: photoRow
            x: Theme.horizontalPageMargin
            spacing: Theme.paddingSmall
            property var cells: modelData

            Repeater {
                model: photoRow.cells

                delegate: ListItem {
                    id: photoItem

                    property var photo: modelData.photo

                    width: modelData.width
                    contentHeight: modelData.height

                    contentItem.children: [
                        Image {
                            anchors.fill: parent
                            source: FaceUtils.thumbUrl(photoItem.photo.file_path)
                            fillMode: Image.PreserveAspectCrop
                            autoTransform: true
                            rotation: photoItem.photo.rotation || 0
                            clip: true
                            asynchronous: true
                            sourceSize.width: 500
                            sourceSize.height: 500

                            Rectangle {
                                anchors.fill: parent
                                visible: parent.status !== Image.Ready
                                color: Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                            }

                            // Selection state
                            Rectangle {
                                anchors.fill: parent
                                visible: selection.active
                                color: selection.isSelected(photoItem.photo.file_path)
                                       ? Theme.rgba(Theme.highlightBackgroundColor, 0.45)
                                       : Theme.rgba("black", 0.35)
                                z: 90

                                Icon {
                                    anchors.centerIn: parent
                                    source: "image://theme/icon-m-acknowledge"
                                    opacity: selection.isSelected(photoItem.photo.file_path)
                                             ? 1 : 0.25
                                }
                            }

                            // Marks the photo currently used as this day's cover
                            Rectangle {
                                visible: photoItem.photo.file_path === coverPath
                                anchors {
                                    top: parent.top
                                    right: parent.right
                                    margins: Theme.paddingSmall
                                }
                                width: Theme.iconSizeSmall
                                height: width
                                radius: width / 2
                                color: Theme.rgba("#FFC107", 0.95)
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
                            selection.toggle(photoItem.photo.file_path)
                            return
                        }
                        page.openViewer(photoItem.photo.file_path)
                    }

                    // Long press picks photos, the way a gallery does. An
                    // inline ContextMenu is not an option in a list of rows:
                    // it would open under the whole row, not the photo.
                    onPressAndHold: {
                        if (!selection.active) {
                            selection.begin(photoItem.photo.file_path)
                        } else {
                            selection.toggle(photoItem.photo.file_path)
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: photos.length === 0
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
