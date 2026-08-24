import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

/*
 * Confirming a suggestion is a yes/no question, so it gets a yes/no screen:
 * one face at a time, large enough to actually recognise.
 *
 * Judging the same thing from a grid of thumbnails does not work - in a group
 * shot at a third of the screen width the face is a couple of dozen pixels,
 * and the honest answer to "is this them?" is "I cannot tell".
 */
Page {
    id: page

    property int personId: -1
    property string personName: ""

    // Entries from getPersonPhotos() that are still unverified
    property var pending: []
    property int currentIndex: 0

    readonly property var current: (currentIndex >= 0 && currentIndex < pending.length)
        ? pending[currentIndex] : null
    readonly property bool done: current === null

    // Whether anything was decided, so the caller knows to reload
    property bool changed: false

    allowedOrientations: Orientation.All

    function load() {
        if (!facePipeline || !facePipeline.initialized || personId < 0) return

        var all = facePipeline.getPersonPhotos(personId)
        var unverified = []
        for (var i = 0; i < all.length; i++) {
            if (all[i].verified !== true) {
                unverified.push(all[i])
            }
        }
        pending = unverified
        currentIndex = 0
    }

    // Moves on without re-fetching: the list was captured up front, and
    // re-reading it after every decision would renumber the queue underfoot.
    function next() {
        currentIndex = currentIndex + 1
    }

    function confirmCurrent() {
        if (!current) return
        if (facePipeline.confirmFace(current.face_id)) {
            changed = true
        }
        next()
    }

    function rejectCurrent() {
        if (!current) return
        if (facePipeline.removePersonFromPhoto(personId, current.photo_id)) {
            changed = true
        }
        next()
    }

    Component.onCompleted: load()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            SectionHeader {
                section: "people"
                title: personName
                description: page.done
                    ? qsTr("Nothing left to confirm")
                    : qsTr("%1 of %2").arg(currentIndex + 1).arg(pending.length)
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.done
                text: qsTr("Is this %1?").arg(personName)
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.highlightColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // The face, as large as the screen allows
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 2 * Theme.horizontalPageMargin,
                                page.height * 0.42)
                height: width
                visible: !page.done

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                }

                Image {
                    id: faceImage
                    anchors.fill: parent
                    source: current
                        ? FaceUtils.cropUrl(current.file_path,
                                            current.bbox_x, current.bbox_y,
                                            current.bbox_width, current.bbox_height,
                                            false)
                        : ""
                    sourceSize.width: 512
                    sourceSize.height: 512
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            // The whole photo underneath: the crop says who, the photo says
            // where, and sometimes only the context settles it
            BackgroundItem {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: Theme.itemSizeExtraLarge
                visible: !page.done
                onClicked: {
                    if (current) {
                        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                            photoPath: current.file_path
                        })
                    }
                }

                Image {
                    anchors.fill: parent
                    source: current ? FaceUtils.thumbUrl(current.file_path) : ""
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    rotation: current ? (current.rotation || 0) : 0
                    asynchronous: true
                    clip: true
                    sourceSize.width: 600
                    sourceSize.height: 600
                }

                Label {
                    anchors {
                        right: parent.right
                        bottom: parent.bottom
                        margins: Theme.paddingSmall
                    }
                    text: qsTr("See the whole photo")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.primaryColor
                }
            }

            // Yes / no, weighted equally: nudging towards either answer is
            // how a library fills up with wrong matches
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge
                visible: !page.done

                Button {
                    text: qsTr("Not them")
                    onClicked: page.rejectCurrent()
                }

                Button {
                    text: qsTr("Yes")
                    onClicked: page.confirmCurrent()
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.done
                text: qsTr("Skip")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    onClicked: page.next()
                }
            }

            ViewPlaceholder {
                enabled: page.done
                text: pending.length > 0 ? qsTr("All done") : qsTr("Nothing left to confirm")
                hintText: qsTr("Every match for this person has been confirmed")
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator {}
    }
}
