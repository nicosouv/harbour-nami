.pragma library

// Justified-rows layout, the one used by contact sheets and photo magazines.
//
// Every row is given the same height and filled with photos at their own
// aspect ratio, then the whole row is scaled so it ends exactly on the right
// margin. Nothing is cropped, so a landscape group shot stays readable
// instead of being squeezed into a square, and the rows come out with a
// natural rhythm rather than a uniform waffle.

// Photo's displayed aspect ratio (width / height), honouring the rotation the
// user applied on top of EXIF. Falls back to square when the dimensions were
// never recorded.
function aspectOf(photo) {
    var w = photo.width || 0
    var h = photo.height || 0
    if (w <= 0 || h <= 0) {
        return 1
    }
    var quarterTurned = (((photo.rotation || 0) % 180) + 180) % 180 !== 0
    return quarterTurned ? h / w : w / h
}

// Lay photos out into rows.
//
//   photos        array of entries carrying width/height/rotation
//   availWidth    width to fill, in pixels
//   targetHeight  height a row aims for before being justified
//   gap           space between two photos
//   maxStretch    how far the final, partly filled row may be enlarged;
//                 without it a row holding one photo would blow up to the
//                 full width of the page
//   squareAll     lay every entry out as a square, whatever its dimensions.
//                 The review mode shows square face crops: giving those the
//                 width of the photo they came from would crop the face
//                 straight back off.
//
// Returns an array of rows; each row is an array of
// { photo, width, height } with widths already summing to availWidth.
function layout(photos, availWidth, targetHeight, gap, maxStretch, squareAll) {
    if (!photos || photos.length === 0 || availWidth <= 0 || targetHeight <= 0) {
        return []
    }
    if (maxStretch === undefined) {
        maxStretch = 1.5
    }

    var rows = []
    var current = []
    var currentWidth = 0

    for (var i = 0; i < photos.length; i++) {
        var aspect = squareAll ? 1 : aspectOf(photos[i])
        current.push({ photo: photos[i], aspect: aspect })
        currentWidth += targetHeight * aspect

        var gaps = (current.length - 1) * gap
        if (currentWidth + gaps >= availWidth) {
            rows.push(justify(current, availWidth, targetHeight, gap, 1))
            current = []
            currentWidth = 0
        }
    }

    if (current.length > 0) {
        rows.push(justify(current, availWidth, targetHeight, gap, maxStretch))
    }
    return rows
}

// Scale one row so its photos plus gaps span exactly availWidth. The last
// photo absorbs the rounding remainder, otherwise a row can end a pixel or
// two short of the margin and the right edge looks ragged.
function justify(entries, availWidth, targetHeight, gap, maxStretch) {
    var gaps = (entries.length - 1) * gap
    var naturalWidth = 0
    for (var i = 0; i < entries.length; i++) {
        naturalWidth += targetHeight * entries[i].aspect
    }

    var scale = naturalWidth > 0 ? (availWidth - gaps) / naturalWidth : 1
    scale = Math.min(scale, maxStretch)

    var height = Math.round(targetHeight * scale)
    var row = []
    var used = 0
    for (var j = 0; j < entries.length; j++) {
        var width
        if (j === entries.length - 1 && scale < maxStretch) {
            width = availWidth - gaps - used
        } else {
            width = Math.round(height * entries[j].aspect)
            used += width
        }
        row.push({ photo: entries[j].photo, width: width, height: height })
    }
    return row
}
