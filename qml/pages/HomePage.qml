import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

// The app's first screen: what there is to look at right now. The full
// people list, with its search and its sort order, is one swipe to the left
// (PeoplePage, attached below).
Page {
    id: page

    allowedOrientations: Orientation.All

    property int totalPeople: 0
    property int totalPhotos: 0

    // pushAttached() must happen once and only once. Guarding on
    // pageStack.depth would depend on whether an attached page counts
    // towards it, which is not worth betting the navigation on.
    property bool peopleAttached: false

    // Faces on the home page before the people page takes over. Enough to
    // recognise the household, not enough to become the list itself.
    property int recentPeopleCount: 12

    ListModel {
        id: recentPeopleModel
    }

    function refresh() {
        if (!facePipeline || !facePipeline.initialized) return

        var people = facePipeline.getAllPeople()

        totalPeople = people.length
        totalPhotos = 0
        for (var i = 0; i < people.length; i++) {
            totalPhotos += people[i].photo_count
        }

        // Most recently photographed first: a home page is about now, and
        // the person with the biggest back catalogue is not necessarily
        // anyone you saw this year
        people.sort(function (a, b) {
            var aLast = a.last_photo || 0
            var bLast = b.last_photo || 0
            if (aLast !== bLast) return bLast - aLast
            return b.photo_count - a.photo_count
        })

        // Updated in place rather than cleared: this runs on every return to
        // the home page, and clear() would throw the row back to its start
        // every time someone comes back from a person
        var shown = Math.min(people.length, recentPeopleCount)
        for (var j = 0; j < shown; j++) {
            if (j < recentPeopleModel.count) {
                recentPeopleModel.set(j, people[j])
            } else {
                recentPeopleModel.append(people[j])
            }
        }
        while (recentPeopleModel.count > shown) {
            recentPeopleModel.remove(recentPeopleModel.count - 1)
        }
    }

    function openPerson(personId, name) {
        pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
            personId: personId,
            personName: name
        })
    }

    onStatusChanged: {
        if (status !== PageStatus.Active) return

        if (!peopleAttached) {
            peopleAttached = true
            pageStack.pushAttached(Qt.resolvedUrl("PeoplePage.qml"))
        }
        refresh()
    }

    Component.onCompleted: refresh()

    Connections {
        target: facePipeline
        onScanCompleted: refresh()
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem { text: qsTr("About"); onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml")) }
            MenuItem { text: qsTr("Settings"); onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml")) }
            MenuItem {
                text: qsTr("Memories")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("MemoriesPage.qml"))
            }
            MenuItem {
                text: qsTr("Events")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("EventsPage.qml"))
            }
            MenuItem {
                text: qsTr("Identify Faces")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml"))
            }
            MenuItem {
                text: qsTr("Scan Gallery")
                enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                onClicked: pageStack.push(Qt.resolvedUrl("ScanningPage.qml"))
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Nami")
                // The counts as a quiet line under the title, the way the
                // people list has always shown them
                description: totalPeople > 0
                    ? (totalPeople + " "
                       + (totalPeople === 1 ? qsTr("person") : qsTr("people"))
                       + "  ·  " + totalPhotos + " "
                       + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos")))
                    : ""
            }

            // What the app is, said once, on the empty library. This used to
            // sit above the people list; the home page is where a first
            // launch actually lands.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: totalPeople === 0

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
            }

            // No heading above this row on purpose: a line of faces says what
            // it is, and a label would only push the content further down.
            ListView {
                id: peopleRow

                property real cellSize: Theme.itemSizeLarge

                width: parent.width
                height: cellSize + Theme.itemSizeExtraSmall
                visible: count > 0

                orientation: ListView.Horizontal
                // Nested in a vertical flickable: without pinning the
                // direction the two fight over every drag and neither moves
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                spacing: Theme.paddingMedium
                clip: true
                model: recentPeopleModel

                // Page margins as header and footer rather than as ListView
                // margins, which do not exist on every Qt version this runs on
                header: Item { width: Theme.horizontalPageMargin; height: 1 }
                footer: Item { width: Theme.horizontalPageMargin; height: 1 }

                delegate: BackgroundItem {
                    id: personItem
                    width: peopleRow.cellSize
                    height: peopleRow.height

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Item {
                            width: peopleRow.cellSize
                            height: width

                            Image {
                                id: avatar
                                anchors.fill: parent
                                source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                                sourceSize.width: width
                                sourceSize.height: height
                                fillMode: Image.PreserveAspectCrop
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
                                opacity: 0.4
                            }
                        }

                        Label {
                            width: parent.width
                            text: model.name || qsTr("Unknown")
                            color: personItem.highlighted ? Theme.highlightColor
                                                          : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    onClicked: openPerson(model.person_id, model.name)
                }
            }
        }

        ViewPlaceholder {
            enabled: totalPeople === 0
            text: qsTr("No faces detected yet")
            hintText: qsTr("Pull down to scan your gallery")
        }

        VerticalScrollDecorator {}
    }
}
