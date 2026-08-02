.pragma library

// Shared by EventsPage, YearsPage and YearDetailPage: photos grouped by
// calendar date, keyed "yyyy-MM-dd". Each entry is
// { date: Date, people: {personId: name}, photos: [...] }
//
// faceManager.getPersonPhotos() is the base source (only photos with an
// identified person); when includeAllPhotos is true, every scanned photo
// is folded in too, deduplicated by file path.
function computeDateMap(faceManager, includeAllPhotos) {
    var dateMap = {}

    function addPhoto(photo, personId, personName) {
        if (!photo.timestamp) return
        var date = new Date(photo.timestamp * 1000)
        var dateKey = Qt.formatDate(date, "yyyy-MM-dd")

        if (!dateMap[dateKey]) {
            dateMap[dateKey] = { date: date, people: {}, photos: [] }
        }
        if (personId !== undefined) {
            dateMap[dateKey].people[personId] = personName
        }

        var exists = false
        for (var k = 0; k < dateMap[dateKey].photos.length; k++) {
            if (dateMap[dateKey].photos[k].file_path === photo.file_path) {
                exists = true
                break
            }
        }
        if (!exists) {
            dateMap[dateKey].photos.push(photo)
        }
    }

    var people = faceManager.getAllPeople()
    for (var i = 0; i < people.length; i++) {
        var person = people[i]
        var photos = faceManager.getPersonPhotos(person.person_id)
        for (var j = 0; j < photos.length; j++) {
            addPhoto(photos[j], person.person_id, person.name)
        }
    }

    if (includeAllPhotos) {
        var allPhotos = faceManager.getAllPhotos()
        for (var ap = 0; ap < allPhotos.length; ap++) {
            addPhoto(allPhotos[ap])
        }
    }

    return dateMap
}

// event_key -> true, from faceManager.getHiddenEvents()
function computeHiddenSet(faceManager) {
    var hiddenSet = {}
    var hiddenList = faceManager.getHiddenEvents()
    for (var h = 0; h < hiddenList.length; h++) {
        hiddenSet[hiddenList[h]] = true
    }
    return hiddenSet
}

// dateKey -> trip_id, from faceManager.getTrips()
function computeDateToTrip(trips) {
    var dateToTrip = {}
    for (var t = 0; t < trips.length; t++) {
        for (var td = 0; td < trips[t].date_keys.length; td++) {
            dateToTrip[trips[t].date_keys[td]] = trips[t].trip_id
        }
    }
    return dateToTrip
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
