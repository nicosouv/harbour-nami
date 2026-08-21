import QtQuick 2.6
import Sailfish.Silica 1.0

/*
 * The bar shown while a photo grid is in selection mode: how many are picked,
 * share them, cancel, plus one optional page-specific action (set as cover).
 *
 * Sits above the view rather than inside it, so it stays reachable however
 * far the grid is scrolled.
 */
Item {
    id: root

    // Named distinctly from the caller's `selection` id: QML resolves an
    // object's own properties before component ids, so `selection: selection`
    // would bind this property to itself instead of to the page's object.
    property QtObject photoSelection
    property string extraActionIcon: ""
    property bool extraActionEnabled: false

    signal shareRequested()
    signal extraActionTriggered()

    height: photoSelection && photoSelection.active ? bar.height : 0
    visible: height > 0
    opacity: visible ? 1 : 0

    Behavior on opacity { FadeAnimation { duration: 150 } }

    Rectangle {
        id: bar
        width: parent.width
        height: row.height + 2 * Theme.paddingMedium
        color: Theme.rgba(Theme.highlightDimmerColor, 0.95)

        Row {
            id: row
            anchors {
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: parent.right
                rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                verticalCenter: parent.verticalCenter
            }
            spacing: Theme.paddingMedium

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - extraButton.width - shareButton.width
                       - cancelButton.width - 3 * parent.spacing

                Label {
                    width: parent.width
                    text: (root.photoSelection && root.photoSelection.count > 0)
                          ? qsTr("%n selected", "", root.photoSelection.count)
                          : qsTr("Tap photos to select")
                    font.pixelSize: Theme.fontSizeSmall
                    color: (root.photoSelection && root.photoSelection.tooMany)
                           ? Theme.errorColor : Theme.highlightColor
                    truncationMode: TruncationMode.Fade
                }

                Label {
                    width: parent.width
                    visible: root.photoSelection && root.photoSelection.tooMany
                    text: qsTr("That many photos will not go through in one share")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.errorColor
                    wrapMode: Text.Wrap
                }
            }

            IconButton {
                id: extraButton
                anchors.verticalCenter: parent.verticalCenter
                visible: root.extraActionIcon.length > 0
                width: visible ? implicitWidth : 0
                icon.source: root.extraActionIcon
                enabled: root.extraActionEnabled
                onClicked: root.extraActionTriggered()
            }

            IconButton {
                id: shareButton
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-share"
                enabled: root.photoSelection && root.photoSelection.count > 0
                onClicked: root.shareRequested()
            }

            IconButton {
                id: cancelButton
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-clear"
                onClicked: root.photoSelection.end()
            }
        }
    }
}
