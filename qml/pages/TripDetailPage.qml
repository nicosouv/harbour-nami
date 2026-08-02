import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/geoutils.js" as GeoUtils
import "../js/eventsettings.js" as EventSettings

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
    property var mapStops: []
    property int totalPhotoCount: 0
    property bool hasLocationData: false
    property real distanceKm: 0
    property string coverPath: ""

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

        coverPath = faceManager.getEventCovers()["trip:" + tripId] || ""

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

        // Optionally add photos with no identified person too
        if (EventSettings.includeAllPhotos(faceManager)) {
            var allPhotos = faceManager.getAllPhotos()
            for (var ap = 0; ap < allPhotos.length; ap++) {
                var extraPhoto = allPhotos[ap]
                if (!extraPhoto.timestamp || seen[extraPhoto.file_path]) continue
                var extraKey = Qt.formatDate(new Date(extraPhoto.timestamp * 1000), "yyyy-MM-dd")
                if (dateSet[extraKey]) {
                    seen[extraPhoto.file_path] = true
                    items.push({
                        file_path: extraPhoto.file_path,
                        timestamp: extraPhoto.timestamp,
                        dateKey: extraKey,
                        has_location: !!extraPhoto.has_location,
                        latitude: extraPhoto.latitude,
                        longitude: extraPhoto.longitude
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

        // A single photo with a corrupted GPS tag (camera/phone GPS glitches
        // happen) would otherwise blow up the map's viewport and the
        // distance total to cover half a continent. Drop points far outside
        // where the rest of the trip actually is before using them for the
        // map, the route, or the distance - the photo itself still shows up
        // normally in the grid below, it's just not trusted for location.
        located = rejectLocationOutliers(located)

        routePoints = located
        hasLocationData = located.length > 0

        var totalKm = 0
        for (var k = 1; k < located.length; k++) {
            totalKm += GeoUtils.haversineKm(located[k - 1].latitude, located[k - 1].longitude,
                                             located[k].latitude, located[k].longitude)
        }
        distanceKm = totalKm

        mapStops = clusterStopCentroids(located)

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

    // Drops points far outside the coordinate-wise median of the set (a
    // simple, robust "center" unaffected by one bad value), using a
    // threshold that scales with how spread out the trip already is. A
    // tight single-city trip flags anything past ~20km; a trip that
    // legitimately spans several countries won't flag its own spread.
    function rejectLocationOutliers(pts) {
        if (pts.length < 3) return pts

        var lats = pts.map(function(p) { return p.latitude }).sort(function(a, b) { return a - b })
        var lons = pts.map(function(p) { return p.longitude }).sort(function(a, b) { return a - b })
        var medianLat = lats[Math.floor(lats.length / 2)]
        var medianLon = lons[Math.floor(lons.length / 2)]

        var distances = pts.map(function(p) {
            return GeoUtils.haversineKm(medianLat, medianLon, p.latitude, p.longitude)
        })
        var sortedDistances = distances.slice().sort(function(a, b) { return a - b })
        var medianDistance = sortedDistances[Math.floor(sortedDistances.length / 2)]
        var threshold = Math.max(20, medianDistance * 8)

        var kept = []
        for (var i = 0; i < pts.length; i++) {
            if (distances[i] <= threshold) kept.push(pts[i])
        }
        // Never end up with an unusable map because the filter was too
        // aggressive on a legitimately scattered trip
        return kept.length >= 2 ? kept : pts
    }

    // Sequential nearest-to-last-point clustering (~1.5km), centroid per
    // cluster, for the map's numbered stop markers
    function clusterStopCentroids(locatedPts) {
        var clusterKm = 1.5
        var clusters = []
        for (var i = 0; i < locatedPts.length; i++) {
            var pt = locatedPts[i]
            var cluster = clusters.length > 0 ? clusters[clusters.length - 1] : null
            if (cluster && GeoUtils.haversineKm(cluster.lastLat, cluster.lastLon, pt.latitude, pt.longitude) <= clusterKm) {
                cluster.lastLat = pt.latitude
                cluster.lastLon = pt.longitude
                cluster.sumLat += pt.latitude
                cluster.sumLon += pt.longitude
                cluster.count++
            } else {
                clusters.push({ lastLat: pt.latitude, lastLon: pt.longitude, sumLat: pt.latitude, sumLon: pt.longitude, count: 1 })
            }
        }
        return clusters.map(function(c) {
            return { latitude: c.sumLat / c.count, longitude: c.sumLon / c.count }
        })
    }

    // Greedy single-pass clustering in chronological order: a photo joins
    // the current stop when it's within ~1.5km of the cluster's last point,
    // otherwise a new stop starts. No reverse geocoding (the app is fully
    // offline), so stops are just numbered in visit order rather than named.
    function clusterLocations(items) {
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
            if (cluster && GeoUtils.haversineKm(cluster.lastLat, cluster.lastLon, it.latitude, it.longitude) <= clusterKm) {
                cluster.photos.push(it)
                cluster.lastLat = it.latitude
                cluster.lastLon = it.longitude
                cluster.sumLat += it.latitude
                cluster.sumLon += it.longitude
            } else {
                clusters.push({
                    photos: [it],
                    lastLat: it.latitude, lastLon: it.longitude,
                    sumLat: it.latitude, sumLon: it.longitude
                })
            }
        }

        return { clusters: clusters, noLocation: noLocation }
    }

    function groupByLocation(items) {
        var clustered = clusterLocations(items)
        var result = []
        for (var c = 0; c < clustered.clusters.length; c++) {
            var count = clustered.clusters[c].photos.length
            result.push({
                title: qsTr("Stop %1").arg(c + 1) + " · " + (count === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(count)),
                photos: clustered.clusters[c].photos
            })
        }
        if (clustered.noLocation.length > 0) {
            result.push({ title: qsTr("No location data"), photos: clustered.noLocation })
        }
        return result
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
            MenuItem {
                text: qsTr("Merge into another trip…")
                enabled: faceManager.getTrips().length > 1
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectTripDialog.qml"), {
                        trips: faceManager.getTrips(),
                        excludeTripId: tripId
                    })
                    dialog.accepted.connect(function() {
                        faceManager.mergeTrips(tripId, dialog.selectedTripId)
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
                title: tripName
                description: totalPhotoCount + " " + (totalPhotoCount === 1 ? qsTr("photo") : qsTr("photos"))
            }

            TripRouteMap {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                points: routePoints
                stops: mapStops
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("~%1 km traveled").arg(Math.round(distanceKm))
                visible: routePoints.length >= 2
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
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

                            delegate: ListItem {
                                id: photoItem
                                width: photoGrid.width / 3
                                height: width
                                contentHeight: width

                                // Wrap content in Item to fix ContextMenu positioning
                                contentItem.children: [
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

                                        // Marks the photo currently used as the trip's cover
                                        Rectangle {
                                            visible: modelData.file_path === coverPath
                                            anchors {
                                                top: parent.top
                                                right: parent.right
                                                margins: Theme.paddingSmall
                                            }
                                            width: Theme.iconSizeSmall
                                            height: width
                                            radius: width / 2
                                            color: Theme.rgba("#FFC107", 0.95)
                                            border.color: "white"
                                            border.width: 2
                                            z: 100

                                            Label {
                                                anchors.centerIn: parent
                                                text: "★"
                                                font.pixelSize: Theme.fontSizeExtraSmall
                                                color: "white"
                                            }
                                        }
                                    }
                                ]

                                onClicked: {
                                    pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                        photoPath: modelData.file_path
                                    })
                                }

                                menu: ContextMenu {
                                    MenuItem {
                                        text: qsTr("Set as trip cover")
                                        onClicked: {
                                            faceManager.setEventCover("trip:" + tripId, modelData.file_path)
                                            coverPath = modelData.file_path
                                        }
                                    }
                                    MenuItem {
                                        text: qsTr("View full photo")
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
