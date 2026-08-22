import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

/*
 * The photo is the subject, so it takes the top of the page and can be
 * zoomed in place. What the app knows about it sits right underneath,
 * always visible: no pulley menu, no panel to open first.
 *
 * Photos are browsed by swiping sideways. The pager is a ListView with no
 * cache buffer, and every photo decodes at screen size rather than at the
 * file's own megapixels, so walking a gallery holds a couple of screen-sized
 * bitmaps rather than a growing pile of full-resolution ones.
 */
Page {
    id: page

    // Browsing a list: paths plus where to start. A single photo can also be
    // handed over on its own (the review screen does that).
    property var photoPaths: []
    property int photoIndex: 0
    property string photoPath: ""

    readonly property var paths: (photoPaths && photoPaths.length > 0)
        ? photoPaths : (photoPath ? [photoPath] : [])
    readonly property string currentPath: (pager.currentIndex >= 0
                                           && pager.currentIndex < paths.length)
        ? paths[pager.currentIndex] : ""

    // User-applied rotation on top of EXIF auto-orientation, persisted
    property int userRotation: 0
    property int rotationTurns: 0

    property var details: ({})

    readonly property bool zoomed: pager.currentItem ? pager.currentItem.zoomed : false

    allowedOrientations: Orientation.All

    // The photo keeps the larger share of the screen; the rest of the page
    // scrolls up over it when the user wants the details.
    readonly property real stageHeight: isPortrait ? page.height * 0.62
                                                   : page.height * 0.78

    function rotatePhoto() {
        rotationTurns += 1
        userRotation = ((rotationTurns % 4) + 4) % 4 * 90
        if (facePipeline && facePipeline.initialized && currentPath) {
            facePipeline.setPhotoRotation(currentPath, userRotation)
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
        Clipboard.text = page.currentPath
        copyBanner.show(qsTr("File path copied"))
    }

    // Reading the details means a database lookup, and sometimes an EXIF read
    // for a photo that was never scanned. Flicking through twenty photos must
    // not do that twenty times, so it waits for the swipe to settle.
    function loadCurrentPhoto() {
        if (!facePipeline || !facePipeline.initialized || !currentPath) {
            details = ({})
            return
        }
        userRotation = facePipeline.photoRotation(currentPath)
        rotationTurns = Math.round(userRotation / 90)
        details = facePipeline.photoDetails(currentPath)
    }

    Timer {
        id: detailsSettle
        interval: 180
        onTriggered: page.loadCurrentPhoto()
    }

    onCurrentPathChanged: detailsSettle.restart()

    Component.onCompleted: {
        pager.currentIndex = Math.max(0, Math.min(photoIndex, paths.length - 1))
        loadCurrentPhoto()
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

                // Swiping sideways walks the gallery. cacheBuffer is 0 on
                // purpose: the default keeps delegates alive well past the
                // edges of the screen, which here means extra decoded photos
                // for no visible gain.
                SilicaListView {
                    id: pager
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: 200
                    cacheBuffer: 0
                    clip: true
                    model: page.paths

                    // A zoomed photo takes the drag so it can be panned; a
                    // double tap zooms back out and hands the pager back
                    interactive: !page.zoomed

                    delegate: ZoomableImage {
                        width: pager.width
                        height: pager.height
                        source: modelData ? "file://" + modelData : ""
                        // Only the photo on screen carries the user's
                        // rotation; the others are at rest anyway
                        rotationTurns: index === pager.currentIndex
                                       ? page.rotationTurns : 0
                        naturalWidthHint: index === pager.currentIndex
                                          ? (details.width || 0) : 0
                        naturalHeightHint: index === pager.currentIndex
                                           ? (details.height || 0) : 0

                        // Leaving a photo zoomed and coming back to it later
                        // would strand the pager on a photo it cannot leave
                        onVisibleChanged: if (!visible) resetZoom()
                    }
                }

                // Position in the gallery, only when there is one to be in
                Label {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        top: parent.top
                        topMargin: Theme.paddingMedium
                    }
                    visible: page.paths.length > 1
                    text: (pager.currentIndex + 1) + " / " + page.paths.length
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.highlightColor
                    opacity: 0.8
                }

                // Zoom level, only while it is not at fit size
                Label {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        bottom: parent.bottom
                        bottomMargin: Theme.paddingMedium
                    }
                    text: pager.currentItem
                          ? Math.round(pager.currentItem.zoom * 100) + "%" : ""
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
                        onClicked: if (pager.currentItem) pager.currentItem.zoomBy(1 / 1.5)
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-add"
                        enabled: pager.currentItem
                                 && pager.currentItem.zoom < pager.currentItem.maxZoom
                        onClicked: if (pager.currentItem) pager.currentItem.zoomBy(1.5)
                    }
                    IconButton {
                        icon.source: "image://theme/icon-m-refresh"
                        onClicked: {
                            page.rotatePhoto()
                            // Fitting changes with every quarter turn
                            if (pager.currentItem) pager.currentItem.resetZoom()
                        }
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
                    onClicked: shareAction.sharePhoto(page.currentPath)
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
                    text: details.file_path || page.currentPath
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
