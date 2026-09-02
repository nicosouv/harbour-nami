.pragma library

// Helpers for the Sailfish share sheet. The QML side lives in
// components/PhotoShareAction.qml - this file only holds the pure functions.
//
// Note: sharing goes through Sailfish.Share (ShareAction), not
// Sailfish.TransferEngine.SharePage. Only the former is on the Harbour
// allowed-APIs list.

// ShareAction takes a single mime type, so a mixed selection falls back to the
// wildcard. Sharing plugins advertise "image/*" capabilities, so this still
// matches; a concrete type is preferred when we can determine one.
function mimeForPath(path) {
    if (!path) {
        return "image/*"
    }
    var dot = path.lastIndexOf(".")
    if (dot < 0) {
        return "image/*"
    }
    switch (path.substring(dot + 1).toLowerCase()) {
    case "jpg":
    case "jpeg":
        return "image/jpeg"
    case "png":
        return "image/png"
    case "gif":
        return "image/gif"
    case "bmp":
        return "image/bmp"
    case "webp":
        return "image/webp"
    case "heic":
    case "heif":
        return "image/heif"
    case "tif":
    case "tiff":
        return "image/tiff"
    // A memory's exported clip. Which container it landed in depends on
    // what the device could encode, so all of them are listed rather than
    // the one a developer's phone happened to pick.
    case "mp4":
    case "m4v":
        return "video/mp4"
    case "webm":
        return "video/webm"
    case "mkv":
        return "video/x-matroska"
    case "ogv":
        return "video/ogg"
    case "avi":
        return "video/x-msvideo"
    default:
        return "image/*"
    }
}

// One concrete mime type when every path agrees, "image/*" otherwise.
function mimeForPaths(paths) {
    if (!paths || paths.length === 0) {
        return "image/*"
    }
    var mime = mimeForPath(paths[0])
    for (var i = 1; i < paths.length; i++) {
        if (mimeForPath(paths[i]) !== mime) {
            return "image/*"
        }
    }
    return mime
}

// Collect file paths out of a ListModel of photo entries. Call this from menu
// handlers only, never from a binding - ListModel.get() in a binding is what
// caused the identify page crash.
function pathsFromModel(model) {
    var paths = []
    for (var i = 0; i < model.count; i++) {
        var entry = model.get(i)
        if (entry && entry.file_path) {
            paths.push(entry.file_path)
        }
    }
    return paths
}

// Same, for the plain JS arrays of {title, photos: [...]} that the trip page
// groups its photos into.
function pathsFromGroups(groups) {
    var paths = []
    for (var g = 0; g < groups.length; g++) {
        var photos = groups[g].photos || []
        for (var i = 0; i < photos.length; i++) {
            if (photos[i] && photos[i].file_path) {
                paths.push(photos[i].file_path)
            }
        }
    }
    return paths
}
