import QtQuick 2.6

// One shot on screen: the photo, cropped to a moving rectangle.
//
// The crop is done by oversizing the image and sliding it behind a clip,
// rather than by scaling the item, because the composer's rectangles are
// normalized coordinates in the source photo and this maps them directly.
// A crop rectangle of half the width means an image drawn at twice the
// viewport width, offset so the right part of it shows.
//
// The composer guarantees each rectangle carries the output aspect, so the
// same scale factor satisfies both axes and the photograph is never
// stretched. That guarantee has a test of its own.
Item {
    id: frame

    // A shot from the edit decision list, or null
    property var shot: null
    // 0 at the start of the shot's camera move, 1 at its end
    property real progress: 0.0
    // How much of the frame a wipe has uncovered, left to right
    property real revealed: 1.0

    clip: true

    function lerp(from, to) {
        return from + (to - from) * progress
    }

    // The tightest the camera gets on this photo, which is what decides how
    // many pixels are worth decoding: a crop rectangle covering 94% of the
    // width is drawn at 1.06 times the viewport, not at 1.67.
    //
    // This used to be a flat 1/0.6, the tightest crop any style asks for,
    // applied to every shot of every style. A sentimental clip, which barely
    // zooms at all, was decoding two and a half times the pixels it draws,
    // and paying for it at every cut.
    readonly property real tightestWidth: {
        if (!shot) return 1.0
        return Math.max(0.05, Math.min(shot.from_w, shot.to_w))
    }

    // Rounded up to a step, so that going from one shot to the next usually
    // does not change it at all. Both `source` and `sourceSize` restart the
    // load on their own, and two of them landing in the same pass would ask
    // the reader thread for the photo twice.
    readonly property int decodeWidth: {
        if (frame.width <= 0) return 0
        var wanted = frame.width / tightestWidth
        return Math.ceil(wanted / 128) * 128
    }

    Item {
        // The reveal is a clip on the frame, not a scale: a wipe uncovers
        // the photograph, it does not squeeze it
        width: frame.width * frame.revealed
        height: frame.height
        clip: true

        Image {
            // Where the moving rectangle is now
            property real rectX: shot ? frame.lerp(shot.from_x, shot.to_x) : 0
            property real rectY: shot ? frame.lerp(shot.from_y, shot.to_y) : 0
            property real rectW: shot ? frame.lerp(shot.from_w, shot.to_w) : 1
            property real rectH: shot ? frame.lerp(shot.from_h, shot.to_h) : 1

            source: shot ? "file://" + shot.file_path : ""
            asynchronous: true
            autoTransform: true
            cache: false

            // Decoded once at the size it will be drawn, rather than at 12
            // megapixels: a shot lasts a second or two and the whole clip
            // would otherwise decode a gigapixel
            sourceSize.width: frame.decodeWidth

            width: rectW > 0 ? frame.width / rectW : frame.width
            height: rectH > 0 ? frame.height / rectH : frame.height
            x: -rectX * width
            y: -rectY * height
        }
    }
}
