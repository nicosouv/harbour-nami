import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property int totalPeople: 0
    property int totalPhotos: 0

    property var coverPhotos: []
    property var dateToTripName: ({})
    property int currentIndex: 0
    property int nextIndex: 0
    property real frontRotation: -2

    function refreshStats() {
        if (facePipeline && facePipeline.initialized) {
            var stats = facePipeline.getStatistics()
            totalPeople = stats.total_people || 0
            totalPhotos = stats.total_photos || 0
        }
    }

    // Trip name when the photo's date belongs to a trip, else its date
    function labelFor(photo) {
        if (!photo) return ""
        var d = new Date(photo.timestamp * 1000)
        var key = Qt.formatDate(d, "yyyy-MM-dd")
        return dateToTripName[key] || Qt.formatDate(d, "d MMM yyyy")
    }

    function loadCoverPhotos() {
        if (!facePipeline || !facePipeline.initialized) return

        var trips = facePipeline.getTrips()
        var map = {}
        for (var t = 0; t < trips.length; t++) {
            for (var d = 0; d < trips[t].date_keys.length; d++) {
                map[trips[t].date_keys[d]] = trips[t].name
            }
        }
        dateToTripName = map

        var photos = facePipeline.getCoverPhotos(24)
        // Shuffle so the rotation isn't the same order every time the cover loads
        for (var i = photos.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1))
            var tmp = photos[i]
            photos[i] = photos[j]
            photos[j] = tmp
        }
        coverPhotos = photos
        currentIndex = 0
        nextIndex = photos.length > 1 ? 1 : 0
    }

    function advance() {
        if (coverPhotos.length < 2) return
        currentIndex = nextIndex
        nextIndex = (nextIndex + 1) % coverPhotos.length
        frontRotation = (Math.random() * 8) - 4
    }

    onStatusChanged: {
        if (status === Cover.Active) {
            refreshStats()
            if (coverPhotos.length === 0) {
                loadCoverPhotos()
            }
            rotateTimer.restart()
        } else {
            rotateTimer.stop()
        }
    }

    Component.onCompleted: {
        refreshStats()
        loadCoverPhotos()
    }

    Connections {
        target: facePipeline
        onScanCompleted: {
            refreshStats()
            loadCoverPhotos()
        }
    }

    Timer {
        id: rotateTimer
        interval: 4500
        repeat: true
        running: false
        onTriggered: swapAnimation.restart()
    }

    SequentialAnimation {
        id: swapAnimation
        NumberAnimation { target: photoContent; property: "opacity"; to: 0; duration: 350; easing.type: Easing.InQuad }
        ScriptAction { script: cover.advance() }
        NumberAnimation { target: photoContent; property: "opacity"; to: 1; duration: 350; easing.type: Easing.OutQuad }
    }

    // Polaroid photo stack: two static back cards plus the live front card
    Item {
        id: stack
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height) * 0.6
        height: width * 1.2
        visible: coverPhotos.length > 0

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            rotation: -7
            color: "white"
            radius: 2
            opacity: 0.5
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            rotation: 6
            color: "white"
            radius: 2
            opacity: 0.7
        }

        Rectangle {
            id: frontCard
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            rotation: frontRotation
            color: "white"
            radius: 2

            Behavior on rotation {
                NumberAnimation { duration: 700; easing.type: Easing.OutBack }
            }

            Item {
                id: photoContent
                anchors.fill: parent
                opacity: 1

                Image {
                    id: frontImage
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: parent.width * 0.07
                    }
                    height: parent.height * 0.7
                    source: coverPhotos.length > 0 ? "file://" + coverPhotos[currentIndex].file_path : ""
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    rotation: coverPhotos.length > 0 ? (coverPhotos[currentIndex].rotation || 0) : 0
                    clip: true
                    asynchronous: true
                    sourceSize.width: 300
                    sourceSize.height: 300
                }

                Label {
                    anchors {
                        top: frontImage.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: Theme.paddingSmall
                        margins: parent.width * 0.07
                    }
                    horizontalAlignment: Text.AlignHCenter
                    text: labelFor(coverPhotos.length > 0 ? coverPhotos[currentIndex] : null)
                    color: "#333333"
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                }
            }
        }
    }

    // Before the first scan: fall back to the plain app icon
    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium
        visible: coverPhotos.length === 0

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "image://theme/icon-l-image"
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
        }

        Label {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nami"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }
    }

    Label {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: Theme.paddingMedium
        }
        text: facePipeline && facePipeline.processing
            ? qsTr("Scanning: %1 / %2").arg(facePipeline.processedPhotos).arg(facePipeline.totalPhotos)
            : (qsTr("%n people", "", totalPeople) + " · " + qsTr("%n photos", "", totalPhotos))
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
    }
}
