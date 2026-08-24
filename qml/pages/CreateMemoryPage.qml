import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

// Building a memory out of a chosen group of people.
//
// The recipes already do this for pairs that keep turning up together. This
// is the same thing asked for rather than found: the people you want, not
// the ones the counting noticed.
Page {
    id: page

    allowedOrientations: Orientation.All

    // Photos where everyone appears at once, rather than every photo any of
    // them is in. With three or four people the two answers are worlds
    // apart, so it is a choice and not a default.
    property bool together: true
    property int matchingPhotos: 0

    ListModel {
        id: peopleModel
    }

    function selectedIds() {
        var ids = []
        for (var i = 0; i < peopleModel.count; i++) {
            var person = peopleModel.get(i)
            if (person.chosen) {
                ids.push(person.person_id)
            }
        }
        return ids
    }

    // Counted before anything is made, so picking a fourth person who is
    // never in frame with the other three reads as zero here rather than as
    // an empty memory afterwards
    function recount() {
        var ids = selectedIds()
        matchingPhotos = ids.length > 0
            ? facePipeline.countPhotosOfPeople(ids, together) : 0
    }

    onTogetherChanged: recount()

    function toggle(index) {
        peopleModel.setProperty(index, "chosen", !peopleModel.get(index).chosen)
        recount()
    }

    function create() {
        var memoryId = facePipeline.createPeopleMemory(selectedIds(), together)
        if (memoryId <= 0) {
            return
        }
        var title = facePipeline.getMemory(memoryId).title
        pageStack.replace(Qt.resolvedUrl("MemoryDetailPage.qml"), {
            memoryId: memoryId,
            title: title
        })
    }

    Component.onCompleted: {
        if (!facePipeline || !facePipeline.initialized) return

        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            peopleModel.append({
                person_id: people[i].person_id,
                name: people[i].name,
                photo_count: people[i].photo_count,
                chosen: false
            })
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: peopleModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingMedium

            PageHeader {
                // Which section this page belongs to, in the space the
                // right-aligned title leaves free
                SectionMark {
                    section: "memories"
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                }

                title: qsTr("New memory")
            }

            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingLarge

                FilterChip {
                    text: qsTr("Together")
                    selected: page.together
                    onClicked: page.together = true
                }
                FilterChip {
                    text: qsTr("Any of them")
                    selected: !page.together
                    onClicked: page.together = false
                }
            }

            // What the choice amounts to, updated as it is made. The one
            // number that decides whether this memory is worth making.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: matchingPhotos === 1 ? qsTr("1 photo")
                                           : qsTr("%1 photos").arg(matchingPhotos)
                color: matchingPhotos > 0 ? Theme.highlightColor : Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }

            Item { width: 1; height: Theme.paddingSmall }
        }

        delegate: ListItem {
            id: personItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeMedium

            Row {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: Theme.paddingMedium

                Rectangle {
                    width: Theme.itemSizeSmall
                    height: width
                    radius: width / 2
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)
                    opacity: model.chosen ? 1.0 : 0.4

                    Image {
                        id: avatar
                        anchors.fill: parent
                        source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                        sourceSize.width: width
                        sourceSize.height: height
                        asynchronous: true
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-contact"
                        width: Theme.iconSizeMedium
                        height: width
                        sourceSize.width: width
                        sourceSize.height: height
                        visible: avatar.status !== Image.Ready
                    }
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.itemSizeSmall - chosenMark.width
                           - 2 * Theme.paddingMedium
                    text: model.name || qsTr("Unknown")
                    color: model.chosen ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                }

                // Only the chosen are marked. An unchecked box on every row
                // is a column of noise down a list of faces.
                Image {
                    id: chosenMark
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-acknowledge?" + Theme.highlightColor
                    width: Theme.iconSizeSmall
                    height: width
                    sourceSize.width: width
                    sourceSize.height: height
                    opacity: model.chosen ? 1.0 : 0.0
                    Behavior on opacity { FadeAnimation {} }
                }
            }

            onClicked: page.toggle(index)
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No people yet")
            hintText: qsTr("They appear once your gallery has been scanned")
        }

        VerticalScrollDecorator {}
    }

    // Nothing to press until the choice adds up to a memory
    DockedPanel {
        id: panel
        dock: Dock.Bottom
        width: parent.width
        height: Theme.itemSizeLarge
        open: matchingPhotos >= 5

        Button {
            anchors.centerIn: parent
            text: qsTr("Create")
            onClicked: page.create()
        }
    }
}
