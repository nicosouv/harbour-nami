import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"

// All photos of a trip (several days grouped together), with a choice of
// browsing them by day or by geographic stop, plus a schematic route map.
Page {
    id: page

    property int tripId: -1
    property string tripName: ""
    property var faceManager: facePipeline

    allowedOrientations: Orientation.All

    property string sortMode: "day"   // "day" or "location"
    property var groups: []
    property var routePoints: []
    property int totalPhotoCount: 0
    property bool hasLocationData: false

    function loadTrip() {
        if (!faceManager || !faceManager.initialized || tripId < 0) return

        var trips = faceManager.getTrips()
        var dateKeys = []
        for (var t = 0; t < trips.length; t++) {
            if (trips[t].trip_id === tripId) {
                tripName = trips[t].name
                dateKeys = trips[t].date_keys
                break
            }
        }

        var dateSet = {}
        for (var d = 0; d < dateKeys.length; d++) {
            dateSet[dateKeys[d]] = true
        }

        // Collect this trip's photos across every person, deduplicated
        var seen = {}
        var items = []
        var people = faceManager.getAllPeople()
        for (var i = 0; i < people.length; i++) {
            var photos = faceManager.getPersonPhotos(people[i].person_id)
            for (var j = 0; j < photos.length; j++) {
                var photo = photos[j]
                if (!photo.timestamp || seen[photo.file_path]) continue
                var key = Qt.formatDate(new Date(photo.timestamp * 1000), "yyyy-MM-dd")
                if (dateSet[key]) {
                    seen[photo.file_path] = true
                    items.push({
                        file_path: photo.file_path,
                        timestamp: photo.timestamp,
                        dateKey: key,
                        has_location: !!photo.has_location,
                        latitude: photo.latitude,
                        longitude: photo.longitude
                    })
                }
            }
        }

        items.sort(function(a, b) { return a.timestamp - b.timestamp })
        totalPhotoCount = items.length

        var located = []
        for (var n = 0; n < items.length; n++) {
            if (items[n].has_location) {
                located.push({ latitude: items[n].latitude, longitude: items[n].longitude })
            }
        }
        routePoints = located
        hasLocationData = located.length > 0

        groups = sortMode === "location" ? groupByLocation(items) : groupByDay(items)
    }

    function groupByDay(items) {
        var byDay = {}
        var order = []
        for (var i = 0; i < items.length; i++) {
            var key = items[i].dateKey
            if (!byDay[key]) {
                byDay[key] = []
                order.push(key)
            }
            byDay[key].push(items[i])
        }
        order.sort()

        var result = []
        for (var j = 0; j < order.length; j++) {
            result.push({
                title: Qt.formatDate(new Date(order[j] + "T00:00:00"), "ddd d MMM yyyy"),
                photos: byDay[order[j]]
            })
        }
        return result
    }

    // Greedy single-pass clustering in chronological order: a photo joins
    // the current stop when it's within ~1.5km of it, otherwise a new stop
    // starts. No reverse geocoding (the app is fully offline), so stops are
    // just numbered in visit order rather than named.
    function groupByLocation(items) {
        var clusterKm = 1.5
        var clusters = []
        var noLocation = []

        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!it.has_location) {
                noLocation.push(it)
                continue
            }
            var cluster = clusters.length > 0 ? clusters[clusters.length - 1] : null
            if (cluster && haversineKm(cluster.lastLat, cluster.lastLon, it.latitude, it.longitude) <= clusterKm) {
                cluster.photos.push(it)
                cluster.lastLat = it.latitude
                cluster.lastLon = it.longitude
            } else {
                clusters.push({ photos: [it], lastLat: it.latitude, lastLon: it.longitude })
            }
        }

        var result = []
        for (var c = 0; c < clusters.length; c++) {
            var count = clusters[c].photos.length
            result.push({
                title: qsTr("Stop %1").arg(c + 1) + " · " + (count === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(count)),
                photos: clusters[c].photos
            })
        }
        if (noLocation.length > 0) {
            result.push({ title: qsTr("No location data"), photos: noLocation })
        }
        return result
    }

    function haversineKm(lat1, lon1, lat2, lon2) {
        var r = 6371
        var dLat = (lat2 - lat1) * Math.PI / 180
        var dLon = (lon2 - lon1) * Math.PI / 180
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180)
                * Math.sin(dLon / 2) * Math.sin(dLon / 2)
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return r * c
    }

    Component.onCompleted: loadTrip()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: sortMode === "day" ? qsTr("Sort by location") : qsTr("Sort by day")
                enabled: hasLocationData
                onClicked: {
                    sortMode = sortMode === "day" ? "location" : "day"
                    loadTrip()
                }
            }
            MenuItem {
                text: qsTr("Rename trip")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/TripNameDialog.qml"), {
                        titleText: qsTr("Rename trip"),
                        currentName: tripName
                    })
                    dialog.accepted.connect(function() {
                        faceManager.renameTrip(tripId, dialog.newName)
                        tripName = dialog.newName
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: tripName
                description: totalPhotoCount + " " + (totalPhotoCount === 1 ? qsTr("photo") : qsTr("photos"))
            }

            TripRouteMap {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                points: routePoints
            }

            Repeater {
                model: groups

                delegate: Column {
                    width: column.width
                    spacing: Theme.paddingSmall

                    SectionHeader {
                        text: modelData.title
                    }

                    Grid {
                        id: photoGrid
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        columns: 3
                        spacing: Theme.paddingSmall

                        Repeater {
                            model: modelData.photos

                            delegate: BackgroundItem {
                                width: photoGrid.width / 3
                                height: width

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Theme.paddingSmall / 2
                                    source: modelData.file_path ? "file://" + modelData.file_path : ""
                                    fillMode: Image.PreserveAspectCrop
                                    autoTransform: true
                                    clip: true
                                    asynchronous: true
                                    sourceSize.width: 400
                                    sourceSize.height: 400

                                    BusyIndicator {
                                        anchors.centerIn: parent
                                        running: parent.status === Image.Loading
                                        size: BusyIndicatorSize.Small
                                    }
                                }

                                onClicked: {
                                    pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                        photoPath: modelData.file_path
                                    })
                                }
                            }
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: totalPhotoCount === 0
                text: qsTr("No photos")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
