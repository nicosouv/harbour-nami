import QtQuick 2.0
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property int totalPeople: 0
    property int totalPhotos: 0

    function refreshStats() {
        if (facePipeline && facePipeline.initialized) {
            var stats = facePipeline.getStatistics()
            totalPeople = stats.total_people || 0
            totalPhotos = stats.total_photos || 0
        }
    }

    onStatusChanged: {
        if (status === Cover.Active) {
            refreshStats()
        }
    }

    Component.onCompleted: refreshStats()

    Connections {
        target: facePipeline
        onScanCompleted: refreshStats()
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium

        Image {
            id: icon
            anchors.horizontalCenter: parent.horizontalCenter
            source: "image://theme/icon-l-image"
            width: Theme.iconSizeLarge
            height: Theme.iconSizeLarge
        }

        Label {
            id: appName
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nami"
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.primaryColor
        }

        Label {
            id: statusLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: facePipeline && facePipeline.processing
                ? qsTr("Scanning...")
                : qsTr("%n people", "", totalPeople)
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }

        Label {
            id: photosLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: facePipeline && facePipeline.processing
                ? qsTr("%1 / %2").arg(facePipeline.processedPhotos).arg(facePipeline.totalPhotos)
                : qsTr("%n photos", "", totalPhotos)
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
        }
    }
}
