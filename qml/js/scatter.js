// Laying polaroids out as a heap rather than as a grid.
//
// The first version was two fixed columns with a little noise on top, and it
// read as exactly that: a table with the alignment slightly off. A pile does
// not have columns. What it has is layers of different sizes, thrown one on
// the next, overlapping.
//
// So the number across a row varies, two to four, and the size follows from
// it: a row of four is a row of smaller prints, further down the pile. Every
// value comes from the deterministic jitter below rather than from
// Math.random(), because a layout that reshuffles when the phone is rotated
// is not a pile, it is a fidget.
//
// Everything here is in fractions of the table's width, y included, so a
// rotation rescales the same heap instead of building a new one.
.pragma library

// The polaroid proportion: a print is taller than it is wide, and the extra
// is the white margin the caption is written on
var ASPECT = 1.2

// How far a row's prints reach past their share of the width, so neighbours
// overlap instead of sitting side by side. Kept light: at 1.18 a print was
// half buried by its neighbour, and this page exists to show the photos.
var SPREAD = 1.07

// Where the next row starts, as a fraction of this row's height.
//
// Barely biting, because the vertical overlap is the one that costs: the
// white margin along the bottom of a print is what makes it read as a
// polaroid, and it carries the date. What actually carries the heap is the
// rotation and the sizes changing row to row, and neither of those hides
// anything.
var LAYER = 0.93

// Room kept at the left and right edges. Small: a pile that stops politely
// short of the edge looks arranged.
var INSET = 0.03

// Deterministic pseudo-random in [0,1). The same memory must lay out the
// same way every time it is opened.
function jitter(i, salt) {
    var x = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453
    return x - Math.floor(x)
}

// Two, three or four across. Seeded with the count as well as the row, so
// two memories of different lengths do not open on the same arrangement.
function columnsFor(row, count) {
    return 2 + Math.floor(jitter(row * 31 + count, 7) * 3)
}

// { items: [{ x, y, w, h, rotation }], height }, all in fractions of the
// table width. Rotation is in degrees.
function layout(count) {
    var items = []
    if (!(count > 0)) {
        return { items: items, height: 0 }
    }

    var y = 0
    var row = 0
    var i = 0
    var lastHeight = 0

    while (i < count) {
        var cols = columnsFor(row, count)
        // A short last row keeps its row's size rather than stretching to
        // fill the width: a pile does not tidy its final layer
        var placing = Math.min(cols, count - i)

        var w = (1.0 / cols) * SPREAD
        var h = w * ASPECT
        var span = 1.0 - w - 2 * INSET
        var step = cols > 1 ? span / (cols - 1) : 0

        for (var c = 0; c < placing; c++, i++) {
            var jx = jitter(i, 1)
            var jy = jitter(i, 2)
            var jr = jitter(i, 3)

            items.push({
                x: INSET + (cols > 1 ? c * step : span / 2) + (jx - 0.5) * w * 0.12,
                y: y + (jy - 0.5) * h * 0.12,
                w: w,
                h: h,
                rotation: (jr - 0.5) * 20
            })
        }

        lastHeight = h
        y += h * LAYER
        row++
    }

    // The last row still extends below where the next one would have begun
    return { items: items, height: y + lastHeight * (1 - LAYER) + lastHeight * 0.08 }
}
