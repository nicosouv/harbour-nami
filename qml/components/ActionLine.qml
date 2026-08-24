import QtQuick 2.6
import Sailfish.Silica 1.0

// One quiet line on the home page saying there is something to do.
//
// Not a card, not a banner, no frame: an icon, a sentence, and a chevron.
// The whole point of these is that they are absent most of the time, so
// they have to cost nothing to look past when they are there.
BackgroundItem {
    id: root

    property alias text: label.text
    // A theme icon rather than an emoji: it takes the theme's colour and the
    // theme's size, so it belongs to the page instead of sitting on top of it
    property string icon: ""

    height: Theme.itemSizeSmall

    Row {
        anchors {
            left: parent.left
            leftMargin: Theme.horizontalPageMargin
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.paddingMedium

        Image {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            source: root.icon.length > 0
                    ? root.icon + "?" + (root.highlighted ? Theme.highlightColor
                                                          : Theme.primaryColor)
                    : ""
            width: Theme.iconSizeSmall
            height: width
            sourceSize.width: width
            sourceSize.height: height
            visible: root.icon.length > 0
        }

        Label {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - glyph.width - chevron.width - 2 * parent.spacing
            color: root.highlighted ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: Theme.fontSizeSmall
            truncationMode: TruncationMode.Fade
        }

        Image {
            id: chevron
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-right?" + Theme.secondaryColor
            width: Theme.iconSizeExtraSmall
            height: width
            sourceSize.width: width
            sourceSize.height: height
        }
    }
}
