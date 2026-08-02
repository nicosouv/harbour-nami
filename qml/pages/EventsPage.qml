import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/geoutils.js" as GeoUtils
import "../js/eventsettings.js" as EventSettings
import "../js/eventsmodel.js" as EventsModel

Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    // Events model: single-day events plus multi-day trips, most recent first
    ListModel {
        id: eventsModel
    }

    // Suggested trips: runs of consecutive "away from home" days not yet
    // grouped, offered for one-tap grouping
    ListModel {
        id: suggestionsModel
    }

    // Selection mode: pick several day-events to combine into a trip, or
    // (when editingTripId >= 0) to add more days to an existing trip
    property bool selectionMode: false
    property var selectedDates: []
    property int selectableDayCount: 0
    property int editingTripId: -1

    // Hidden day/trip events stay out of the list unless toggled on
    property bool showHidden: false

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
        editingTripId = -1
        selectionMode = true
    }

    // Reuses the same day-picker, but confirming adds to an existing trip
    // instead of naming a new one
    function enterAddDaysMode(tripId) {
        selectedDates = []
        editingTripId = tripId
        selectionMode = true
    }

    function exitSelectionMode() {
        selectionMode = false
        selectedDates = []
        editingTripId = -1
    }

    function confirmSelection() {
        if (editingTripId >= 0) {
            faceManager.addDatesToTrip(editingTripId, selectedDates)
            exitSelectionMode()
            detectEvents()
        } else {
            groupSelectedDates()
        }
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

    // === Trip suggestions: dates far from "home" grouped into candidate trips ===

    // Parallel to suggestionsModel (kept in sync by index): the date keys
    // are not stored as a model role, since dynamically appending a plain
    // JS array as a role value doesn't reliably behave like a nested
    // ListModel with .get()/.count
    property var suggestionDateKeysByRow: []

    function loadDismissedSuggestions() {
        var raw = faceManager.getSetting("dismissed_trip_suggestions", "")
        return raw.length > 0 ? raw.split("\n") : []
    }

    function dismissSuggestionAt(row) {
        var signature = suggestionsModel.get(row).signature
        var dismissed = loadDismissedSuggestions()
        if (dismissed.indexOf(signature) === -1) {
            dismissed.push(signature)
            faceManager.setSetting("dismissed_trip_suggestions", dismissed.join("\n"))
        }
        suggestionsModel.remove(row)
        suggestionDateKeysByRow.splice(row, 1)
    }

    function groupSuggestionAt(row) {
        var dateKeys = suggestionDateKeysByRow[row]

        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/TripNameDialog.qml"), {
            titleText: qsTr("Name this trip")
        })
        dialog.accepted.connect(function() {
            faceManager.createTrip(dialog.newName, dateKeys)
            detectEvents()
        })
    }

    // Cluster located day-centroids (5km) and return the one covering the
    // most distinct days: a proxy for "home" without any manual setup
    function computeHomeCentroid(dateMap) {
        var dayCentroids = []
        for (var dateKey in dateMap) {
            var bucket = dateMap[dateKey]
            var sumLat = 0, sumLon = 0, n = 0
            for (var i = 0; i < bucket.photos.length; i++) {
                var photo = bucket.photos[i]
                if (photo.has_location) {
                    sumLat += photo.latitude
                    sumLon += photo.longitude
                    n++
                }
            }
            if (n > 0) {
                dayCentroids.push({ lat: sumLat / n, lon: sumLon / n })
            }
        }
        if (dayCentroids.length === 0) return null

        var clusters = []
        for (var d = 0; d < dayCentroids.length; d++) {
            var dc = dayCentroids[d]
            var matched = null
            for (var c = 0; c < clusters.length; c++) {
                if (GeoUtils.haversineKm(clusters[c].lat, clusters[c].lon, dc.lat, dc.lon) <= 5) {
                    matched = clusters[c]
                    break
                }
            }
            if (matched) {
                matched.sumLat += dc.lat
                matched.sumLon += dc.lon
                matched.count++
                matched.lat = matched.sumLat / matched.count
                matched.lon = matched.sumLon / matched.count
            } else {
                clusters.push({ lat: dc.lat, lon: dc.lon, sumLat: dc.lat, sumLon: dc.lon, count: 1 })
            }
        }

        clusters.sort(function(a, b) { return b.count - a.count })
        return clusters[0]
    }

    // Runs of consecutive (gap <= 2 days) ungrouped days whose photos sit
    // far from home; each run of 2+ days becomes a dismissible suggestion
    function computeTripSuggestions(dateMap, dateToTrip) {
        var home = computeHomeCentroid(dateMap)
        if (!home || home.count < 5) return []

        var AWAY_KM = 40
        var awayDates = []
        var sortedKeys = Object.keys(dateMap).sort()
        for (var i = 0; i < sortedKeys.length; i++) {
            var dateKey = sortedKeys[i]
            if (dateToTrip[dateKey]) continue
            var bucket = dateMap[dateKey]
            if (bucket.photos.length < 2) continue

            var sumLat = 0, sumLon = 0, n = 0
            for (var p = 0; p < bucket.photos.length; p++) {
                var photo = bucket.photos[p]
                if (photo.has_location) {
                    sumLat += photo.latitude
                    sumLon += photo.longitude
                    n++
                }
            }
            if (n === 0) continue

            if (GeoUtils.haversineKm(home.lat, home.lon, sumLat / n, sumLon / n) > AWAY_KM) {
                awayDates.push(dateKey)
            }
        }

        var runs = []
        var current = []
        for (var d = 0; d < awayDates.length; d++) {
            if (current.length === 0) {
                current.push(awayDates[d])
            } else {
                var prevDate = new Date(current[current.length - 1] + "T00:00:00")
                var curDate = new Date(awayDates[d] + "T00:00:00")
                var gapDays = Math.round((curDate.getTime() - prevDate.getTime()) / 86400000)
                if (gapDays <= 2) {
                    current.push(awayDates[d])
                } else {
                    runs.push(current)
                    current = [awayDates[d]]
                }
            }
        }
        if (current.length > 0) runs.push(current)

        var dismissed = loadDismissedSuggestions()
        var suggestions = []
        for (var r = 0; r < runs.length; r++) {
            if (runs[r].length < 2) continue
            var signature = runs[r][0] + "_" + runs[r][runs[r].length - 1]
            if (dismissed.indexOf(signature) !== -1) continue

            var minD = new Date(runs[r][0] + "T00:00:00")
            var maxD = new Date(runs[r][runs[r].length - 1] + "T00:00:00")
            suggestions.push({
                signature: signature,
                rangeString: formatTripDateRange(minD, maxD),
                dayCount: runs[r].length,
                dateKeys: runs[r]
            })
        }
        return suggestions
    }

    function refreshSuggestions(dateMap, dateToTrip) {
        suggestionsModel.clear()
        var suggestions = computeTripSuggestions(dateMap, dateToTrip)
        var keysByRow = []
        for (var i = 0; i < suggestions.length; i++) {
            suggestionsModel.append({
                signature: suggestions[i].signature,
                rangeString: suggestions[i].rangeString,
                dayCount: suggestions[i].dayCount
            })
            keysByRow.push(suggestions[i].dateKeys)
        }
        suggestionDateKeysByRow = keysByRow
    }

    Component.onCompleted: {
        detectEvents()
    }

    // Refresh when coming back from a day/trip page: covers, renames and
    // merges done there would otherwise not show until next app start
    onStatusChanged: {
        if (status === PageStatus.Active) {
            detectEvents()
        }
    }

    // Same month/year collapse to a short range; different years spell both out
    function formatTripDateRange(minDate, maxDate) {
        return EventsModel.formatTripDateRange(minDate, maxDate)
    }

    // Group photos by date, then fold dates already grouped into a trip
    // into a single trip row instead of listing them separately
    function detectEvents() {
        if (!faceManager || !faceManager.initialized) return

        eventsModel.clear()

        var eventCovers = faceManager.getEventCovers()
        var hiddenSet = EventsModel.computeHiddenSet(faceManager)
        var trips = faceManager.getTrips()
        var dateToTripId = EventsModel.computeDateToTrip(trips)
        var dateToTrip = {}
        for (var dk0 in dateToTripId) {
            dateToTrip[dk0] = true
        }

        var dateMap = EventsModel.computeDateMap(faceManager, EventSettings.includeAllPhotos(faceManager))

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

            var tripKey = "trip:" + trip.trip_id
            var tripHidden = hiddenSet[tripKey] === true
            if (tripHidden && !showHidden) continue

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
                coverPhoto: eventCovers["trip:" + trip.trip_id] || coverPhoto,
                hidden: tripHidden
            })
        }

        // Standalone day rows: everything not folded into a trip
        var dayCountAvailable = 0
        for (var dateKey in dateMap) {
            if (dateToTrip[dateKey]) continue
            var event = dateMap[dateKey]
            if (event.photos.length >= 2) {
                var dayKey = "day:" + dateKey
                var dayHidden = hiddenSet[dayKey] === true
                if (!dayHidden) dayCountAvailable++  // hidden days aren't offered for grouping
                if (dayHidden && !showHidden) continue

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
                    coverPhoto: eventCovers["day:" + dateKey] || event.photos[0].file_path,
                    hidden: dayHidden
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

        refreshSuggestions(dateMap, dateToTrip)
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
                    ? (editingTripId >= 0
                        ? qsTr("Select the days to add to this trip")
                        : qsTr("Select the days to combine into a trip"))
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
                    text: editingTripId >= 0
                        ? qsTr("Add %n day(s)", "", selectedDates.length)
                        : qsTr("Group %n day(s)", "", selectedDates.length)
                    enabled: editingTripId >= 0 ? selectedDates.length >= 1 : selectedDates.length >= 2
                    onClicked: confirmSelection()
                }
            }

            // Suggested trips: days far from home, not yet grouped
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: !selectionMode && suggestionsModel.count > 0

                Repeater {
                    model: suggestionsModel

                    delegate: Item {
                        width: parent.width
                        height: banner.height

                        Rectangle {
                            id: banner
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            height: bannerColumn.height + 2 * Theme.paddingMedium
                            radius: Theme.paddingSmall
                            color: Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                            border.color: Theme.rgba(Theme.highlightColor, 0.3)
                            border.width: 1

                            Column {
                                id: bannerColumn
                                width: parent.width - 2 * Theme.paddingMedium
                                anchors.centerIn: parent
                                spacing: Theme.paddingSmall

                                Label {
                                    width: parent.width
                                    text: qsTr("Suggested trip: %1 (%2)").arg(model.rangeString)
                                        .arg(model.dayCount === 1 ? qsTr("1 day") : qsTr("%1 days").arg(model.dayCount))
                                    color: Theme.highlightColor
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.WordWrap
                                }

                                Row {
                                    spacing: Theme.paddingMedium

                                    Button {
                                        text: qsTr("Dismiss")
                                        onClicked: dismissSuggestionAt(index)
                                    }

                                    Button {
                                        text: qsTr("Group")
                                        onClicked: groupSuggestionAt(index)
                                    }
                                }
                            }
                        }
                    }
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
                text: qsTr("Year in review")
                onClicked: pageStack.push(Qt.resolvedUrl("YearsPage.qml"))
            }
            MenuItem {
                text: qsTr("Select days to group into a trip")
                enabled: selectableDayCount >= 2
                onClicked: enterSelectionMode()
            }
            MenuItem {
                text: showHidden ? qsTr("Hide hidden events") : qsTr("Show hidden events")
                onClicked: {
                    showHidden = !showHidden
                    detectEvents()
                }
            }
        }

        delegate: ListItem {
            id: eventItem
            width: ListView.view.width
            contentHeight: Theme.itemSizeExtraLarge + Theme.paddingMedium
            enabled: (model.type === "day" && !model.hidden) || !selectionMode
            opacity: model.hidden ? 0.5 : ((selectionMode && model.type === "trip") ? 0.4 : 1.0)

            menu: ContextMenu {
                MenuItem {
                    text: qsTr("Rename")
                    visible: model.type === "trip" && !model.hidden
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
                    text: qsTr("Add more days…")
                    visible: model.type === "trip" && !model.hidden
                    onClicked: enterAddDaysMode(model.tripId)
                }
                MenuItem {
                    text: qsTr("Merge into another trip…")
                    visible: model.type === "trip" && !model.hidden
                    onClicked: {
                        var tid = model.tripId
                        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectTripDialog.qml"), {
                            trips: faceManager.getTrips(),
                            excludeTripId: tid
                        })
                        dialog.accepted.connect(function() {
                            faceManager.mergeTrips(tid, dialog.selectedTripId)
                            detectEvents()
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Ungroup")
                    visible: model.type === "trip" && !model.hidden
                    onClicked: {
                        var tid = model.tripId
                        Remorse.popupAction(page, qsTr("Ungrouping trip"), function() {
                            faceManager.deleteTrip(tid)
                            detectEvents()
                        })
                    }
                }
                MenuItem {
                    text: qsTr("Hide")
                    visible: !model.hidden
                    onClicked: {
                        faceManager.hideEvent(model.type === "trip" ? ("trip:" + model.tripId) : ("day:" + model.dateKey))
                        detectEvents()
                    }
                }
                MenuItem {
                    text: qsTr("Unhide")
                    visible: model.hidden
                    onClicked: {
                        faceManager.unhideEvent(model.type === "trip" ? ("trip:" + model.tripId) : ("day:" + model.dateKey))
                        detectEvents()
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

                    // Hidden badge
                    Rectangle {
                        anchors {
                            top: parent.top
                            right: parent.right
                            margins: Theme.paddingSmall / 2
                        }
                        visible: model.hidden
                        width: hiddenBadgeLabel.width + Theme.paddingSmall
                        height: hiddenBadgeLabel.height + Theme.paddingSmall / 2
                        radius: Theme.paddingSmall / 2
                        color: Theme.rgba(Theme.secondaryColor, 0.85)

                        Label {
                            id: hiddenBadgeLabel
                            anchors.centerIn: parent
                            text: qsTr("Hidden")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            font.bold: true
                            color: Theme.primaryColor
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
