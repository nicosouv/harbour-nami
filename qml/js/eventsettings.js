.pragma library

// Shared setting key for "include photos without an identified person" in
// Events/DayPhotosPage/TripDetailPage, so all three read/write the same
// value consistently.
function includeAllPhotos(faceManager) {
    return faceManager.getSetting("events_include_all_photos", "false") === "true"
}
