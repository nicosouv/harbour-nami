import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Events model: single-day events plus multi-day trips, most recent first
    ListModel {
        id: eventsModel
    }

    // Selection mode: pick several day-events to combine into a trip
    property bool selectionMode: false
    property var selectedDates: []
    property int selectableDayCount: 0

    function isDateSelected(dateKey) {
        return selectedDates.indexOf(dateKey) !== -1
    }

    function toggleDateSelection(dateKey) {
        var idx = selectedDates.indexOf(dateKey)
        var copy = selectedDates.slice()
        if (idx === -1) {
            copy.push(dateKey)
        } else {
            copy.splice(idx, 1)
        }
        selectedDates = copy
    }

    function enterSelectionMode() {
        selectedDates = []
        selectionMode = true
    }

    function exitSelectionMode() {
        selectionMode = false
        selectedDates = []
    }

    function groupSelectedDates() {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/TripNameDialog.qml"), {
            titleText: qsTr("Name this trip")
        })
        dialog.accepted.connect(function() {
            faceManager.createTrip(dialog.newName, selectedDates)
            exitSelectionMode()
            detectEvents()
        })
    }

    Component.onCompleted: {
        detectEvents()
    }

    // Same month/year collapse to a short range; different years spell both out
    function formatTripDateRange(minDate, maxDate) {
        if (minDate.getFullYear() === maxDate.getFullYear()) {
            if (minDate.getMonth() === maxDate.getMonth() && minDate.getDate() === maxDate.getDate()) {
                return Qt.formatDate(minDate, "d MMM yyyy")
            }
            if (minDate.getMonth() === maxDate.getMonth()) {
                return Qt.formatDate(minDate, "d") + "–" + Qt.formatDate(maxDate, "d MMM yyyy")
            }
            return Qt.formatDate(minDate, "d MMM") + " – " + Qt.formatDate(maxDate, "d MMM yyyy")
        }
        return Qt.formatDate(minDate, "d MMM yyyy") + " – " + Qt.formatDate(maxDate, "d MMM yyyy")
    }

    // Group photos by date, then fold dates already grouped into a trip
    // into a single trip row instead of listing them separately
    function detectEvents() {
        if (!faceManager || !faceManager.initialized) return

        eventsModel.clear()

        var trips = faceManager.getTrips()
        var dateToTrip = {}
        for (var t = 0; t < trips.length; t++) {
            for (var td = 0; td < trips[t].date_keys.length; td++) {
                dateToTrip[trips[t].date_keys[td]] = true
            }
        }

        var people = faceManager.getAllPeople()
        var dateMap = {}  // dateKey -> { date, people: Set, photos: Array }

        for (var i = 0; i < people.length; i++) {
            var person = people[i]
            var photos = faceManager.getPersonPhotos(person.person_id)

            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp) continue

                var date = new Date(photo.timestamp * 1000)
                var dateKey = Qt.formatDate(date, "yyyy-MM-dd")

                if (!dateMap[dateKey]) {
                    dateMap[dateKey] = { date: date, people: {}, photos: [] }
                }

                dateMap[dateKey].people[person.person_id] = person.name

                var photoExists = false
                for (var k = 0; k < dateMap[dateKey].photos.length; k++) {
                    if (dateMap[dateKey].photos[k].file_path === photo.file_path) {
                        photoExists = true
                        break
                    }
                }
                if (!photoExists) {
                    dateMap[dateKey].photos.push(photo)
                }
            }
        }

        var events = []

        // Trip rows: fold every date belonging to the trip into one entry
        for (var ti = 0; ti < trips.length; ti++) {
            var trip = trips[ti]
            var tripPhotoCount = 0
            var tripPeople = {}
            var minDate = null, maxDate = null
            var coverPhoto = ""
            var coverTime = 0
            var dayCount = 0

            for (var dk = 0; dk < trip.date_keys.length; dk++) {
                var bucket = dateMap[trip.date_keys[dk]]
                if (!bucket) continue
                dayCount++
                tripPhotoCount += bucket.photos.length
                for (var pid in bucket.people) {
                    tripPeople[pid] = bucket.people[pid]
                }
                if (!minDate || bucket.date < minDate) minDate = bucket.date
                if (!maxDate || bucket.date > maxDate) maxDate = bucket.date

                for (var bp = 0; bp < bucket.photos.length; bp++) {
                    if (coverTime === 0 || bucket.photos[bp].timestamp < coverTime) {
                        coverTime = bucket.photos[bp].timestamp
                        coverPhoto = bucket.photos[bp].file_path
                    }
                }
            }

            if (dayCount === 0) continue  // none of the trip's dates have photos yet

            var tripPeopleNames = []
            for (var tpid in tripPeople) {
                tripPeopleNames.push(tripPeople[tpid])
            }

            events.push({
                type: "trip",
                dateKey: "",
                tripId: trip.trip_id,
                name: trip.name,
                time: maxDate.getTime(),
                dateString: "",
                dateRangeString: formatTripDateRange(minDate, maxDate),
                dayCount: dayCount,
                photoCount: tripPhotoCount,
                peopleCount: tripPeopleNames.length,
                peopleNames: tripPeopleNames.join(", "),
                coverPhoto: coverPhoto
            })
        }

        // Standalone day rows: everything not folded into a trip
        var dayCountAvailable = 0
        for (var dateKey in dateMap) {
            if (dateToTrip[dateKey]) continue
            var event = dateMap[dateKey]
            if (event.photos.length >= 2) {
                dayCountAvailable++
                var dayPeopleNames = []
                for (var personId in event.people) {
                    dayPeopleNames.push(event.people[personId])
                }

                events.push({
                    type: "day",
                    dateKey: dateKey,
                    tripId: -1,
                    name: "",
                    time: event.date.getTime(),
                    dateString: Qt.formatDate(event.date, "ddd d MMM yyyy"),
                    dateRangeString: "",
                    dayCount: 1,
                    photoCount: event.photos.length,
                    peopleCount: dayPeopleNames.length,
                    peopleNames: dayPeopleNames.join(", "),
                    coverPhoto: event.photos[0].file_path
                })
            }
        }
        selectableDayCount = dayCountAvailable

        // Sort by date (most recent first)
        events.sort(function(a, b) {
            return b.time - a.time
        })

        for (var n = 0; n < events.length; n++) {
            eventsModel.append(events[n])
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: eventsModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Events")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: selectionMode
                    ? qsTr("Select the days to combine into a trip")
                    : qsTr("Photos automatically grouped by date. Group several days into a trip for a multi-day event.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                wrapMode: Text.WordWrap
            }

            Row {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                visible: selectionMode

                Button {
                    text: qsTr("Cancel")
                    onClicked: exitSelectionMode()
                }

                Button {
                    text: qsTr("Group %n day(s)", "", selectedDates.length)
                    enabled: selectedDates.length >= 2
                    onClicked: groupSelectedDates()
                }
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }
        }

        PullDownMenu {
            visible: !selectionMode
            MenuItem {
                text: qsTr("Select days to group into a trip")
                enabled: selectableDayCount >= 2
                onClicked: enterSelectionMode()
            }
        }

        delegate: ListItem {
            id: eventItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeExtraLarge + Theme.paddingMedium
            enabled: model.type === "day" || !selectionMode
            opacity: (selectionMode && model.type === "trip") ? 0.4 : 1.0

            menu: model.type === "trip" ? tripContextMenu : null

            Component {
                id: tripContextMenu

                ContextMenu {
                    MenuItem {
                        text: qsTr("Rename")
                        onClicked: {
                            var tid = model.tripId
                            var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/TripNameDialog.qml"), {
                                titleText: qsTr("Rename trip"),
                                currentName: model.name
                            })
                            dialog.accepted.connect(function() {
                                faceManager.renameTrip(tid, dialog.newName)
                                detectEvents()
                            })
                        }
                    }
                    MenuItem {
                        text: qsTr("Ungroup")
                        onClicked: {
                            var tid = model.tripId
                            eventItem.remorseAction(qsTr("Ungrouping trip"), function() {
                                faceManager.deleteTrip(tid)
                                detectEvents()
                            })
                        }
                    }
                }
            }

            Row {
                anchors {
                    fill: parent
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingMedium

                // Selection indicator (day rows only, selection mode only)
                Item {
                    width: selectionMode && model.type === "day" ? Theme.iconSizeMedium : 0
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    visible: selectionMode && model.type === "day"

                    Rectangle {
                        anchors.centerIn: parent
                        width: Theme.iconSizeSmall
                        height: width
                        radius: width / 2
                        color: isDateSelected(model.dateKey) ? Theme.highlightColor : "transparent"
                        border.color: Theme.highlightColor
                        border.width: 1

                        Label {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.primaryColor
                            visible: isDateSelected(model.dateKey)
                        }
                    }
                }

                // Cover photo
                Image {
                    width: Theme.itemSizeExtraLarge
                    height: Theme.itemSizeExtraLarge
                    anchors.verticalCenter: parent.verticalCenter
                    source: model.coverPhoto ? "file://" + model.coverPhoto : ""
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    clip: true
                    asynchronous: true

                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Theme.rgba(Theme.highlightColor, 0.2)
                        border.width: 1
                        radius: Theme.paddingSmall
                    }

                    // Trip badge
                    Rectangle {
                        anchors {
                            top: parent.top
                            left: parent.left
                            margins: Theme.paddingSmall / 2
                        }
                        visible: model.type === "trip"
                        width: tripBadgeLabel.width + Theme.paddingSmall
                        height: tripBadgeLabel.height + Theme.paddingSmall / 2
                        radius: Theme.paddingSmall / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.85)

                        Label {
                            id: tripBadgeLabel
                            anchors.centerIn: parent
                            text: qsTr("Trip")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.highlightColor
                        }
                    }

                    BusyIndicator {
                        anchors.centerIn: parent
                        running: parent.status === Image.Loading
                        size: BusyIndicatorSize.Small
                    }
                }

                // Event info
                Column {
                    width: parent.width - Theme.itemSizeExtraLarge - Theme.paddingMedium
                        - (selectionMode && model.type === "day" ? Theme.iconSizeMedium + parent.spacing : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        text: model.type === "trip" ? model.name : model.dateString
                        color: eventItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeMedium
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }

                    Label {
                        text: model.type === "trip"
                            ? model.dateRangeString + " · " + model.dayCount + " " + (model.dayCount === 1 ? qsTr("day") : qsTr("days"))
                            : ""
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                        visible: model.type === "trip"
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
                if (selectionMode) {
                    if (model.type === "day") {
                        toggleDateSelection(model.dateKey)
                    }
                    return
                }

                if (model.type === "trip") {
                    pageStack.push(Qt.resolvedUrl("TripDetailPage.qml"), {
                        tripId: model.tripId,
                        tripName: model.name
                    })
                } else {
                    pageStack.push(Qt.resolvedUrl("DayPhotosPage.qml"), {
                        dateKey: model.dateKey,
                        title: model.dateString
                    })
                }
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No events detected")
            hintText: qsTr("Events are created when you have multiple photos from the same day")
        }

        VerticalScrollDecorator {}
    }
}
