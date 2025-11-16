import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Memories model
    ListModel {
        id: memoriesModel
    }

    Component.onCompleted: {
        detectMemories()
    }

    // Detect memories: photos from same date in previous years
    function detectMemories() {
        if (!faceManager || !faceManager.initialized) return

        memoriesModel.clear()

        var today = new Date()
        var todayMonth = today.getMonth()
        var todayDay = today.getDate()

        // Get all people
        var people = faceManager.getAllPeople()
        var memories = {}  // Map of years ago -> photos

        // Scan all photos
        for (var i = 0; i < people.length; i++) {
            var person = people[i]
            var photos = faceManager.getPersonPhotos(person.person_id)

            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp) continue

                var photoDate = new Date(photo.timestamp * 1000)
                var photoMonth = photoDate.getMonth()
                var photoDay = photoDate.getDate()
                var photoYear = photoDate.getFullYear()

                // Check if same day and month, but different year
                if (photoMonth === todayMonth && photoDay === todayDay && photoYear < today.getFullYear()) {
                    var yearsAgo = today.getFullYear() - photoYear

                    if (!memories[yearsAgo]) {
                        memories[yearsAgo] = {
                            yearsAgo: yearsAgo,
                            date: photoDate,
                            photos: [],
                            people: {}
                        }
                    }

                    // Add photo if not duplicate
                    var photoExists = false
                    for (var k = 0; k < memories[yearsAgo].photos.length; k++) {
                        if (memories[yearsAgo].photos[k].file_path === photo.file_path) {
                            photoExists = true
                            break
                        }
                    }
                    if (!photoExists) {
                        memories[yearsAgo].photos.push(photo)
                        memories[yearsAgo].people[person.person_id] = person.name
                    }
                }
            }
        }

        // Convert to model
        for (var yearsAgo in memories) {
            var memory = memories[yearsAgo]

            // Get people names
            var peopleNames = []
            for (var personId in memory.people) {
                peopleNames.push(memory.people[personId])
            }

            memoriesModel.append({
                yearsAgo: memory.yearsAgo,
                date: memory.date,
                dateString: Qt.formatDate(memory.date, "d MMMM yyyy"),
                photoCount: memory.photos.length,
                peopleCount: peopleNames.length,
                peopleNames: peopleNames.join(", "),
                coverPhoto: memory.photos[0].file_path
            })
        }

        // Sort by years ago (most recent first)
        var memoriesList = []
        for (var m = 0; m < memoriesModel.count; m++) {
            memoriesList.push(memoriesModel.get(m))
        }
        memoriesList.sort(function(a, b) {
            return a.yearsAgo - b.yearsAgo
        })

        memoriesModel.clear()
        for (var n = 0; n < memoriesList.length; n++) {
            memoriesModel.append(memoriesList[n])
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: memoriesModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Memories")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Photos from this day in previous years")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }
        }

        delegate: BackgroundItem {
            id: memoryItem
            width: ListView.view.width
            height: Theme.itemSizeExtraLarge + Theme.paddingLarge

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingMedium

                // Cover photo with overlay
                Item {
                    width: Theme.itemSizeExtraLarge
                    height: Theme.itemSizeExtraLarge
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        anchors.fill: parent
                        source: model.coverPhoto ? "file://" + model.coverPhoto : ""
                        fillMode: Image.PreserveAspectCrop
                        clip: true
                        asynchronous: true

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Theme.rgba(Theme.highlightColor, 0.3)
                            border.width: 2
                            radius: Theme.paddingSmall
                        }

                        BusyIndicator {
                            anchors.centerIn: parent
                            running: parent.status === Image.Loading
                            size: BusyIndicatorSize.Small
                        }
                    }

                    // Years ago badge
                    Rectangle {
                        anchors {
                            bottom: parent.bottom
                            right: parent.right
                            margins: Theme.paddingSmall
                        }
                        width: yearsLabel.width + Theme.paddingMedium
                        height: yearsLabel.height + Theme.paddingSmall
                        radius: Theme.paddingSmall / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.9)

                        Label {
                            id: yearsLabel
                            anchors.centerIn: parent
                            text: model.yearsAgo + (model.yearsAgo === 1 ? qsTr(" year ago") : qsTr(" years ago"))
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.highlightColor
                        }
                    }
                }

                // Memory info
                Column {
                    width: parent.width - Theme.itemSizeExtraLarge - Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        text: model.dateString
                        color: memoryItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        font.bold: true
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.photoCount + " " + (model.photoCount === 1 ? qsTr("photo") : qsTr("photos"))
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.peopleNames
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                        visible: model.peopleCount > 0
                    }
                }
            }

            onClicked: {
                // TODO: Open memory detail page
                console.log("Memory clicked:", model.yearsAgo, "years ago")
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No memories")
            hintText: qsTr("No photos found from this day in previous years")
        }

        VerticalScrollDecorator {}
    }
}
