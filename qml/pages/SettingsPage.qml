import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

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
                value: "0"
            }

            DetailItem {
                label: qsTr("Named people")
                value: "0"
            }

            DetailItem {
                label: qsTr("Storage used")
                value: "0 KB"
            }

            SectionHeader {
                text: qsTr("Data Management")
            }

            ButtonLayout {
                Button {
                    text: qsTr("Export data")
                    onClicked: {
                        // Export face recognition data
                        // TODO: Implement GDPR data export
                    }
                }

                Button {
                    text: qsTr("Clear all data")
                    onClicked: {
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/ConfirmDialog.qml"), {
                            "title": qsTr("Clear all data?"),
                            "message": qsTr("This will delete all detected faces and names. This action cannot be undone.")
                        })
                        dialog.accepted.connect(function() {
                            // Clear all face recognition data
                            // TODO: Implement data deletion
                        })
                    }
                }
            }
        }
    }
}
