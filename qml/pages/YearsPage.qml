import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/eventsettings.js" as EventSettings
import "../js/eventsmodel.js" as EventsModel

// Year-by-year recap: trips, event days and photos per year, most recent first
Page {
    id: page

    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    ListModel {
        id: yearsModel
    }

    function computeYearStats() {
        if (!faceManager || !faceManager.initialized) return []

        var dateMap = EventsModel.computeDateMap(faceManager, EventSettings.includeAllPhotos(faceManager))
        var hiddenSet = EventsModel.computeHiddenSet(faceManager)
        var trips = faceManager.getTrips()
        var dateToTrip = EventsModel.computeDateToTrip(trips)

        var yearStats = {}
        function statsFor(year) {
            if (!yearStats[year]) {
                yearStats[year] = { trips: 0, days: 0, photos: 0 }
            }
            return yearStats[year]
        }

        // Event days and photos, attributed to the calendar year of the date itself
        for (var dateKey in dateMap) {
            var bucket = dateMap[dateKey]
            var tripId = dateToTrip[dateKey]
            var qualifies = false
            if (tripId !== undefined) {
                qualifies = !hiddenSet["trip:" + tripId]
            } else if (bucket.photos.length >= 2) {
                qualifies = !hiddenSet["day:" + dateKey]
            }
            if (!qualifies) continue

            var stat = statsFor(bucket.date.getFullYear())
            stat.days++
            stat.photos += bucket.photos.length
        }

        // Trip counts, attributed to the year of the trip's earliest date
        for (var ti = 0; ti < trips.length; ti++) {
            var trip = trips[ti]
            if (hiddenSet["trip:" + trip.trip_id]) continue

            var hasPhotos = false
            for (var dk = 0; dk < trip.date_keys.length; dk++) {
                if (dateMap[trip.date_keys[dk]]) {
                    hasPhotos = true
                    break
                }
            }
            if (!hasPhotos) continue

            var sortedDates = trip.date_keys.slice().sort()
            var firstYear = new Date(sortedDates[0] + "T00:00:00").getFullYear()
            statsFor(firstYear).trips++
        }

        var years = []
        for (var yearKey in yearStats) {
            years.push({
                year: parseInt(yearKey),
                trips: yearStats[yearKey].trips,
                days: yearStats[yearKey].days,
                photos: yearStats[yearKey].photos
            })
        }
        years.sort(function(a, b) { return b.year - a.year })
        return years
    }

    function refresh() {
        yearsModel.clear()
        var years = computeYearStats()
        for (var i = 0; i < years.length; i++) {
            yearsModel.append(years[i])
        }
    }

    Component.onCompleted: refresh()

    onStatusChanged: {
        if (status === PageStatus.Active) {
            refresh()
        }
    }

    SilicaListView {
        id: listView
        anchors.fill: parent

        model: yearsModel

        header: Column {
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Year in review")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("A recap of your trips and events, year by year")
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
            id: yearItem
            width: ListView.view.width
            height: Theme.itemSizeLarge

            Column {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: Theme.horizontalPageMargin
                    rightMargin: Theme.horizontalPageMargin
                }
                spacing: Theme.paddingSmall

                Label {
                    text: model.year
                    color: yearItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    font.pixelSize: Theme.fontSizeExtraLarge
                    font.bold: true
                }

                Label {
                    width: parent.width
                    text: qsTr("%1 · %2 · %3")
                        .arg(model.trips === 1 ? qsTr("1 trip") : qsTr("%1 trips").arg(model.trips))
                        .arg(model.days === 1 ? qsTr("1 event day") : qsTr("%1 event days").arg(model.days))
                        .arg(model.photos === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(model.photos))
                    color: Theme.secondaryColor
                    font.pixelSize: Theme.fontSizeSmall
                    truncationMode: TruncationMode.Fade
                }
            }

            onClicked: {
                pageStack.push(Qt.resolvedUrl("YearDetailPage.qml"), {
                    year: model.year
                })
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No events yet")
            hintText: qsTr("Your yearly recap appears once you have a few events")
        }

        VerticalScrollDecorator {}
    }
}
