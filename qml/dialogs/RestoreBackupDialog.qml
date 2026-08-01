import QtQuick 2.0
import Sailfish.Silica 1.0

Dialog {
    id: dialog

    // List of {file_path, exported_at, total_photos, total_people}
    property var backups: []
    property string selectedFilePath: ""

    canAccept: selectedFilePath.length > 0

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width

            DialogHeader {
                acceptText: qsTr("Restore")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Select a backup to restore")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: backups

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeMedium
                    highlighted: dialog.selectedFilePath === modelData.file_path

                    Column {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }

                        Label {
                            width: parent.width
                            text: modelData.exported_at
                            color: dialog.selectedFilePath === modelData.file_path
                                ? Theme.highlightColor : Theme.primaryColor
                            truncationMode: TruncationMode.Fade
                        }

                        Label {
                            width: parent.width
                            text: qsTr("%1 photos, %2 people").arg(modelData.total_photos).arg(modelData.total_people)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryColor
                        }
                    }

                    onClicked: dialog.selectedFilePath = modelData.file_path
                }
            }

            ViewPlaceholder {
                enabled: backups.length === 0
                text: qsTr("No backup found in this folder")
                hintText: qsTr("Backups are named nami-backup-*.json")
            }
        }

        VerticalScrollDecorator {}
    }
}
