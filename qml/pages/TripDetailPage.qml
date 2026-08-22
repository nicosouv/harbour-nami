import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/geoutils.js" as GeoUtils
import "../js/eventsettings.js" as EventSettings
import "../js/mosaic.js" as Mosaic

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
    // groups laid out as mosaic rows: [{ title, rows }]
    property var photoGroups: []
    property var routePoints: []
    property var mapStops: []
    property int totalPhotoCount: 0
    property bool hasLocationData: false
    property real distanceKm: 0
    property string coverPath: ""

    PhotoShareAction { id: shareAction }
    PhotoSelection { id: selection }

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
                        width: photo.width,
                        height: photo.height,
                        rotation: photo.rotation,
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
                        width: extraPhoto.width,
                        height: extraPhoto.height,
                        rotation: extraPhoto.rotation,
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
        var unlocated = []
        for (var n = 0; n < items.length; n++) {
            if (items[n].has_location) {
                located.push(items[n])
            } else {
                unlocated.push(items[n])
            }
        }

        // A single photo with a corrupted GPS tag (camera/phone GPS glitches
        // happen) would otherwise blow up the map's viewport and the
        // distance total to cover half a continent. Drop points far outside
        // where the rest of the trip actually is before using them for the
        // map, the route, or the distance - the photo itself still shows up
        // normally in the grid below, it's just not trusted for location.
        var trusted = rejectLocationOutliers(located)
        var isTrusted = {}
        for (var t = 0; t < trusted.length; t++) {
            isTrusted[trusted[t].file_path] = true
        }
        for (var o = 0; o < located.length; o++) {
            if (!isTrusted[located[o].file_path]) {
                unlocated.push(located[o])
            }
        }
        unlocated.sort(function(a, b) { return a.timestamp - b.timestamp })

        routePoints = trusted
        hasLocationData = trusted.length > 0

        var totalKm = 0
        for (var k = 1; k < trusted.length; k++) {
            totalKm += GeoUtils.haversineKm(trusted[k - 1].latitude, trusted[k - 1].longitude,
                                             trusted[k].latitude, trusted[k].longitude)
        }
        distanceKm = totalKm

        // One clustering feeds both the map's numbered markers and the
        // "Stop N" sections below, so the numbers always refer to the same
        // places
        var places = clusterByPlace(trusted)
        mapStops = places.map(function(c, i) {
            return {
                latitude: c.latitude, longitude: c.longitude,
                // The map labels its markers with the list's own numbering,
                // and uses the photo count to decide which ones to show
                label: i + 1, photo_count: c.photos.length
            }
        })

        groups = sortMode === "location" ? groupByLocation(places, unlocated) : groupByDay(items)
        rebuildRows()
    }

    // Built once per opening: the viewer browses the whole list, so the
    // tapped photo is just where it starts.
    function openViewer(path) {
        var paths = browsePaths()
        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
            photoPaths: paths,
            photoIndex: Math.max(0, paths.indexOf(path))
        })
    }

    // Flattened in the order the groups are shown, so swiping follows
    // what the eye just scrolled past
    function browsePaths() {
        var paths = []
        for (var g = 0; g < groups.length; g++) {
            var photos = groups[g].photos || []
            for (var i = 0; i < photos.length; i++) {
                paths.push(photos[i].file_path)
            }
        }
        return paths
    }

    function rebuildRows() {
        var avail = photoArea.width - 2 * Theme.horizontalPageMargin
        if (avail <= 0) {
            photoGroups = []
            return
        }
        var targetHeight = avail / 3
        var out = []
        for (var i = 0; i < groups.length; i++) {
            out.push({
                title: groups[i].title,
                rows: Mosaic.layout(groups[i].photos, avail, targetHeight,
                                    Theme.paddingSmall)
            })
        }
        photoGroups = out
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

    // How far apart two photos can be and still count as the same place.
    // Fixed at 1.5km, a day spent walking around one city split into a
    // dozen "stops" and the map grew a numbered marker every few pixels; on
    // a cross-country road trip the same 1.5km made every fuel stop a stop
    // of its own. So it scales with how far the trip actually reaches,
    // which keeps markers a readable distance apart at any zoom.
    function placeRadiusKm(pts) {
        if (pts.length < 2) {
            return 1.5
        }
        var minLat = pts[0].latitude, maxLat = minLat
        var minLon = pts[0].longitude, maxLon = minLon
        for (var i = 1; i < pts.length; i++) {
            minLat = Math.min(minLat, pts[i].latitude)
            maxLat = Math.max(maxLat, pts[i].latitude)
            minLon = Math.min(minLon, pts[i].longitude)
            maxLon = Math.max(maxLon, pts[i].longitude)
        }
        var extentKm = GeoUtils.haversineKm(minLat, minLon, maxLat, maxLon)
        return Math.max(1.5, Math.min(25, extentKm * 0.03))
    }

    // Greedy single-pass clustering in chronological order: a photo joins
    // the current stop while it stays within the radius above of that
    // stop's centre, otherwise a new stop starts. Comparing against the
    // running centroid rather than the previous photo matters: chaining off
    // the last photo lets a stop drift across a whole city, or shatter into
    // one stop per street corner. No reverse geocoding (the app is fully
    // offline), so stops are numbered in visit order rather than named.
    function clusterByPlace(locatedItems) {
        var radiusKm = placeRadiusKm(locatedItems)
        var clusters = []

        for (var i = 0; i < locatedItems.length; i++) {
            var it = locatedItems[i]
            var cluster = clusters.length > 0 ? clusters[clusters.length - 1] : null
            if (cluster && GeoUtils.haversineKm(cluster.latitude, cluster.longitude,
                                                it.latitude, it.longitude) <= radiusKm) {
                cluster.photos.push(it)
                cluster.sumLat += it.latitude
                cluster.sumLon += it.longitude
                cluster.latitude = cluster.sumLat / cluster.photos.length
                cluster.longitude = cluster.sumLon / cluster.photos.length
            } else {
                clusters.push({
                    photos: [it],
                    sumLat: it.latitude, sumLon: it.longitude,
                    latitude: it.latitude, longitude: it.longitude
                })
            }
        }

        return clusters
    }

    function groupByLocation(places, unlocated) {
        var result = []
        for (var c = 0; c < places.length; c++) {
            var count = places[c].photos.length
            result.push({
                title: qsTr("Stop %1").arg(c + 1) + " · " + (count === 1 ? qsTr("1 photo") : qsTr("%1 photos").arg(count)),
                photos: places[c].photos
            })
        }
        if (unlocated.length > 0) {
            result.push({ title: qsTr("No location data"), photos: unlocated })
        }
        return result
    }

    Component.onCompleted: loadTrip()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("Select photos")
                enabled: totalPhotoCount > 0 && !selection.active
                onClicked: selection.begin("")
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

            // Sorting sits where it acts, between the map it reorders by
            // and the photos it reorders: a pulley menu hid which of the two
            // orders was in force.
            Item {
                width: parent.width
                height: sortRow.height + Theme.paddingMedium
                visible: totalPhotoCount > 0 && !selection.active

                Row {
                    id: sortRow
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    FilterChip {
                        text: qsTr("By day")
                        selected: sortMode === "day"
                        onClicked: {
                            if (sortMode === "day") return
                            sortMode = "day"
                            loadTrip()
                        }
                    }

                    FilterChip {
                        text: qsTr("By location")
                        visible: hasLocationData
                        selected: sortMode === "location"
                        onClicked: {
                            if (sortMode === "location") return
                            sortMode = "location"
                            loadTrip()
                        }
                    }
                }
            }

            // Same mosaic as a person's page: photos keep their own shape
            // rather than being squeezed into squares
            Column {
                id: photoArea
                width: parent.width
                spacing: Theme.paddingMedium

                onWidthChanged: page.rebuildRows()

                Repeater {
                    model: photoGroups

                    delegate: Column {
                        id: photoSection
                        width: photoArea.width
                        spacing: Theme.paddingSmall
                        property var group: modelData

                        // Left-aligned, on the axis the photo rows use.
                        // SectionHeader right-aligns, which clipped long titles.
                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            text: photoSection.group.title
                            visible: photoSection.group.title.length > 0
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                            truncationMode: TruncationMode.Fade
                        }

                        Repeater {
                            model: photoSection.group.rows

                            delegate: Row {
                                id: photoRow
                                x: Theme.horizontalPageMargin
                                spacing: Theme.paddingSmall
                                property var cells: modelData

                                Repeater {
                                    model: photoRow.cells

                                    delegate: ListItem {
                                        id: photoItem

                                        property var photo: modelData.photo

                                        width: modelData.width
                                        // No explicit height: the ListItem
                                        // grows for its context menu, the Row
                                        // grows with it and the Column pushes
                                        // the following rows down
                                        contentHeight: modelData.height

                                        contentItem.children: [
                                            Image {
                                                anchors.fill: parent
                                                source: photoItem.photo.file_path
                                                    ? "file://" + photoItem.photo.file_path : ""
                                                fillMode: Image.PreserveAspectCrop
                                                autoTransform: true
                                                rotation: photoItem.photo.rotation || 0
                                                clip: true
                                                asynchronous: true
                                                sourceSize.width: 500
                                                sourceSize.height: 500

                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: parent.status !== Image.Ready
                                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                                                }

                                                // Selection state
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: selection.active
                                                    color: selection.isSelected(photoItem.photo.file_path)
                                                           ? Theme.rgba(Theme.highlightBackgroundColor, 0.45)
                                                           : Theme.rgba("black", 0.35)
                                                    z: 90

                                                    Icon {
                                                        anchors.centerIn: parent
                                                        source: "image://theme/icon-m-acknowledge"
                                                        opacity: selection.isSelected(photoItem.photo.file_path)
                                                                 ? 1 : 0.25
                                                    }
                                                }

                                                // Marks the trip's cover photo
                                                Rectangle {
                                                    visible: photoItem.photo.file_path === coverPath
                                                    anchors {
                                                        top: parent.top
                                                        right: parent.right
                                                        margins: Theme.paddingSmall
                                                    }
                                                    width: Theme.iconSizeSmall
                                                    height: width
                                                    radius: width / 2
                                                    color: Theme.rgba("#FFC107", 0.95)
                                                    z: 100

                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "\u2605"
                                                        font.pixelSize: Theme.fontSizeExtraSmall
                                                        color: "white"
                                                    }
                                                }
                                            }
                                        ]

                                        onClicked: {
                                            if (selection.active) {
                                                selection.toggle(photoItem.photo.file_path)
                                                return
                                            }
                                            page.openViewer(photoItem.photo.file_path)
                                        }

                                        onPressAndHold: {
                                            if (selection.active) {
                                                selection.toggle(photoItem.photo.file_path)
                                            }
                                        }

                                        menu: selection.active ? null : tripPhotoMenu

                                        Component {
                                            id: tripPhotoMenu

                                            ContextMenu {
                                                MenuItem {
                                                    text: qsTr("Set as trip cover")
                                                    onClicked: {
                                                        faceManager.setEventCover(
                                                            "trip:" + tripId,
                                                            photoItem.photo.file_path)
                                                        coverPath = photoItem.photo.file_path
                                                    }
                                                }
                                                MenuItem {
                                                    text: qsTr("View full photo")
                                                    onClicked: {
                                                        page.openViewer(photoItem.photo.file_path)
                                                    }
                                                }
                                                MenuItem {
                                                    text: qsTr("Share")
                                                    onClicked: shareAction.sharePhoto(
                                                        photoItem.photo.file_path)
                                                }
                                            }
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

    PhotoSelectionBar {
        id: selectionBar
        photoSelection: selection
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        z: 200
        onShareRequested: {
            if (shareAction.sharePhotos(selection.paths)) selection.end()
        }
        extraActionIcon: "image://theme/icon-m-favorite"
        extraActionEnabled: selection.count === 1
        onExtraActionTriggered: {
            faceManager.setEventCover("trip:" + tripId, selection.paths[0])
            coverPath = selection.paths[0]
            selection.end()
        }
    }
}
