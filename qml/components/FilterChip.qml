import QtQuick 2.6
import Sailfish.Silica 1.0

/*
 * A small tappable label that reads as selected or not.
 *
 * Filtering and sorting belong on the page, next to what they act on: buried
 * in a pulley menu the user cannot see the current state without opening the
 * menu. Deliberately lighter than a Button so a row of them stays quiet.
 */
MouseArea {
    id: root

    property alias text: label.text
    property bool selected: false

    width: label.width + 2 * Theme.paddingMedium
    height: label.height + Theme.paddingMedium

    Label {
        id: label
        anchors.centerIn: parent
        font.pixelSize: Theme.fontSizeSmall
        color: root.selected
               ? Theme.highlightColor
               : (root.pressed ? Theme.secondaryHighlightColor : Theme.secondaryColor)

        Behavior on color { ColorAnimation { duration: 100 } }
    }

    // Underline rather than a filled pill: it marks the active choice without
    // turning a row of filters into a row of buttons
    Rectangle {
        anchors {
            left: label.left
            right: label.right
            top: label.bottom
            topMargin: Theme.paddingSmall / 2
        }
        height: Math.max(1, Theme.paddingSmall / 3)
        radius: height / 2
        color: Theme.highlightColor
        opacity: root.selected ? 1 : 0

        Behavior on opacity { FadeAnimation { duration: 150 } }
    }
}
