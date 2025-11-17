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
                text: qsTr("Performance")
            }

            ComboBox {
                id: qualityCombo
                width: parent.width
                label: qsTr("Recognition quality")
                currentIndex: 1

                menu: ContextMenu {
                    MenuItem { text: qsTr("Low (faster)") }
                    MenuItem { text: qsTr("Medium (balanced)") }
                    MenuItem { text: qsTr("High (accurate)") }
                }

                description: qsTr("Higher quality improves accuracy but uses more resources")
            }

            TextSwitch {
                id: autoScanSwitch
                text: qsTr("Auto-scan new photos")
                description: qsTr("Automatically detect faces in newly added photos")
                checked: false
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
                        pageStack.push(Qt.resolvedUrl("../components/NotificationBanner.qml"), {
                            "text": qsTr("Export feature coming soon")
                        })
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
        }
    }
}
