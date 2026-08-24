import QtQuick 2.6
import Sailfish.Silica 1.0

// Which of the app's three sections a page belongs to.
//
// The three look different by design, and that is why they need naming: a
// page deep inside Events and a page deep inside Memories are both a title
// over a grid of photographs, and by the third screen down nobody remembers
// which door they came through.
//
// Icon, colour and word together. The colour is what you catch without
// reading, the icon is what you recognise, the word is what settles it.
//
// Placed inside a PageHeader, in the empty space to the left of its
// right-aligned title. It went the other way round first, as a header that
// wrapped PageHeader in a Column, and that quietly broke PersonDetailPage:
// the page puts its avatar inside its header, and a Column positions its
// children rather than letting them anchor freely.
Row {
    id: root

    // "people" | "events" | "memories"
    property string section: ""

    spacing: Theme.paddingSmall
    visible: section.length > 0

    // Fixed rather than taken from the ambience. Theme.highlightColor is one
    // colour, and one colour cannot tell three sections apart; the whole
    // point is that they differ. Chosen to hold up on a light ambience as
    // well as a dark one.
    readonly property color sectionColor: {
        switch (section) {
        case "people":   return "#5A9BD8"
        case "events":   return "#E0604C"
        case "memories": return "#E0A23C"
        }
        return Theme.highlightColor
    }

    readonly property string sectionIcon: {
        switch (section) {
        case "people":   return "image://theme/icon-m-contact"
        case "events":   return "image://theme/icon-m-date"
        case "memories": return "image://theme/icon-m-image"
        }
        return ""
    }

    readonly property string sectionName: {
        switch (section) {
        case "people":   return qsTr("People")
        case "events":   return qsTr("Events")
        case "memories": return qsTr("Memories")
        }
        return ""
    }

    Image {
        anchors.verticalCenter: name.verticalCenter
        source: root.sectionIcon.length > 0
                ? root.sectionIcon + "?" + root.sectionColor : ""
        width: Theme.iconSizeExtraSmall
        height: width
        sourceSize.width: width
        sourceSize.height: height
        visible: root.sectionIcon.length > 0
    }

    Label {
        id: name
        text: root.sectionName
        color: root.sectionColor
        font.pixelSize: Theme.fontSizeTiny
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.pixelRatio * 1.5
    }
}
