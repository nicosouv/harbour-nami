import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Download state
    property bool downloading: false
    property string currentModel: ""
    property int progress: 0
    property var modelInfo: ({})

    Component.onCompleted: {
        checkModels()
    }

    function checkModels() {
        if (!faceManager || !faceManager.ready) return

        faceManager.python.call('nami_bridge.check_models', [], function(result) {
            if (result.success) {
                modelInfo = result.model_info
                page.forceActiveFocus()
            }
        })
    }

    function startDownload() {
        if (downloading) return

        downloading = true
        progress = 0

        // Set up signal handlers
        faceManager.setHandler('download-progress', function(data) {
            currentModel = data.model
            progress = data.percentage
        })

        faceManager.setHandler('download-completed', function(results) {
            downloading = false
            progress = 100
            checkModels()
        })

        faceManager.setHandler('download-failed', function(results) {
            downloading = false
            // Show error
        })

        // Start download
        faceManager.python.call('nami_bridge.download_models', [], function(result) {
            if (!result.success) {
                downloading = false
            }
        })
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("ML Models Setup")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Nami requires machine learning models for face detection and recognition.")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("All models run 100% on your device. No data is sent to external servers.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Required Models")
            }

            // YuNet model
            ListItem {
                contentHeight: yunetColumn.height + 2 * Theme.paddingMedium

                Column {
                    id: yunetColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingSmall

                    Row {
                        width: parent.width
                        spacing: Theme.paddingMedium

                        Image {
                            source: modelInfo.yunet && modelInfo.yunet.exists ?
                                   "image://theme/icon-s-installed" :
                                   "image://theme/icon-s-cloud-download"
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: qsTr("YuNet Face Detection")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Label {
                        text: qsTr("Size: %1 MB").arg(modelInfo.yunet ? modelInfo.yunet.expected_size_mb : "0.35")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    Label {
                        text: modelInfo.yunet && modelInfo.yunet.exists ?
                             qsTr("✓ Installed") :
                             qsTr("Not installed")
                        color: modelInfo.yunet && modelInfo.yunet.exists ?
                              Theme.secondaryHighlightColor :
                              Theme.errorColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            // ArcFace model
            ListItem {
                contentHeight: arcfaceColumn.height + 2 * Theme.paddingMedium

                Column {
                    id: arcfaceColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingSmall

                    Row {
                        width: parent.width
                        spacing: Theme.paddingMedium

                        Image {
                            source: modelInfo.arcface && modelInfo.arcface.exists ?
                                   "image://theme/icon-s-installed" :
                                   "image://theme/icon-s-cloud-download"
                            width: Theme.iconSizeSmall
                            height: Theme.iconSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Label {
                            text: qsTr("ArcFace Recognition")
                            color: Theme.highlightColor
                            font.pixelSize: Theme.fontSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Label {
                        text: qsTr("Size: %1 MB").arg(modelInfo.arcface ? modelInfo.arcface.expected_size_mb : "2.5")
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }

                    Label {
                        text: modelInfo.arcface && modelInfo.arcface.exists ?
                             qsTr("✓ Installed") :
                             qsTr("Manual installation required")
                        color: modelInfo.arcface && modelInfo.arcface.exists ?
                              Theme.secondaryHighlightColor :
                              Theme.errorColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            // Download progress
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: downloading

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Downloading %1...").arg(currentModel)
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }

                ProgressBar {
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.horizontalCenter: parent.horizontalCenter
                    minimumValue: 0
                    maximumValue: 100
                    value: progress
                }

                BusyIndicator {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: BusyIndicatorSize.Medium
                    running: downloading
                }
            }

            // Action buttons
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Download Models")
                enabled: !downloading && !(modelInfo.yunet && modelInfo.yunet.exists && modelInfo.arcface && modelInfo.arcface.exists)
                visible: !downloading
                onClicked: startDownload()
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Continue")
                enabled: modelInfo.yunet && modelInfo.yunet.exists && modelInfo.arcface && modelInfo.arcface.exists
                visible: !downloading
                onClicked: {
                    // Initialize face manager and go to main page
                    pageStack.pop()
                }
            }

            SectionHeader {
                text: qsTr("Manual Installation")
                visible: modelInfo.arcface && !modelInfo.arcface.exists
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("The ArcFace model requires manual installation. Please see the documentation for instructions.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
                visible: modelInfo.arcface && !modelInfo.arcface.exists
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Open Documentation")
                visible: modelInfo.arcface && !modelInfo.arcface.exists
                onClicked: {
                    Qt.openUrlExternally("https://github.com/nicosouv/harbour-nami/blob/main/python/models/README.md")
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
