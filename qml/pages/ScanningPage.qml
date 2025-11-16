import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    // State
    property int currentPhoto: 0
    property int totalPhotos: 0
    property int facesDetected: 0
    property bool scanning: true

    Component.onCompleted: {
        // Start scanning
        facePipeline.scanGallery(defaultGalleryPath, true)
    }

    Connections {
        target: facePipeline

        onScanProgress: {
            currentPhoto = current
            totalPhotos = total
        }

        onPhotoProcessed: {
            if (result.success) {
                facesDetected += result.facesDetected
            }
        }

        onScanCompleted: {
            scanning = false
            facesDetected = facesDetected
            // Navigate to results page
            pageStack.replace(Qt.resolvedUrl("ScanResultsPage.qml"), {
                photosProcessed: photosProcessed,
                facesDetected: facesDetected
            })
        }
    }

    // Gradient background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0a192f" }
            GradientStop { position: 1.0; color: "#172a45" }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge * 2

            // Spacer
            Item {
                width: parent.width
                height: Theme.paddingLarge * 4
            }

            // Animated circle progress
            Item {
                width: parent.width
                height: Theme.itemSizeHuge * 2

                // Outer glow circle
                Rectangle {
                    anchors.centerIn: parent
                    width: Theme.itemSizeHuge * 1.8
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: "#64ffda"
                    border.width: 2
                    opacity: 0.3

                    SequentialAnimation on opacity {
                        running: scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.8; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 0.3; duration: 1000; easing.type: Easing.InOutQuad }
                    }

                    SequentialAnimation on scale {
                        running: scanning
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.1; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutQuad }
                    }
                }

                // Main circle
                Rectangle {
                    id: mainCircle
                    anchors.centerIn: parent
                    width: Theme.itemSizeHuge * 1.5
                    height: width
                    radius: width / 2
                    color: Qt.rgba(0.39, 1, 0.85, 0.1)
                    border.color: "#64ffda"
                    border.width: 3

                    // Progress arc (simulated with rotation)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 20
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.color: "#64ffda"
                        border.width: 8
                        opacity: 0.6

                        rotation: totalPhotos > 0 ? (currentPhoto / totalPhotos) * 360 : 0

                        Behavior on rotation {
                            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                        }
                    }

                    // Center content
                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: totalPhotos > 0 ? currentPhoto : "0"
                            font.pixelSize: Theme.fontSizeHuge * 1.5
                            font.bold: true
                            color: "#64ffda"
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: totalPhotos > 0 ? "/ " + totalPhotos : "..."
                            font.pixelSize: Theme.fontSizeLarge
                            color: "#8892b0"
                        }
                    }
                }
            }

            // Title
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: scanning ? qsTr("Scanning Gallery") : qsTr("Scan Complete")
                font.pixelSize: Theme.fontSizeExtraLarge
                font.bold: true
                color: "#ccd6f6"
            }

            // Subtitle
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - Theme.horizontalPageMargin * 4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: scanning ?
                      (totalPhotos > 0 ? qsTr("%1 files processed out of %2 files").arg(currentPhoto).arg(totalPhotos) : qsTr("Preparing...")) :
                      qsTr("Found %n face(s)", "", facesDetected)
                font.pixelSize: Theme.fontSizeMedium
                color: "#8892b0"
            }

            // Stats
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.paddingLarge * 3

                Column {
                    spacing: Theme.paddingSmall

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: currentPhoto
                        font.pixelSize: Theme.fontSizeHuge
                        font.bold: true
                        color: "#64ffda"
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Photos")
                        font.pixelSize: Theme.fontSizeSmall
                        color: "#8892b0"
                    }
                }

                Rectangle {
                    width: 1
                    height: Theme.itemSizeSmall
                    color: "#8892b0"
                    opacity: 0.3
                }

                Column {
                    spacing: Theme.paddingSmall

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: facesDetected
                        font.pixelSize: Theme.fontSizeHuge
                        font.bold: true
                        color: "#64ffda"
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Faces")
                        font.pixelSize: Theme.fontSizeSmall
                        color: "#8892b0"
                    }
                }
            }

            // Progress percentage
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: totalPhotos > 0 ? Math.round((currentPhoto / totalPhotos) * 100) + "%" : "0%"
                font.pixelSize: Theme.fontSizeExtraLarge
                font.bold: true
                color: "#64ffda"
                opacity: 0.8
                visible: scanning
            }

            // Cancel button (if needed)
            Item {
                width: parent.width
                height: Theme.paddingLarge * 2
            }

            BackgroundItem {
                width: Theme.buttonWidthMedium
                height: Theme.itemSizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !scanning

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.paddingSmall
                    color: "#64ffda"
                    opacity: parent.pressed ? 0.6 : 0.8

                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Done")
                        color: "#0a192f"
                        font.bold: true
                        font.pixelSize: Theme.fontSizeMedium
                    }
                }

                onClicked: pageStack.pop()
            }
        }
    }
}
