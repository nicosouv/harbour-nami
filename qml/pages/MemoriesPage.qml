import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

// Every memory the recipes have found, best first. The home page shows the
// top one and a handful of others; this is the whole list.
//
// It reads the memories table rather than working the list out again. The
// page used to walk every person's every photo on each opening and group
// them in JavaScript, which meant the list existed only for as long as the
// page did: nothing could link to a memory, and nothing could remember that
// the user had renamed or dismissed one.
Page {
    id: page

    allowedOrientations: Orientation.All

    MemoryLabels {
        id: memoryLabels
    }

    ListModel {
        id: memoriesModel
    }

    function loadMemories() {
        if (!facePipeline || !facePipeline.initialized) return

        memoriesModel.clear()

        var memories = facePipeline.getMemories()
        for (var i = 0; i < memories.length; i++) {
            var memory = memories[i]
            memoriesModel.append({
                memory_id: memory.memory_id,
                cover_photo: memory.cover_photo,
                photo_count: memory.photo_count,
                display_title: memoryLabels.title(memory),
                display_subtitle: memoryLabels.subtitle(memory)
            })
        }
    }

    function dismissMemory(memoryId, title) {
        Remorse.popupAction(page, qsTr("Hiding %1").arg(title), function () {
            facePipeline.setMemoryDismissed(memoryId, true)
            loadMemories()
        })
    }

    Component.onCompleted: loadMemories()

    onStatusChanged: {
        // Coming back from a memory: it may have been renamed or edited
        if (status === PageStatus.Active) {
            loadMemories()
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: memoriesModel

        PullDownMenu {
            MenuItem {
                text: qsTr("Look for new memories")
                enabled: facePipeline && facePipeline.initialized
                onClicked: {
                    facePipeline.generateMemories(true)
                    loadMemories()
                }
            }
            MenuItem {
                text: qsTr("Memory of chosen people")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("CreateMemoryPage.qml"))
            }
        }

        header: PageHeader {
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

            title: qsTr("Memories")
        }

        delegate: ListItem {
            id: memoryItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeExtraLarge

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                    topMargin: Theme.paddingSmall
                    bottomMargin: Theme.paddingSmall
                }
                spacing: Theme.paddingMedium

                Image {
                    id: cover
                    width: height * 1.4
                    height: parent.height
                    source: FaceUtils.thumbUrl(model.cover_photo)
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    clip: true
                    asynchronous: true
                }

                Column {
                    width: parent.width - cover.width - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall / 2

                    Label {
                        width: parent.width
                        text: model.display_title
                        color: memoryItem.highlighted ? Theme.highlightColor
                                                      : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: model.display_subtitle
                        color: memoryItem.highlighted ? Theme.secondaryHighlightColor
                                                      : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        visible: text.length > 0
                    }
                }
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Hide")
                    onClicked: dismissMemory(model.memory_id, model.display_title)
                }
            }

            onClicked: pageStack.push(Qt.resolvedUrl("MemoryDetailPage.qml"), {
                memoryId: model.memory_id,
                title: model.display_title
            })
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No memories yet")
            hintText: qsTr("They appear once your gallery has been scanned")
        }

        VerticalScrollDecorator {}
    }
}
