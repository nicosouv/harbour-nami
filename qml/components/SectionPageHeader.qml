import QtQuick 2.6
import Sailfish.Silica 1.0

// A page header that says which of the app's three sections you are in.
//
// The three look different by design, and that is exactly why they need
// naming: a page deep inside Events and a page deep inside Memories are both
// a title over a grid of photographs, and by the third screen down nobody
// remembers which door they came through.
//
// Icon, colour and word together rather than any one of them. The colour is
// what you catch without reading, the icon is what you recognise, and the
// word is what settles it. On its own each is a guess.
//
// A drop-in for PageHeader: same title and description, and it still works
// as a ListView header because it is one item.
//
// Not called SectionHeader. Silica already has one, and a component here
// with that name shadows it in every file that imports this directory,
// which took YearDetailPage down without a word: it uses Silica'''s, with a
// text property this one does not have.
Column {
    id: root

    // "people" | "events" | "memories". Anything else, and this is just a
    // PageHeader: the home, the settings and the about page belong to no
    // section and must not pretend to.
    property string section: ""
    property string title: ""
    property string description: ""

    width: parent ? parent.width : 0

    // Fixed rather than taken from the ambience. Theme.highlightColor is one
    // colour, and one colour cannot tell three sections apart; the whole
    // point here is that they differ. Chosen to hold up on a light ambience
    // as well as a dark one.
    readonly property color sectionColor: {
        switch (section) {
        case "people":   return "#3D7AB8"   // blue
        case "events":   return "#C6412F"   // red
        case "memories": return "#C8891F"   // amber
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

    // Nothing is gained by writing PEOPLE above a page whose title is
    // already People. The root of a section names itself; it is the screens
    // underneath, where a title over a grid of photographs could belong to
    // any of the three, that lose the thread.
    readonly property bool marked: sectionName.length > 0 && title !== sectionName

    // A plain spacer rather than Row.topPadding: the positioner padding
    // properties are recent enough that betting the header of every page on
    // them is not worth the line it saves
    Item {
        width: 1
        height: Theme.paddingLarge
        visible: root.marked
    }

    Row {
        x: Theme.horizontalPageMargin
        spacing: Theme.paddingSmall
        visible: root.marked

        Image {
            anchors.verticalCenter: sectionLabel.verticalCenter
            source: root.sectionIcon.length > 0
                    ? root.sectionIcon + "?" + root.sectionColor : ""
            width: Theme.iconSizeExtraSmall
            height: width
            sourceSize.width: width
            sourceSize.height: height
            visible: root.sectionIcon.length > 0
        }

        Label {
            id: sectionLabel
            text: root.sectionName
            color: root.sectionColor
            font.pixelSize: Theme.fontSizeTiny
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Theme.pixelRatio * 1.5
        }
    }

    PageHeader {
        title: root.title
        description: root.description
    }
}
