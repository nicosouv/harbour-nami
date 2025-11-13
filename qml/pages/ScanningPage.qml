import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property string galleryPath
    property var faceManager: appWindow.faceRecognition

    allowedOrientations: Orientation.All

    // Scanning state
    property bool scanning: false
    property int currentPhoto: 0
    property int totalPhotos: 0
    property int detectedFaces: 0

    Component.onCompleted: {
        startScanning()
    }

    Connections {
        target: faceManager

        onScanProgress: {
            currentPhoto = progress.current
            totalPhotos = progress.total
        }

        onScanCompleted: {
            scanning = false
            detectedFaces = summary.total_faces
        }
    }

    function startScanning() {
        if (!faceManager || !faceManager.ready) {
            console.error("Face manager not ready")
            return
        }

        scanning = true
        currentPhoto = 0
        totalPhotos = 0
        detectedFaces = 0

        faceManager.scanGallery(galleryPath)
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: scanning ? qsTr("Scanning Gallery") : qsTr("Scan Complete")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge * 2
            }

            // Progress indicator
            BusyIndicator {
                anchors.horizontalCenter: parent.horizontalCenter
                size: BusyIndicatorSize.Large
                running: scanning
                visible: scanning
            }

            // Success icon
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                source: "image://theme/icon-l-accept"
                visible: !scanning
                width: Theme.iconSizeLarge
                height: Theme.iconSizeLarge
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Progress text
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scanning ?
                      qsTr("Processing photos...") :
                      qsTr("Gallery scan completed!")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: totalPhotos > 0 ?
                      qsTr("%1 of %2 photos").arg(currentPhoto).arg(totalPhotos) :
                      qsTr("Preparing...")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
                visible: scanning
            }

            // Progress bar
            ProgressBar {
                width: parent.width - 2 * Theme.horizontalPageMargin
                anchors.horizontalCenter: parent.horizontalCenter
                minimumValue: 0
                maximumValue: totalPhotos > 0 ? totalPhotos : 100
                value: currentPhoto
                indeterminate: totalPhotos === 0
                visible: scanning
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Results
            SectionHeader {
                text: qsTr("Results")
                visible: !scanning
            }

            DetailItem {
                label: qsTr("Photos scanned")
                value: totalPhotos
                visible: !scanning
            }

            DetailItem {
                label: qsTr("Faces detected")
                value: detectedFaces
                visible: !scanning
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Actions
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Review Unknown Faces")
                visible: !scanning && detectedFaces > 0
                onClicked: {
                    pageStack.replace(Qt.resolvedUrl("UnknownFacesPage.qml"))
                }
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Done")
                visible: !scanning
                onClicked: {
                    pageStack.pop()
                }
            }
        }
    }
}
