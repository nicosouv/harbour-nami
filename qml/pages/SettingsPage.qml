import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0

Page {
    id: page

    property var stats: ({})
    property string galleryPath: ""

    allowedOrientations: Orientation.All

    function loadStatistics() {
        if (facePipeline && facePipeline.initialized) {
            stats = facePipeline.getStatistics()
            galleryPath = facePipeline.getSetting("gallery_path", defaultGalleryPath)
        }
    }

    Component.onCompleted: {
        loadStatistics()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width

            PageHeader {
                title: qsTr("Settings")
            }

            SectionHeader {
                text: qsTr("Privacy")
            }

            TextArea {
                width: parent.width
                readOnly: true
                label: qsTr("On-device processing")
                text: qsTr("All face recognition processing happens locally on your device. No data is sent to external servers.")
            }

            SectionHeader {
                text: qsTr("Scanning")
            }

            ValueButton {
                label: qsTr("Scan folder")
                value: galleryPath || defaultGalleryPath
                enabled: facePipeline && facePipeline.initialized
                onClicked: {
                    var dialog = pageStack.push(folderPickerComponent)
                }

                Component {
                    id: folderPickerComponent
                    FolderPickerDialog {
                        title: qsTr("Select folder to scan")
                        onAccepted: {
                            galleryPath = selectedPath
                            facePipeline.setSetting("gallery_path", selectedPath)
                        }
                    }
                }
            }

            Slider {
                id: thresholdSlider
                width: parent.width
                label: qsTr("Recognition strictness")
                minimumValue: 0.65
                maximumValue: 0.80
                stepSize: 0.01
                valueText: Math.round(value * 100) + "%"
                enabled: facePipeline && facePipeline.initialized

                Component.onCompleted: {
                    if (facePipeline && facePipeline.initialized) {
                        value = parseFloat(facePipeline.getSetting("auto_match_threshold", "0.72"))
                    }
                }

                onReleased: {
                    facePipeline.setSetting("auto_match_threshold", value.toFixed(2))
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Higher values reduce wrong matches but leave more faces to identify manually")
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Storage")
            }

            DetailItem {
                label: qsTr("Detected faces")
                value: stats.total_faces || 0
            }

            DetailItem {
                label: qsTr("Named people")
                value: stats.total_people || 0
            }

            DetailItem {
                label: qsTr("Storage used")
                value: {
                    var bytes = stats.db_size_bytes || 0
                    if (bytes < 1024) return bytes + " B"
                    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
                    return (bytes / (1024 * 1024)).toFixed(1) + " MB"
                }
            }

            SectionHeader {
                text: qsTr("Data Management")
            }

            ButtonLayout {
                Button {
                    text: qsTr("Export data")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: {
                        var path = facePipeline.exportData()
                        exportResultLabel.text = path
                            ? qsTr("Exported to %1").arg(path)
                            : qsTr("Export failed")
                    }
                }

                Button {
                    text: qsTr("Clear all data")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: {
                        var remorse = Remorse.popupAction(page, qsTr("Deleting all data"), function() {
                            if (facePipeline.deleteAllData()) {
                                loadStatistics()
                            }
                        })
                    }
                }
            }

            Label {
                id: exportResultLabel
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.Wrap
                visible: text.length > 0
            }
        }
    }
}
