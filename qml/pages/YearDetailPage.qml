import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils
import "../js/eventsettings.js" as EventSettings
import "../js/eventsmodel.js" as EventsModel

// One year's recap: a month-by-month timeline of trip/event days, plus the
// year's trips and standalone event days for navigation
Page {
    id: page

    property int year: 0
    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    property var dayStatus: ({})   // "yyyy-MM-dd" -> "trip" | "day"
    property var yearTrips: []
    property var yearDays: []
    property int totalPhotoCount: 0

    property real cellSize: Math.max(8, (width - 2 * Theme.horizontalPageMargin - 3 * 30) / 31)

    function pad2(n) {
        return n < 10 ? "0" + n : "" + n
    }

    function statusForDay(month, day) {
        var key = year + "-" + pad2(month) + "-" + pad2(day)
        return dayStatus[key] || "none"
    }

    function daysInMonth(month) {
        return new Date(year, month, 0).getDate()
    }

    function loadYear() {
        if (!faceManager || !faceManager.initialized || year <= 0) return

        var eventCovers = faceManager.getEventCovers()
        var hiddenSet = EventsModel.computeHiddenSet(faceManager)
        var trips = faceManager.getTrips()
        var dateToTrip = EventsModel.computeDateToTrip(trips)
        var dateMap = EventsModel.computeDateMap(faceManager, EventSettings.includeAllPhotos(faceManager))

        var status = {}
        var photoTotal = 0
        for (var dateKey in dateMap) {
            var bucket = dateMap[dateKey]
            if (bucket.date.getFullYear() !== year) continue

            var tripId = dateToTrip[dateKey]
            if (tripId !== undefined) {
                if (hiddenSet["trip:" + tripId]) continue
                status[dateKey] = "trip"
                photoTotal += bucket.photos.length
            } else if (bucket.photos.length >= 2) {
                if (hiddenSet["day:" + dateKey]) continue
                status[dateKey] = "day"
                photoTotal += bucket.photos.length
            }
        }
        dayStatus = status
        totalPhotoCount = photoTotal

        // Trips attributed to this year (by earliest date)
        var trips_ = []
        for (var ti = 0; ti < trips.length; ti++) {
            var trip = trips[ti]
            if (hiddenSet["trip:" + trip.trip_id]) continue

            var sortedDates = trip.date_keys.slice().sort()
            if (sortedDates.length === 0) continue
            if (new Date(sortedDates[0] + "T00:00:00").getFullYear() !== year) continue

            var photoCount = 0, dayCount = 0, minDate = null, maxDate = null
            var coverPhoto = "", coverTime = 0
            for (var dk = 0; dk < trip.date_keys.length; dk++) {
                var bucket2 = dateMap[trip.date_keys[dk]]
                if (!bucket2) continue
                dayCount++
                photoCount += bucket2.photos.length
                if (!minDate || bucket2.date < minDate) minDate = bucket2.date
                if (!maxDate || bucket2.date > maxDate) maxDate = bucket2.date
                for (var bp = 0; bp < bucket2.photos.length; bp++) {
                    if (coverTime === 0 || bucket2.photos[bp].timestamp < coverTime) {
                        coverTime = bucket2.photos[bp].timestamp
                        coverPhoto = bucket2.photos[bp].file_path
                    }
                }
            }
            if (dayCount === 0) continue

            trips_.push({
                tripId: trip.trip_id,
                name: trip.name,
                dateRangeString: EventsModel.formatTripDateRange(minDate, maxDate),
                dayCount: dayCount,
                photoCount: photoCount,
                coverPhoto: eventCovers["trip:" + trip.trip_id] || coverPhoto,
                time: minDate.getTime()
            })
        }
        trips_.sort(function(a, b) { return a.time - b.time })
        yearTrips = trips_

        // Standalone event days in this year
        var days_ = []
        for (var dateKey2 in status) {
            if (status[dateKey2] !== "day") continue
            var bucket3 = dateMap[dateKey2]
            days_.push({
                dateKey: dateKey2,
                dateString: Qt.formatDate(bucket3.date, "ddd d MMM"),
                photoCount: bucket3.photos.length,
                coverPhoto: eventCovers["day:" + dateKey2] || bucket3.photos[0].file_path,
                time: bucket3.date.getTime()
            })
        }
        days_.sort(function(a, b) { return a.time - b.time })
        yearDays = days_
    }

    Component.onCompleted: loadYear()

    onStatusChanged: {
        if (status === PageStatus.Active) {
            loadYear()
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: String(year)
                description: qsTr("%1 · %2")
                    .arg(yearTrips.length === 1 ? qsTr("1 trip") : qsTr("%1 trips").arg(yearTrips.length))
                    .arg(totalPhotoCount === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(totalPhotoCount))
            }

            // Month-by-month timeline
            Column {
                width: parent.width
                spacing: Theme.paddingMedium

                Row {
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingLarge

                    Row {
                        spacing: Theme.paddingSmall / 2
                        Rectangle { width: page.cellSize; height: width; radius: 2; color: Theme.highlightColor; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: qsTr("Trip"); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor }
                    }
                    Row {
                        spacing: Theme.paddingSmall / 2
                        Rectangle { width: page.cellSize; height: width; radius: 2; color: Theme.secondaryHighlightColor; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: qsTr("Event day"); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor }
                    }
                }

                Repeater {
                    model: 12

                    delegate: Column {
                        width: column.width
                        spacing: Theme.paddingSmall / 2

                        property int month: index + 1

                        Label {
                            x: Theme.horizontalPageMargin
                            text: Qt.formatDate(new Date(year, month - 1, 1), "MMMM")
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: Theme.secondaryHighlightColor
                        }

                        Flow {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            spacing: 3

                            Repeater {
                                model: daysInMonth(month)

                                delegate: Rectangle {
                                    width: page.cellSize
                                    height: page.cellSize
                                    radius: 2

                                    property string dayState: statusForDay(month, index + 1)

                                    color: dayState === "trip" ? Theme.highlightColor
                                        : dayState === "day" ? Theme.secondaryHighlightColor
                                        : Theme.rgba(Theme.secondaryColor, 0.15)
                                }
                            }
                        }
                    }
                }
            }

            // Trips this year
            SectionHeader {
                text: qsTr("Trips")
                visible: yearTrips.length > 0
            }

            Repeater {
                model: yearTrips

                delegate: BackgroundItem {
                    id: tripItem
                    width: column.width
                    height: Theme.itemSizeExtraLarge + Theme.paddingMedium

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }
                        spacing: Theme.paddingMedium

                        Image {
                            width: Theme.itemSizeExtraLarge
                            height: Theme.itemSizeExtraLarge
                            anchors.verticalCenter: parent.verticalCenter
                            source: FaceUtils.thumbUrl(modelData.coverPhoto)
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
                        }

                        Column {
                            width: parent.width - Theme.itemSizeExtraLarge - Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall

                            Label {
                                text: modelData.name
                                color: tripItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }

                            Label {
                                text: modelData.dateRangeString + " · " + modelData.dayCount + " " + (modelData.dayCount === 1 ? qsTr("day") : qsTr("days"))
                                color: Theme.secondaryHighlightColor
                                font.pixelSize: Theme.fontSizeExtraSmall
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }

                            Label {
                                text: modelData.photoCount + " " + (modelData.photoCount === 1 ? qsTr("photo") : qsTr("photos"))
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }
                        }
                    }

                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("TripDetailPage.qml"), {
                            tripId: modelData.tripId,
                            tripName: modelData.name
                        })
                    }
                }
            }

            // Standalone event days this year
            SectionHeader {
                text: qsTr("Other event days")
                visible: yearDays.length > 0
            }

            Repeater {
                model: yearDays

                delegate: BackgroundItem {
                    id: dayItem
                    width: column.width
                    height: Theme.itemSizeLarge

                    Row {
                        anchors {
                            fill: parent
                            leftMargin: Theme.horizontalPageMargin
                            rightMargin: Theme.horizontalPageMargin
                        }
                        spacing: Theme.paddingMedium

                        Image {
                            width: Theme.itemSizeMedium
                            height: Theme.itemSizeMedium
                            anchors.verticalCenter: parent.verticalCenter
                            source: FaceUtils.thumbUrl(modelData.coverPhoto)
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
                        }

                        Column {
                            width: parent.width - Theme.itemSizeMedium - Theme.paddingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.paddingSmall

                            Label {
                                text: modelData.dateString
                                color: dayItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                font.pixelSize: Theme.fontSizeMedium
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }

                            Label {
                                text: modelData.photoCount + " " + (modelData.photoCount === 1 ? qsTr("photo") : qsTr("photos"))
                                color: Theme.secondaryColor
                                font.pixelSize: Theme.fontSizeSmall
                                truncationMode: TruncationMode.Fade
                                width: parent.width
                            }
                        }
                    }

                    onClicked: {
                        pageStack.push(Qt.resolvedUrl("DayPhotosPage.qml"), {
                            dateKey: modelData.dateKey,
                            title: modelData.dateString
                        })
                    }
                }
            }

            ViewPlaceholder {
                enabled: yearTrips.length === 0 && yearDays.length === 0
                text: qsTr("No events this year")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
