import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

/*
 * The photo is the subject, so it takes the top of the page and can be
 * zoomed in place. What the app knows about it sits right underneath,
 * always visible: no pulley menu, no panel to open first.
 *
 * The page scrolls as one, except while the photo is zoomed in - the photo
 * then takes the drag so it can be panned, and a double tap gives the page
 * back.
 */
Page {
    id: page

    property string photoPath: ""
    // User-applied rotation on top of EXIF auto-orientation, persisted
    property int userRotation: 0

    // Rotation is animated from a counter that only ever grows, so going from
    // 270 back to 0 turns forward instead of spinning back through 180.
    property int rotationTurns: 0
    readonly property bool quarterTurned: (rotationTurns % 2) !== 0

    // Zoom is a plain multiplier over the fit-to-viewport size. Panning is
    // left to the Flickable, which is why the image is sized rather than
    // scaled: contentWidth/contentHeight then match what is actually drawn,
    // and the view can no longer be panned into empty space.
    property real zoom: 1.0
    readonly property real minZoom: 1.0
    readonly property real maxZoom: 6.0
    readonly property real doubleTapZoom: 2.5
    readonly property bool zoomed: zoom > minZoom + 0.01

    property var details: ({})

    // Focal point of the zoom in progress: a normalised position inside the
    // photo (anchorN*) pinned to a fixed point of the viewport (anchorV*).
    // Re-applied on every zoom change, so zooming keeps whatever the user
    // aimed at under their finger instead of drifting to a corner.
    property real anchorNx: 0.5
    property real anchorNy: 0.5
    property real anchorVx: 0
    property real anchorVy: 0

    allowedOrientations: Orientation.All

    // The photo keeps the larger share of the screen; the rest of the page
    // scrolls up over it when the user wants the details.
    readonly property real stageHeight: isPortrait ? page.height * 0.62
                                                   : page.height * 0.78

    // Natural size of the photo. Image.implicitWidth already accounts for the
    // EXIF orientation applied by autoTransform; the database values are the
    // fallback while the image is still loading.
    readonly property real naturalWidth: photoImage.implicitWidth > 0
        ? photoImage.implicitWidth
        : ((details.width > 0) ? details.width : page.width)
    readonly property real naturalHeight: photoImage.implicitHeight > 0
        ? photoImage.implicitHeight
        : ((details.height > 0) ? details.height : page.height)

    // Bounding box once the user's own rotation is applied
    readonly property real turnedWidth: quarterTurned ? naturalHeight : naturalWidth
    readonly property real turnedHeight: quarterTurned ? naturalWidth : naturalHeight

    readonly property real fitScale: (turnedWidth > 0 && turnedHeight > 0)
        ? Math.min(stage.width / turnedWidth, stage.height / turnedHeight)
        : 1
    readonly property real baseWidth: turnedWidth * fitScale
    readonly property real baseHeight: turnedHeight * fitScale

    function clamp(value, lo, hi) {
        if (hi <= lo) return lo
        return Math.max(lo, Math.min(value, hi))
    }

    // Remember what the user is aiming at, in stage coordinates
    function beginZoom(focusX, focusY) {
        anchorVx = focusX
        anchorVy = focusY
        anchorNx = frame.width > 0
            ? (stage.contentX + focusX - frame.x) / frame.width : 0.5
        anchorNy = frame.height > 0
            ? (stage.contentY + focusY - frame.y) / frame.height : 0.5
    }

    function applyAnchor() {
        stage.contentX = clamp(anchorNx * frame.width + frame.x - anchorVx,
                               0, stage.contentWidth - stage.width)
        stage.contentY = clamp(anchorNy * frame.height + frame.y - anchorVy,
                               0, stage.contentHeight - stage.height)
    }

    function zoomTo(newZoom, focusX, focusY) {
        beginZoom(focusX, focusY)
        zoom = clamp(newZoom, minZoom, maxZoom)
    }

    // Zoom buttons work on the middle of the stage, which is what the user is
    // looking at; anchoring them at the origin is what used to send the view
    // off to the top-left corner.
    function zoomBy(factor) {
        zoomTo(zoom * factor, stage.width / 2, stage.height / 2)
    }

    function resetZoom() {
        zoomTo(minZoom, stage.width / 2, stage.height / 2)
    }

    function rotatePhoto() {
        rotationTurns += 1
        // Fitting changes with every quarter turn, so start from fit again
        resetZoom()
        userRotation = ((rotationTurns % 4) + 4) % 4 * 90
        if (facePipeline && facePipeline.initialized) {
            facePipeline.setPhotoRotation(photoPath, userRotation)
        }
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes < 1024) return qsTr("%1 B").arg(bytes)
        if (bytes < 1024 * 1024) return qsTr("%1 kB").arg((bytes / 1024).toFixed(0))
        return qsTr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1))
    }

    function formatCoordinate(value, positive, negative) {
        return Math.abs(value).toFixed(4) + "° " + (value >= 0 ? positive : negative)
    }

    function copyPath() {
        Clipboard.text = page.photoPath
        copyBanner.show(qsTr("File path copied"))
    }

    onZoomChanged: applyAnchor()

    Component.onCompleted: {
        if (facePipeline && facePipeline.initialized && photoPath) {
            userRotation = facePipeline.photoRotation(photoPath)
            rotationTurns = Math.round(userRotation / 90)
            details = facePipeline.photoDetails(photoPath)
        }
    }

    PhotoShareAction { id: shareAction }

    SilicaFlickable {
        id: pageFlick
        anchors.fill: parent
        contentHeight: content.height
        // While the photo is zoomed it takes the drag for panning
        interactive: !page.zoomed

        Column {
            id: content
            width: parent.width

            // ---- the photo ------------------------------------------------
            Item {
                id: stageArea
                width: parent.width
                height: page.stageHeight

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightDimmerColor, 0.25)
                }

                PinchArea {
                    anchors.fill: parent

                    property real startZoom: 1.0

                    onPinchStarted: {
                        startZoom = page.zoom
                        page.beginZoom(pinch.startCenter.x, pinch.startCenter.y)
                    }
                    onPinchUpdated: {
                        page.anchorVx = pinch.center.x
                        page.anchorVy = pinch.center.y
                        page.zoom = page.clamp(startZoom * pinch.scale,
                                               page.minZoom, page.maxZoom)
                    }

                    Flickable {
                        id: stage
                        anchors.fill: parent
                        clip: true

                        // Exactly the drawn size, so panning stops at the edges
                        contentWidth: Math.max(width, frame.width)
                        contentHeight: Math.max(height, frame.height)
                        interactive: page.zoomed

                        Item {
                            id: frame
                            width: page.baseWidth * page.zoom
                            height: page.baseHeight * page.zoom
                            // Centred while smaller than the viewport
                            x: Math.max(0, (stage.contentWidth - width) / 2)
                            y: Math.max(0, (stage.contentHeight - height) / 2)

                            Image {
                                id: photoImage
                                anchors.centerIn: parent
                                // Swapped on a quarter turn so the rotated
                                // image still lands inside the frame
                                width: page.quarterTurned ? frame.height : frame.width
                                height: page.quarterTurned ? frame.width : frame.height
                                rotation: page.rotationTurns * 90
                                source: photoPath ? "file://" + photoPath : ""
                                fillMode: Image.PreserveAspectFit
                                autoTransform: true  // honor EXIF orientation
                                asynchronous: true

                                Behavior on rotation {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                }
                            }
                        }

                        // Double tap zooms in at the tapped point, or back out
                        MouseArea {
                            width: stage.contentWidth
                            height: stage.contentHeight
                            onDoubleClicked: {
                                // Mouse coordinates are in content space
                                var vx = mouse.x - stage.contentX
                                var vy = mouse.y - stage.contentY
                                page.zoomTo(page.zoomed ? page.minZoom
                                                        : page.doubleTapZoom, vx, vy)
                            }
                        }
                    }
                }

                BusyIndicator {
                    anchors.centerIn: parent
                    running: photoImage.status === Image.Loading
                    size: BusyIndicatorSize.Large
                }

                Label {
                    anchors.centerIn: parent
                    visible: photoImage.status === Image.Error
                    text: qsTr("Failed to load image")
                    color: Theme.secondaryColor
                }

                // Zoom level, only while it is not at fit size
                Label {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        bottom: parent.bottom
                        bottomMargin: Theme.paddingMedium
                    }
                    text: Math.round(page.zoom * 100) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.highlightColor
                    opacity: page.zoomed ? 0.9 : 0
                    Behavior on opacity { FadeAnimation { duration: 200 } }
                }

                // Photo controls, kept on the image itself
                Row {
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        bottom: parent.bottom
                        bottomMargin: Theme.paddingMedium
                    }
                    spacing: Theme.paddingMedium

                    IconButton {
                        icon.source: "image://theme/icon-m-remove"
                        enabled: page.zoomed
                        onClicked: page.zoomBy(1 / 1.5)
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-add"
                        enabled: page.zoom < page.maxZoom
                        onClicked: page.zoomBy(1.5)
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-refresh"
                        onClicked: page.rotatePhoto()
                    }
                }
            }

            // ---- what we know about it ------------------------------------
            Item { width: 1; height: Theme.paddingLarge }

            // File name on the left, share on the right
            Item {
                width: parent.width
                height: Math.max(nameLabel.height, shareButton.height)

                Label {
                    id: nameLabel
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: shareButton.left
                        rightMargin: Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }
                    text: details.file_name || ""
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                }

                IconButton {
                    id: shareButton
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }
                    icon.source: "image://theme/icon-m-share"
                    onClicked: shareAction.sharePhoto(page.photoPath)
                }
            }

            Item { width: 1; height: Theme.paddingMedium }

            DetailItem {
                width: parent.width
                label: qsTr("Taken")
                visible: (details.timestamp || 0) > 0
                value: (details.timestamp || 0) > 0
                       ? Qt.formatDateTime(new Date(details.timestamp * 1000),
                                           Qt.DefaultLocaleShortDate)
                       : ""
            }

            DetailItem {
                width: parent.width
                label: qsTr("Size")
                visible: (details.width || 0) > 0 || (details.file_size || 0) > 0
                value: {
                    var parts = []
                    if ((details.width || 0) > 0 && (details.height || 0) > 0) {
                        parts.push(details.width + " × " + details.height)
                    }
                    var bytes = formatSize(details.file_size || 0)
                    if (bytes.length > 0) {
                        parts.push(bytes)
                    }
                    return parts.join("  ·  ")
                }
            }

            DetailItem {
                width: parent.width
                label: qsTr("Location")
                visible: details.has_location === true
                value: details.has_location === true
                       ? formatCoordinate(details.latitude, qsTr("N"), qsTr("S"))
                         + ", " + formatCoordinate(details.longitude, qsTr("E"), qsTr("W"))
                       : ""
            }

            Item { width: 1; height: Theme.paddingMedium; visible: details.has_location === true }

            // Where the photo was taken, on the same offline sketch map the
            // trips use. Zoomed far out by default so the coastline says which
            // part of the world this is; tap to zoom in.
            TripRouteMap {
                id: locationMap
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                minPoints: 1
                minSpanKm: wideView ? 1500 : 20

                property bool wideView: true

                points: details.has_location === true
                        ? [{ latitude: details.latitude,
                             longitude: details.longitude }]
                        : []

                MouseArea {
                    anchors.fill: parent
                    onClicked: locationMap.wideView = !locationMap.wideView
                }
            }

            // ---- the file -------------------------------------------------
            SectionHeader {
                width: parent.width
                text: qsTr("File")
            }

            // Path on the left, copy on the right
            Item {
                width: parent.width
                height: Math.max(pathLabel.height, copyButton.height) + Theme.paddingSmall

                Label {
                    id: pathLabel
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: copyButton.left
                        rightMargin: Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }
                    text: details.file_path || page.photoPath
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryHighlightColor
                    wrapMode: Text.WrapAnywhere
                }

                IconButton {
                    id: copyButton
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }
                    icon.source: "image://theme/icon-m-clipboard"
                    onClicked: page.copyPath()
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: details.in_library === false
                text: qsTr("Not in the Nami library")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }

            Item { width: 1; height: Theme.paddingLarge }
        }

        VerticalScrollDecorator {}
    }

    InfoBanner {
        id: copyBanner
        anchors.top: parent.top
        anchors.topMargin: Theme.paddingLarge
        z: 100
    }
}
