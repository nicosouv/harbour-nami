import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

    // Access global face pipeline from C++ backend
    // facePipeline is exposed via QML context in main.cpp

    // People model
    ListModel {
        id: peopleModel
    }

    // Refresh people list
    function refreshPeople() {
        if (!facePipeline || !facePipeline.initialized) return

        peopleModel.clear()
        var people = facePipeline.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            peopleModel.append(people[i])
        }
    }

    Component.onCompleted: {
        // Wait for face pipeline to be ready
        if (facePipeline && facePipeline.initialized) {
            refreshPeople()
        }
    }

    Connections {
        target: facePipeline
        onScanCompleted: refreshPeople()
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: peopleModel

        PullDownMenu {
            MenuItem {
                text: qsTr("About")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
            }
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: qsTr("Review Unknown Faces")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("UnknownFacesPage.qml"))
            }
            MenuItem {
                text: qsTr("Scan Gallery")
                enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                onClicked: {
                    // Start gallery scan
                    facePipeline.scanGallery(defaultGalleryPath, true)
                }
            }
        }

        header: Column {
            width: parent.width
            spacing: 0

            PageHeader {
                title: qsTr("Nami")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Face Recognition Gallery")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Automatically organize your photos by faces. All processing happens on your device for complete privacy.")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            SectionHeader {
                text: qsTr("People")
            }
        }

        delegate: ListItem {
            id: listItem
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

                // Face thumbnail placeholder
                Rectangle {
                    width: Theme.itemSizeSmall
                    height: Theme.itemSizeSmall
                    radius: Theme.itemSizeSmall / 2
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)

                    Image {
                        anchors.centerIn: parent
                        source: "image://theme/icon-m-contact"
                        width: Theme.iconSizeMedium
                        height: Theme.iconSizeMedium
                    }
                }

                Column {
                    width: parent.width - Theme.itemSizeSmall - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        text: model.name || qsTr("Unknown")
                        color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.photo_count + " " + (model.photo_count === 1 ? qsTr("photo") : qsTr("photos"))
                        color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }
                }
            }

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Rename")
                    onClicked: {
                        var dialog = pageStack.push("Sailfish.Silica.InputDialog", {
                            acceptDestination: page,
                            acceptDestinationAction: PageStackAction.Pop,
                            title: qsTr("Rename Person"),
                            placeholderText: qsTr("Enter name"),
                            text: model.name
                        })
                        dialog.accepted.connect(function() {
                            facePipeline.updatePersonName(model.person_id, dialog.value)
                            refreshPeople()
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Delete")
                    onClicked: {
                        var dialog = pageStack.push("Sailfish.Silica.RemorseDialog", {
                            title: qsTr("Delete person?"),
                            text: qsTr("This will remove %1 and unlink all their photos").arg(model.name)
                        })
                        dialog.accepted.connect(function() {
                            facePipeline.deletePerson(model.person_id)
                            refreshPeople()
                        })
                    }
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
                    personId: model.person_id,
                    personName: model.name
                })
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No faces detected yet")
            hintText: qsTr("Pull down to scan your gallery")
        }

        VerticalScrollDecorator {}
    }
}
