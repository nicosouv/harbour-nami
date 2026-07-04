import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var stats: ({})

    allowedOrientations: Orientation.All

    function loadStatistics() {
        if (facePipeline && facePipeline.initialized) {
            stats = facePipeline.getStatistics()
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
