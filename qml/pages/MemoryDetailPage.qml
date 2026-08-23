import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

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

    // Deterministic pseudo-random in [0,1) so the scatter looks organic but
    // stays stable across relayouts
    function jitter(i, salt) {
        var x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453
        return x - Math.floor(x)
    }

    function loadPhotos() {
        if (!facePipeline || !facePipeline.initialized || memoryId <= 0) return

        photosModel.clear()

        // Already in playback order, and already without the photos the user
        // took out of the clip
        var photos = facePipeline.getMemoryPhotos(memoryId, true)
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
    property var clip: null

    function loadClip() {
        if (!facePipeline || !facePipeline.initialized || memoryId <= 0) return
        var composed = facePipeline.composeMemoryClip(memoryId)
        clip = (composed && composed.shots && composed.shots.length > 0) ? composed : null
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
                text: qsTr("Select photos")
                enabled: photosModel.count > 0 && !selection.active
                onClicked: selection.begin("")
            }
        }

        PageHeader {
            id: header
            title: page.title
            description: photosModel.count + " " + (photosModel.count === 1 ? qsTr("photo") : qsTr("photos"))
        }

        // The clip, above the photos it was made from
        Item {
            id: stage
            anchors.top: header.bottom
            width: parent.width
            height: page.clip ? width / page.clip.aspect + Theme.itemSizeSmall : 0
            visible: page.clip !== null

            MemoryPlayer {
                id: clipPlayer
                width: parent.width
                height: page.clip ? width / page.clip.aspect : 0
                clip: page.clip
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
                anchors {
                    left: parent.left
                    right: parent.right
                    top: clipPlayer.bottom
                    topMargin: Theme.paddingMedium
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
        }

        // The "table" the polaroids land on
        Item {
            id: table
            anchors.top: stage.visible ? stage.bottom : header.bottom
            width: parent.width
            // Two loose columns; each row eats ~55% of a polaroid height so
            // they overlap a little like a real pile
            property real polaroidWidth: width * 0.46
            property real polaroidHeight: polaroidWidth * 1.2
            property real rowStep: polaroidHeight * 0.72
            height: photosModel.count > 0
                    ? Math.ceil(photosModel.count / 2) * rowStep + polaroidHeight * 0.5
                    : 0

            Repeater {
                model: photosModel

                // One polaroid: white frame, photo, handwritten-style caption
                delegate: Item {
                    id: polaroid

                    property real jx: jitter(index, 1)
                    property real jy: jitter(index, 2)
                    property real jr: jitter(index, 3)

                    width: table.polaroidWidth
                    height: table.polaroidHeight
                    x: Theme.horizontalPageMargin
                       + (index % 2) * (table.width - table.polaroidWidth - 2 * Theme.horizontalPageMargin)
                       * (0.9 + 0.1 * jx)
                       + (index % 2 === 0 ? jx * table.width * 0.06 : -jx * table.width * 0.06)
                    y: Math.floor(index / 2) * table.rowStep + jy * table.rowStep * 0.25
                    rotation: (jr - 0.5) * 16
                    z: index

                    // Thrown-on-the-table entrance
                    opacity: 0
                    scale: 1.35
                    Component.onCompleted: dropAnimation.start()

                    SequentialAnimation {
                        id: dropAnimation
                        PauseAnimation { duration: 120 * index }
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
                            font.pixelSize: Theme.fontSizeExtraSmall
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
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
