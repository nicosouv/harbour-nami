import QtQuick 2.0
import Sailfish.Silica 1.0

// Pick another trip to merge the current one into
Dialog {
    id: dialog

    property var trips: []          // full list from getTrips()
    property int excludeTripId: -1
    property int selectedTripId: -1
    property string selectedTripName: ""

    canAccept: selectedTripId > 0

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: qsTr("Merge")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Merge into which trip?")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: trips

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    visible: modelData.trip_id !== dialog.excludeTripId
                    highlighted: selectedTripId === modelData.trip_id

                    Label {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        text: modelData.name
                        color: selectedTripId === modelData.trip_id
                            ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    onClicked: {
                        selectedTripId = modelData.trip_id
                        selectedTripName = modelData.name
                        dialog.accept()
                    }
                }
            }

            ViewPlaceholder {
                enabled: trips.length <= 1
                text: qsTr("No other trips")
                hintText: qsTr("Group more days into a trip first")
            }
        }

        VerticalScrollDecorator {}
    }
}
