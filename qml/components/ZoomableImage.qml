import QtQuick 2.6
import Sailfish.Silica 1.0

/*
 * One photo, fitted to this item and zoomable in place.
 *
 * Memory is the constraint here, because a pager keeps neighbours alive and a
 * phone photo can be 48 megapixels - 190 MB decoded. Three of those at once
 * is not survivable, so:
 *
 *  - sourceSize is capped to what is actually on screen. At fit size a photo
 *    costs about as much as the screen (a few MB) whatever the file holds.
 *  - it is raised once, to a bounded ceiling, only when this photo is
 *    actually zoomed, and only for this one photo.
 *  - cache is off: the viewer walks forward through a gallery and would
 *    otherwise pile decoded photos up in Qt's pixmap cache behind it.
 *
 * Panning is left to the Flickable, which is why the image is sized rather
 * than scaled: contentWidth/contentHeight then match what is actually drawn,
 * so the view cannot be panned into empty space.
 */
Item {
    id: root

    property string source: ""
    // Fallback dimensions while the image header has not been read yet
    property int naturalWidthHint: 0
    property int naturalHeightHint: 0

    // Rotation is driven by a counter that only ever grows, so going from 270
    // back to 0 turns forward instead of spinning back through 180.
    property int rotationTurns: 0
    readonly property bool quarterTurned: (rotationTurns % 2) !== 0

    property real zoom: 1.0
    readonly property real minZoom: 1.0
    readonly property real maxZoom: 6.0
    readonly property real doubleTapZoom: 2.5
    readonly property bool zoomed: zoom > minZoom + 0.01

    readonly property int status: image.status

    // Focal point of the zoom in progress: a normalised position inside the
    // photo (anchorN*) pinned to a fixed point of the viewport (anchorV*).
    // Re-applied on every zoom change, so zooming keeps whatever the user
    // aimed at under their finger instead of drifting to a corner.
    property real anchorNx: 0.5
    property real anchorNy: 0.5
    property real anchorVx: 0
    property real anchorVy: 0

    // Ceiling for the zoomed decode. Six times the screen would be sharper
    // still and cost a hundred megabytes; this keeps a zoomed photo in the
    // tens of MB while staying crisp at everyday zoom levels.
    readonly property int zoomedSourceCap: 2560

    readonly property real naturalWidth: image.implicitWidth > 0
        ? image.implicitWidth
        : (naturalWidthHint > 0 ? naturalWidthHint : width)
    readonly property real naturalHeight: image.implicitHeight > 0
        ? image.implicitHeight
        : (naturalHeightHint > 0 ? naturalHeightHint : height)

    readonly property real turnedWidth: quarterTurned ? naturalHeight : naturalWidth
    readonly property real turnedHeight: quarterTurned ? naturalWidth : naturalHeight

    readonly property real fitScale: (turnedWidth > 0 && turnedHeight > 0)
        ? Math.min(width / turnedWidth, height / turnedHeight)
        : 1
    readonly property real baseWidth: turnedWidth * fitScale
    readonly property real baseHeight: turnedHeight * fitScale

    function clamp(value, lo, hi) {
        if (hi <= lo) return lo
        return Math.max(lo, Math.min(value, hi))
    }

    function beginZoom(focusX, focusY) {
        anchorVx = focusX
        anchorVy = focusY
        anchorNx = frame.width > 0
            ? (flick.contentX + focusX - frame.x) / frame.width : 0.5
        anchorNy = frame.height > 0
            ? (flick.contentY + focusY - frame.y) / frame.height : 0.5
    }

    function applyAnchor() {
        flick.contentX = clamp(anchorNx * frame.width + frame.x - anchorVx,
                               0, flick.contentWidth - flick.width)
        flick.contentY = clamp(anchorNy * frame.height + frame.y - anchorVy,
                               0, flick.contentHeight - flick.height)
    }

    function zoomTo(newZoom, focusX, focusY) {
        beginZoom(focusX, focusY)
        zoom = clamp(newZoom, minZoom, maxZoom)
    }

    // Zoom buttons work on the middle of the stage, which is what the user is
    // looking at; anchoring them at the origin sends the view to the corner.
    function zoomBy(factor) {
        zoomTo(zoom * factor, width / 2, height / 2)
    }

    function resetZoom() {
        zoomTo(minZoom, width / 2, height / 2)
    }

    onZoomChanged: applyAnchor()

    PinchArea {
        anchors.fill: parent

        property real startZoom: 1.0

        onPinchStarted: {
            startZoom = root.zoom
            root.beginZoom(pinch.startCenter.x, pinch.startCenter.y)
        }
        onPinchUpdated: {
            root.anchorVx = pinch.center.x
            root.anchorVy = pinch.center.y
            root.zoom = root.clamp(startZoom * pinch.scale, root.minZoom, root.maxZoom)
        }

        Flickable {
            id: flick
            anchors.fill: parent
            clip: true

            // Exactly the drawn size, so panning stops at the photo's edges
            contentWidth: Math.max(width, frame.width)
            contentHeight: Math.max(height, frame.height)
            interactive: root.zoomed

            Item {
                id: frame
                width: root.baseWidth * root.zoom
                height: root.baseHeight * root.zoom
                // Centred while smaller than the viewport
                x: Math.max(0, (flick.contentWidth - width) / 2)
                y: Math.max(0, (flick.contentHeight - height) / 2)

                Image {
                    id: image
                    anchors.centerIn: parent
                    // Swapped on a quarter turn so the rotated image still
                    // lands inside the frame
                    width: root.quarterTurned ? frame.height : frame.width
                    height: root.quarterTurned ? frame.width : frame.height
                    rotation: root.rotationTurns * 90
                    source: root.source
                    fillMode: Image.PreserveAspectFit
                    autoTransform: true  // honor EXIF orientation
                    asynchronous: true
                    // See the note at the top: the viewer walks forward and
                    // must not leave decoded photos behind it
                    cache: false

                    // Two decode levels, not a continuous one: rebinding
                    // sourceSize reloads the file, so following the zoom
                    // smoothly would re-decode on every pinch frame.
                    sourceSize.width: root.zoomed
                        ? root.zoomedSourceCap : Math.ceil(root.width)
                    sourceSize.height: root.zoomed
                        ? root.zoomedSourceCap : Math.ceil(root.height)

                    Behavior on rotation {
                        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                    }
                }
            }

            // Double tap zooms in at the tapped point, or back out
            MouseArea {
                width: flick.contentWidth
                height: flick.contentHeight
                onDoubleClicked: {
                    // Mouse coordinates are in content space
                    var vx = mouse.x - flick.contentX
                    var vy = mouse.y - flick.contentY
                    root.zoomTo(root.zoomed ? root.minZoom : root.doubleTapZoom, vx, vy)
                }
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: image.status === Image.Loading
        size: BusyIndicatorSize.Large
    }

    Label {
        anchors.centerIn: parent
        visible: image.status === Image.Error
        text: qsTr("Failed to load image")
        color: Theme.secondaryColor
    }
}
