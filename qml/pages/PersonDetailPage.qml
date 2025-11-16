import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property int personId: -1
    property string personName: ""
    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Photos with this person
    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!faceManager || !faceManager.initialized || personId < 0) return

        photosModel.clear()

        // Get all photos for this person
        var photos = faceManager.getPersonPhotos(personId)

        for (var i = 0; i < photos.length; i++) {
            photosModel.append(photos[i])
        }
    }

    Component.onCompleted: {
        loadPhotos()
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Rename")
                onClicked: {
                    var dialog = pageStack.push("Sailfish.Silica.InputDialog", {
                        acceptDestination: page,
                        acceptDestinationAction: PageStackAction.Pop,
                        title: qsTr("Rename Person"),
                        placeholderText: qsTr("Enter name"),
                        text: personName
                    })
                    dialog.accepted.connect(function() {
                        facePipeline.updatePersonName(personId, dialog.value)
                        personName = dialog.value
                    })
                }
            }
            MenuItem {
                text: qsTr("Delete")
                onClicked: {
                    var remorse = pageStack.push("Sailfish.Silica.RemorsePopup")
                    remorse.execute(qsTr("Deleting %1").arg(personName), function() {
                        facePipeline.deletePerson(personId)
                        pageStack.pop()
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: personName
            }

            // Statistics card
            Item {
                width: parent.width
                height: statsCard.height

                Rectangle {
                    id: statsCard
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: statsColumn.height + 2 * Theme.paddingMedium
                    x: Theme.horizontalPageMargin
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                    Column {
                        id: statsColumn
                        width: parent.width - 2 * Theme.paddingMedium
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            text: photosModel.count + " " + (photosModel.count === 1 ? qsTr("photo") : qsTr("photos"))
                            font.pixelSize: Theme.fontSizeHuge
                            font.bold: true
                            color: Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Label {
                            text: qsTr("with this person")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            SectionHeader {
                text: qsTr("Photos")
                visible: photosModel.count > 0
            }

            // Photo grid
            Grid {
                id: photoGrid
                width: parent.width
                columns: 3
                spacing: Theme.paddingSmall

                Repeater {
                    model: photosModel

                    delegate: BackgroundItem {
                        width: photoGrid.width / 3
                        height: width

                        Image {
                            anchors.fill: parent
                            anchors.margins: Theme.paddingSmall / 2
                            source: model.file_path ? "file://" + model.file_path : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            clip: true

                            // Limit source size to save memory
                            sourceSize.width: 400
                            sourceSize.height: 400

                            BusyIndicator {
                                anchors.centerIn: parent
                                running: parent.status === Image.Loading
                                size: BusyIndicatorSize.Small
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.color: Theme.rgba(Theme.highlightColor, 0.1)
                                border.width: 1
                            }
                        }

                        onClicked: {
                            // TODO: Open full-screen photo viewer
                            console.log("Photo clicked:", model.file_path)
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: photosModel.count === 0
                text: qsTr("No photos")
                hintText: qsTr("This person hasn't been detected in any photos yet")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
