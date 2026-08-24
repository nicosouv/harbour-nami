import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

// Reordering and excluding a memory's photos.
//
// A separate page from the memory itself, because the two want opposite
// things: the memory scatters its photos like polaroids on a table, and an
// order you can change has to be a list you can read top to bottom.
//
// Deliberately not a timeline. What a memory needs is which photos and in
// what order; anything past that is a video editor, and this is a phone.
Page {
    id: page

    property int memoryId: 0
    property string memoryTitle: ""

    // The memory page recomposes on this rather than polling: every edit
    // here changes the clip it is showing
    signal changed()

    allowedOrientations: Orientation.All

    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || memoryId <= 0) return

        photosModel.clear()

        // Excluded photos included: taking one out has to be undoable, and
        // an editor that hides what you removed cannot offer that
        var photos = facePipeline.getMemoryPhotos(memoryId, false)
        for (var i = 0; i < photos.length; i++) {
            photosModel.append({
                photo_id: photos[i].photo_id,
                file_path: photos[i].file_path,
                included: photos[i].included
            })
        }
    }

    function toggleIncluded(index) {
        var item = photosModel.get(index)
        var wanted = !item.included

        // Never down to nothing: a memory with no photos disappears from
        // every list, and from a page that gives no way back
        if (!wanted && includedCount() <= 1) {
            return
        }

        if (facePipeline.setMemoryPhotoIncluded(memoryId, item.photo_id, wanted)) {
            photosModel.setProperty(index, "included", wanted)
            page.changed()
        }
    }

    function includedCount() {
        var count = 0
        for (var i = 0; i < photosModel.count; i++) {
            if (photosModel.get(i).included) count++
        }
        return count
    }

    function move(from, to) {
        if (to < 0 || to >= photosModel.count) return

        photosModel.move(from, to, 1)

        // The whole order is written back rather than the one pair that
        // moved: positions are only meaningful relative to each other, and
        // sending the list is what the database call expects
        var order = []
        for (var i = 0; i < photosModel.count; i++) {
            order.push(photosModel.get(i).photo_id)
        }
        facePipeline.reorderMemoryPhotos(memoryId, order)
        page.changed()
    }

    function setCover(index) {
        facePipeline.setMemoryCover(memoryId, photosModel.get(index).file_path)
        page.changed()
    }

    Component.onCompleted: loadPhotos()

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: photosModel

        header: SectionPageHeader {
            section: "memories"
            title: qsTr("Edit photos")
            description: page.memoryTitle
        }

        // A ListView, not a grid: a ContextMenu expands its item and pushes
        // the rest down, which a GridView lays out on a fixed cell height and
        // cannot do, so its menu would be drawn over the neighbouring cells
        delegate: ListItem {
            id: photoItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeLarge

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    topMargin: Theme.paddingSmall
                    bottomMargin: Theme.paddingSmall
                }
                spacing: Theme.paddingMedium

                Image {
                    id: thumb
                    width: height
                    height: parent.height
                    source: FaceUtils.thumbUrl(model.file_path)
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    clip: true
                    asynchronous: true
                    // Excluded photos stay on the page, dimmed: they are what
                    // undoing an exclusion needs
                    opacity: model.included ? 1.0 : 0.3
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - thumb.width - moveUp.width - moveDown.width
                           - 3 * Theme.paddingMedium
                    text: (index + 1) + ""
                    color: model.included ? Theme.primaryColor : Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }

                IconButton {
                    id: moveUp
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-up"
                    enabled: index > 0
                    onClicked: page.move(index, index - 1)
                }

                IconButton {
                    id: moveDown
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: "image://theme/icon-m-down"
                    enabled: index < photosModel.count - 1
                    onClicked: page.move(index, index + 1)
                }
            }

            menu: ContextMenu {
                MenuItem {
                    text: model.included ? qsTr("Leave out of the clip")
                                         : qsTr("Put back in the clip")
                    onClicked: page.toggleIncluded(index)
                }
                MenuItem {
                    text: qsTr("Use as cover")
                    enabled: model.included
                    onClicked: page.setCover(index)
                }
            }

            onClicked: page.toggleIncluded(index)
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }
}
