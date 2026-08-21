import QtQuick 2.6
import Sailfish.Silica 1.0

/*
 * A short list of actions, pushed as its own page.
 *
 * Silica's ContextMenu expands its ListItem and lets the view push the
 * following items down. A SilicaGridView cannot do that: it lays cells out on
 * a fixed cellHeight, so an opened menu is drawn straight over the next row.
 * Grid delegates therefore ask for their actions here instead, where there is
 * room to read them.
 *
 * Usage:
 *     var sheet = pageStack.push(Qt.resolvedUrl("ActionSheetPage.qml"), {
 *         heading: name,
 *         actions: [ { id: "rename", text: qsTr("Rename") } ]
 *     })
 *     sheet.chosen.connect(function (actionId) { ... })
 *
 * The page pops itself before emitting, so a handler is free to push another
 * page without fighting this one for the stack.
 */
Page {
    id: page

    property string heading: ""
    property string subheading: ""
    // [{ id: string, text: string, enabled: bool (optional) }]
    property var actions: []

    signal chosen(string actionId)

    allowedOrientations: Orientation.All

    SilicaListView {
        anchors.fill: parent
        model: page.actions

        header: PageHeader {
            title: page.heading
            description: page.subheading
        }

        delegate: BackgroundItem {
            width: parent.width
            enabled: modelData.enabled === undefined ? true : modelData.enabled
            opacity: enabled ? 1 : Theme.opacityLow

            Label {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                text: modelData.text
                color: parent.highlighted ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }

            onClicked: {
                var actionId = modelData.id
                pageStack.pop()
                page.chosen(actionId)
            }
        }

        VerticalScrollDecorator {}
    }
}
