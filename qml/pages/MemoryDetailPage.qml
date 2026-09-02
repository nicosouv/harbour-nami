import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils
import "../js/scatter.js" as Scatter

// A memory's photos scattered like polaroids thrown on a table
Page {
    id: page

    // The stored memory this page shows. Its photo set was chosen by the
    // recipes and can be edited, so it is read back rather than recomputed:
    // a page that worked out its own list would show something different
    // from the card that led here.
    property int memoryId: 0
    property string title: ""

    allowedOrientations: Orientation.All

    ListModel {
        id: photosModel
    }

    PhotoShareAction { id: shareAction }
    PhotoSelection { id: selection }
    StyleLabels { id: styleLabels }

    // Where each polaroid lands, in fractions of the table's width. Not a
    // binding: it is recomputed when the photo set changes, and never
    // because the phone turned.
    property var scatter: Scatter.layout(0)

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || memoryId <= 0) return

        photosModel.clear()

        // Already in playback order, and already without the photos the user
        // took out of the clip
        var photos = facePipeline.getMemoryPhotos(memoryId, true)

        // Before the model is filled, not after: a delegate is created the
        // moment its row appears, and one created against the previous
        // layout lands in the wrong place and then jumps
        scatter = Scatter.layout(photos.length)

        for (var i = 0; i < photos.length; i++) {
            var photo = photos[i]
            photosModel.append({
                file_path: photo.file_path,
                timestamp: photo.timestamp,
                caption: photo.timestamp
                    ? Qt.formatDate(new Date(photo.timestamp * 1000), "d MMM yyyy")
                    : ""
            })
        }
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
        for (var i = 0; i < photosModel.count; i++) {
            // From a click handler, never a binding
            paths.push(photosModel.get(i).file_path)
        }
        return paths
    }

    // The edit, composed on demand. Not stored: it is a pure function of the
    // photos, the style and the track, so keeping a copy would only give it
    // a chance to go stale.
    property var edit: null
    property string style: ""

    // Where the exported clip was written, empty until there is one. Read
    // from the memory rather than remembered from the export: the file can
    // be deleted from the gallery, and the app must not go on offering it.
    property string videoPath: ""

    // 0 to 1 while a clip is being written. The export runs on a worker and
    // survives leaving the page, so this page reports it rather than owning
    // it.
    property real exportProgress: 0

    readonly property bool exporting: facePipeline && facePipeline.exportingVideo

    function loadClip() {
        if (!facePipeline || !facePipeline.initialized || memoryId <= 0) return

        var memory = facePipeline.getMemory(memoryId)
        style = memory.style || ""
        videoPath = memory.video_path || ""

        var composed = facePipeline.composeMemoryClip(memoryId)
        edit = (composed && composed.shots && composed.shots.length > 0) ? composed : null
    }

    // The clip as a file, which is the only form of it anybody else can
    // watch. Minutes of work on a phone, so the page says so and stays
    // usable while it happens.
    function saveVideo() {
        clipPlayer.pause()
        exportProgress = 0
        if (!facePipeline.exportMemoryVideo(memoryId, page.title)) {
            banner.show(qsTr("Could not start saving the video"))
        }
    }

    Connections {
        target: facePipeline

        onVideoExportProgress: {
            if (memoryId === page.memoryId) {
                page.exportProgress = progress
            }
        }

        onVideoExportFinished: {
            if (memoryId !== page.memoryId) return
            page.videoPath = path
            banner.show(qsTr("Video saved to %1").arg(path))
        }

        onVideoExportFailed: {
            if (memoryId !== page.memoryId) return
            // An empty message is the export having been called off, which
            // the user already knows about
            if (error.length > 0) {
                banner.show(qsTr("Could not save the video"))
                console.warn("Memory video export failed:", error)
            }
        }
    }

    // Written down straight away rather than on leaving the page: trying a
    // style is a choice, and a choice that survives only until you navigate
    // away is one the user has to make again every time
    function chooseStyle(styleId) {
        if (styleId === style) return
        facePipeline.setMemoryStyle(memoryId, styleId)
        clipPlayer.pause()
        loadClip()
    }

    function renameMemory() {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/RenamePersonDialog.qml"), {
            currentName: page.title,
            titleText: qsTr("Rename memory")
        })
        dialog.accepted.connect(function () {
            if (facePipeline.renameMemory(memoryId, dialog.newName)) {
                page.title = dialog.newName
            }
        })
    }

    function editPhotos() {
        var editor = pageStack.push(Qt.resolvedUrl("MemoryEditPage.qml"), {
            memoryId: memoryId,
            memoryTitle: page.title
        })
        editor.changed.connect(function () {
            loadPhotos()
            loadClip()
        })
    }

    function hideMemory() {
        Remorse.popupAction(page, qsTr("Hiding %1").arg(page.title), function () {
            facePipeline.setMemoryDismissed(memoryId, true)
            pageStack.pop()
        })
    }

    Component.onCompleted: {
        loadPhotos()
        loadClip()
    }

    // Leaving the page must stop the music, or it plays on under whatever
    // comes next
    onStatusChanged: {
        if (status === PageStatus.Deactivating) {
            clipPlayer.pause()
        }
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: header.height + stage.height + table.height + Theme.paddingLarge * 2

        PullDownMenu {
            MenuItem {
                text: qsTr("Hide this memory")
                visible: !page.exporting
                onClicked: hideMemory()
            }
            MenuItem {
                text: qsTr("Share video")
                visible: page.videoPath.length > 0 && !page.exporting
                onClicked: shareAction.shareFile(page.videoPath)
            }
            MenuItem {
                // Absent rather than disabled when the device has no
                // encoder: an item that can never do anything is one the
                // user is invited to keep trying
                text: page.videoPath.length > 0 ? qsTr("Save the video again")
                                                : qsTr("Save as video")
                visible: !page.exporting && page.edit !== null
                         && facePipeline && facePipeline.canExportVideo()
                onClicked: saveVideo()
            }
            MenuItem {
                text: qsTr("Stop saving")
                visible: page.exporting
                onClicked: facePipeline.cancelMemoryVideo()
            }
            MenuItem {
                text: qsTr("Edit photos")
                enabled: photosModel.count > 0
                visible: !page.exporting
                onClicked: editPhotos()
            }
            MenuItem {
                text: qsTr("Rename")
                visible: !page.exporting
                onClicked: renameMemory()
            }
            MenuItem {
                text: qsTr("Select photos")
                enabled: photosModel.count > 0 && !selection.active
                visible: !page.exporting
                onClicked: selection.begin("")
            }
        }

        PageHeader {
            id: header
            // Which section this page belongs to, in the space the
            // right-aligned title leaves free
            SectionMark {
                section: "memories"
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
            }

            title: page.title
            description: photosModel.count + " " + (photosModel.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        // The clip, above the photos it was made from
        Item {
            id: stage
            anchors.top: header.bottom
            width: parent.width
            height: page.edit
                    ? width / page.edit.aspect + styleRow.height + Theme.paddingLarge
                    : 0
            visible: page.edit !== null

            MemoryPlayer {
                id: clipPlayer
                width: parent.width
                height: page.edit ? width / page.edit.aspect : 0
                edit: page.edit
            }

            MouseArea {
                anchors.fill: clipPlayer
                onClicked: clipPlayer.playing ? clipPlayer.pause() : clipPlayer.play()
            }

            // Only shown while stopped: a control sitting over a playing clip
            // is a control sitting over the thing you asked to look at
            Rectangle {
                anchors.centerIn: clipPlayer
                width: Theme.itemSizeLarge
                height: width
                radius: width / 2
                color: Theme.rgba("black", 0.45)
                visible: !clipPlayer.playing

                Image {
                    anchors.centerIn: parent
                    source: "image://theme/icon-l-play?#ffffff"
                    width: Theme.iconSizeLarge
                    height: width
                    sourceSize.width: width
                    sourceSize.height: height
                }
            }

            // A plain line rather than a slider: this is a preview, and the
            // clip is a minute long
            Rectangle {
                id: progressLine
                anchors {
                    left: parent.left
                    right: parent.right
                    top: clipPlayer.bottom
                }
                height: 2
                color: Theme.rgba(Theme.secondaryColor, 0.3)

                Rectangle {
                    height: parent.height
                    color: Theme.highlightColor
                    width: clipPlayer.durationMs > 0
                           ? parent.width * clipPlayer.positionMs / clipPlayer.durationMs
                           : 0
                }
            }

            // The styles, under the thing they change. Picking one recomposes
            // and plays it: a style is a decision you make by watching it,
            // not by reading its name.
            Row {
                id: styleRow
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    top: progressLine.bottom
                    topMargin: Theme.paddingSmall
                }
                spacing: Theme.paddingMedium

                Repeater {
                    model: facePipeline && facePipeline.initialized
                           ? facePipeline.memoryStyles() : []

                    FilterChip {
                        text: styleLabels.name(modelData.id)
                        selected: page.style === modelData.id
                        onClicked: page.chooseStyle(modelData.id)
                    }
                }
            }
        }

        // The "table" the polaroids land on
        Item {
            id: table
            anchors.top: stage.visible ? stage.bottom : header.bottom
            width: parent.width

            // Worked out once per photo count and held in fractions of the
            // width, so turning the phone rescales the same heap instead of
            // dealing a new one
            height: page.scatter.height * width

            Repeater {
                model: photosModel

                // One polaroid: white frame, photo, handwritten-style caption
                delegate: Item {
                    id: polaroid

                    property var place: page.scatter.items[index]
                                        || { x: 0, y: 0, w: 0.4, h: 0.48, rotation: 0 }

                    width: place.w * table.width
                    height: place.h * table.width
                    x: place.x * table.width
                    y: place.y * table.width
                    rotation: place.rotation
                    z: index

                    // Thrown-on-the-table entrance
                    opacity: 0
                    scale: 1.35
                    Component.onCompleted: dropAnimation.start()

                    SequentialAnimation {
                        id: dropAnimation
                        // Staggered, but capped: at forty photos a fixed
                        // step per print meant five seconds of waiting for
                        // the pile to finish landing
                        PauseAnimation { duration: Math.min(index * 70, 1600) }
                        ParallelAnimation {
                            NumberAnimation {
                                target: polaroid; property: "opacity"
                                to: 1; duration: 260; easing.type: Easing.OutQuad
                            }
                            NumberAnimation {
                                target: polaroid; property: "scale"
                                to: 1; duration: 320; easing.type: Easing.OutBack
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "white"
                        radius: 2

                        // Cheap drop shadow
                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 3
                            anchors.leftMargin: 3
                            z: -1
                            color: Theme.rgba("black", 0.35)
                            radius: 2
                        }

                        Image {
                            id: polaroidPhoto
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: parent.width * 0.05
                            }
                            height: parent.height - parent.width * 0.24
                            source: FaceUtils.thumbUrl(model.file_path)
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
                        }

                        Label {
                            anchors {
                                top: polaroidPhoto.bottom
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                            }
                            text: model.caption
                            color: "#444444"
                            font.italic: true
                            // Scaled to the print rather than fixed: rows
                            // now hold two to four, so a print can be half
                            // the width of the one above it and a fixed
                            // size would run a date off the edge
                            font.pixelSize: Math.max(Theme.fontSizeTiny,
                                                     Math.min(Theme.fontSizeExtraSmall,
                                                              polaroid.width * 0.11))
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: selection.active
                        color: selection.isSelected(model.file_path)
                               ? Theme.rgba(Theme.highlightBackgroundColor, 0.5)
                               : Theme.rgba("black", 0.4)
                        z: 90

                        Icon {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-acknowledge"
                            opacity: selection.isSelected(model.file_path) ? 1 : 0.25
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: 95
                        onClicked: {
                            if (selection.active) {
                                selection.toggle(model.file_path)
                                return
                            }
                            page.openViewer(model.file_path)
                        }
                        onPressAndHold: {
                            if (!selection.active) {
                                selection.begin(model.file_path)
                            } else {
                                selection.toggle(model.file_path)
                            }
                        }
                    }
                }
            }
        }

        ViewPlaceholder {
            enabled: photosModel.count === 0
            text: qsTr("No photos")
        }

        VerticalScrollDecorator {}
    }

    // What the export is doing, over the clip it is drawing. A line and a
    // count of nothing: the numbers a person can act on are how far along it
    // is and that it can be stopped, and the pull-down holds the second one.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: exportColumn.height + 2 * Theme.paddingLarge
        color: Theme.rgba(Theme.highlightDimmerColor, 0.95)
        visible: page.exporting
        z: 150

        Column {
            id: exportColumn
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Theme.horizontalPageMargin
                rightMargin: Theme.horizontalPageMargin
            }
            spacing: Theme.paddingMedium

            Label {
                width: parent.width
                text: qsTr("Saving the video, %1%").arg(Math.round(page.exportProgress * 100))
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                truncationMode: TruncationMode.Fade
            }

            Rectangle {
                width: parent.width
                height: 2
                color: Theme.rgba(Theme.secondaryColor, 0.3)

                Rectangle {
                    height: parent.height
                    width: parent.width * page.exportProgress
                    color: Theme.highlightColor
                }
            }
        }
    }

    InfoBanner {
        id: banner
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingLarge
        z: 200
    }

    PhotoSelectionBar {
        id: selectionBar
        photoSelection: selection
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        z: 200
        onShareRequested: {
            if (shareAction.sharePhotos(selection.paths)) selection.end()
        }
    }
}
