import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/geoutils.js" as GeoUtils
import "../js/worldcoastlines.js" as WorldCoastlines

// A schematic, offline "route map": no tiles, no network, no API key, just
// a sketch of the trip's shape against a simplified world coastline (bundled
// from Natural Earth 1:110m, public domain) so the app stays fully offline.
Item {
    id: root

    // Array of {latitude, longitude} in chronological order: every geotagged
    // photo of the trip. Used for the viewport, not for the drawn line.
    property var points: []
    // Array of {latitude, longitude} in chronological visit order, one per
    // numbered marker (matches the "Stop N" grouping); optional
    property var stops: []

    property real revealProgress: 0

    // The line follows the stops when there are any: a line through every
    // geotagged photo turns a day spent in one city into an unreadable
    // scribble, since hundreds of photos land within a few pixels
    readonly property var routeLine: stops.length > 0 ? stops : points

    // Hairlines, dots and dashes are the only sizes here not coming from
    // Theme, so they need the device scaling factor applied by hand. The
    // fallback keeps the map drawn rather than blank should Theme not
    // expose pixelRatio.
    readonly property real uiScale: Theme.pixelRatio > 0 ? Theme.pixelRatio : 1

    // Markers only for the places that carry the trip. A photo taken from
    // the car is a legitimate stop in the list below, but a numbered dot for
    // every one of them buries the places you actually spent time in. The
    // line still passes through every stop, and a marker keeps the number it
    // has in the list, so "Stop 7" is the same thing in both.
    readonly property int maxMarkers: 8
    readonly property var markerStops: {
        if (stops.length <= maxMarkers) {
            return stops
        }
        var order = []
        for (var i = 0; i < stops.length; i++) {
            order.push(i)
        }
        order.sort(function(a, b) {
            return (stops[b].photo_count || 0) - (stops[a].photo_count || 0)
        })

        var keep = []
        for (var k = 0; k < stops.length; k++) {
            keep.push(false)
        }
        // Where the trip started and ended always earn their marker
        keep[0] = true
        keep[stops.length - 1] = true
        var kept = 2
        for (var o = 0; o < order.length && kept < maxMarkers; o++) {
            if (!keep[order[o]]) {
                keep[order[o]] = true
                kept++
            }
        }

        var result = []
        for (var s = 0; s < stops.length; s++) {
            if (keep[s]) {
                result.push(stops[s])
            }
        }
        return result
    }

    // Never zoom in tighter than this. A trip spent inside one town would
    // otherwise fill the map with a few hundred metres of empty paper, with
    // no coastline in sight and nothing to tell you where you are.
    // Settable: a single photo's location is shown much further out, so the
    // coastline actually says which country you are looking at.
    property real minSpanKm: 5

    // A route needs two points to be a route; a single-location map (one
    // geotagged photo) sets this to 1.
    property int minPoints: 2

    height: visible ? Theme.itemSizeExtraLarge * 1.8 : 0
    visible: points.length >= minPoints

    Rectangle {
        anchors.fill: parent
        radius: Theme.paddingMedium
        color: "transparent"
        border.color: Theme.rgba(Theme.highlightColor, 0.25)
        border.width: 1
        z: 10
    }

    // Bottom layer: paper background, coastline. Repainted only when the
    // data or size changes, not on every reveal animation frame (those are
    // comparatively expensive: up to ~130 world polylines).
    Canvas {
        id: backdropCanvas
        anchors.fill: parent
        anchors.margins: 1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.routeLine.length < 1 || width <= 0 || height <= 0) return

            var viewport = root.computeViewport(width, height)

            // Sea first, land painted over it: the coastline data is a set
            // of closed rings ordered from largest to smallest, so a small
            // island drawn after its continent stays visible
            var sea = ctx.createLinearGradient(0, 0, 0, height)
            sea.addColorStop(0, "#dde9f0")
            sea.addColorStop(1, "#cadbe6")
            ctx.fillStyle = sea
            ctx.fillRect(0, 0, width, height)

            // Land rings, clipped to the viewport (cheap bbox reject per
            // ring keeps this fast even though the dataset covers the whole
            // planet). Decimated in pixel space (skip points under ~2.5px
            // from the last kept one) so a dense/jagged coastline doesn't
            // turn into visual noise in a small map - real coastlines are
            // highly detailed at any zoom level, so without this the mini
            // map reads as "the whole world crammed in" even when correctly
            // cropped.
            ctx.fillStyle = "#f7f0dc"
            ctx.strokeStyle = "rgba(120,105,80,0.55)"
            ctx.lineWidth = 0.9 * root.uiScale
            var lines = WorldCoastlines.COASTLINES
            var minPixelStep = Math.pow(2.5 * root.uiScale, 2)
            for (var c = 0; c < lines.length; c++) {
                var line = lines[c]
                var lMinLon = line[0], lMaxLon = line[0], lMinLat = line[1], lMaxLat = line[1]
                for (var p = 0; p < line.length; p += 2) {
                    if (line[p] < lMinLon) lMinLon = line[p]
                    if (line[p] > lMaxLon) lMaxLon = line[p]
                    if (line[p + 1] < lMinLat) lMinLat = line[p + 1]
                    if (line[p + 1] > lMaxLat) lMaxLat = line[p + 1]
                }
                if (lMaxLon < viewport.minLon || lMinLon > viewport.maxLon
                    || lMaxLat < viewport.minLat || lMinLat > viewport.maxLat) {
                    continue
                }

                ctx.beginPath()
                var lastX = 0, lastY = 0
                var lastIdx = line.length - 2
                for (var q = 0; q < line.length; q += 2) {
                    var xy = root.toXY(line[q], line[q + 1], viewport, width, height)
                    if (q === 0) {
                        ctx.moveTo(xy[0], xy[1])
                        lastX = xy[0]; lastY = xy[1]
                        continue
                    }
                    var dx = xy[0] - lastX, dy = xy[1] - lastY
                    if (q === lastIdx || dx * dx + dy * dy >= minPixelStep) {
                        ctx.lineTo(xy[0], xy[1])
                        lastX = xy[0]; lastY = xy[1]
                    }
                }
                ctx.closePath()
                ctx.fill()
                ctx.stroke()
            }
        }
    }

    // Top layer: the route line (animated reveal), numbered stops and the
    // scale bar. Cheap enough to repaint every animation frame.
    Canvas {
        id: routeCanvas
        anchors.fill: parent
        anchors.margins: 1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.routeLine.length < 1 || width <= 0 || height <= 0) return

            var viewport = root.computeViewport(width, height)
            var scale = root.uiScale

            var pix = []
            for (var i = 0; i < root.routeLine.length; i++) {
                pix.push(root.toXY(root.routeLine[i].longitude, root.routeLine[i].latitude,
                                   viewport, width, height))
            }

            // Route line: dashed, gently curved through the stops, revealed
            // progressively. Both the curve and the dashes are walked by
            // hand along a sampled polyline (see routePolyline/strokeDashed)
            if (pix.length >= 2) {
                ctx.lineWidth = 2.5 * scale
                ctx.strokeStyle = "rgba(51,51,51,0.85)"
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                root.strokeDashed(ctx, root.routePolyline(pix), 7 * scale, 5 * scale,
                                  root.revealProgress)
            }

            // Numbered stop markers when available, else plain start/end dots
            if (root.stops.length > 0) {
                ctx.font = "bold " + Math.round(Theme.fontSizeExtraSmall) + "px sans-serif"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (var s = 0; s < root.markerStops.length; s++) {
                    var stop = root.markerStops[s]
                    var at = root.toXY(stop.longitude, stop.latitude, viewport, width, height)
                    var label = String(stop.label !== undefined ? stop.label : s + 1)
                    // Wide enough for the number it holds: two-digit stops
                    // used to spill out of a fixed 9px dot. Measured when
                    // the canvas supports it, estimated otherwise, since a
                    // throwing call here would cost every marker below.
                    var labelWidth = ctx.measureText
                        ? ctx.measureText(label).width
                        : label.length * Theme.fontSizeExtraSmall * 0.6
                    var radius = Math.max(Theme.fontSizeExtraSmall * 0.8,
                                          labelWidth / 2 + 4 * scale)
                    ctx.beginPath()
                    ctx.arc(at[0], at[1], radius, 0, 2 * Math.PI)
                    ctx.fillStyle = Theme.highlightColor
                    ctx.fill()
                    // Light rim so a marker sitting on the route line still
                    // reads as a separate thing, over land or over sea
                    ctx.strokeStyle = "rgba(255,255,255,0.92)"
                    ctx.lineWidth = 1.5 * scale
                    ctx.stroke()
                    ctx.fillStyle = "white"
                    ctx.fillText(label, at[0], at[1] + scale)
                }
            } else if (pix.length === 1) {
                // Single location: there is no route, so the green/red
                // start/end coding would be meaningless. Draw one neutral
                // marker with a rim so it reads over land and over sea.
                ctx.beginPath()
                ctx.arc(pix[0][0], pix[0][1], 7 * scale, 0, 2 * Math.PI)
                ctx.fillStyle = Theme.highlightColor
                ctx.fill()
                ctx.strokeStyle = "rgba(255,255,255,0.92)"
                ctx.lineWidth = 2 * scale
                ctx.stroke()
            } else {
                var ends = [0, pix.length - 1]
                for (var k = 0; k < ends.length; k++) {
                    ctx.beginPath()
                    ctx.arc(pix[ends[k]][0], pix[ends[k]][1], 6 * scale, 0, 2 * Math.PI)
                    ctx.fillStyle = k === 0 ? "#4CAF50" : "#F44336"
                    ctx.fill()
                }
            }

            // Scale bar. Both axes are drawn at the same number of pixels
            // per kilometre (see computeViewport), so this is a real ruler
            // in every direction, not just horizontally.
            var kmPerPixel = viewport.kmPerDegLat / viewport.pxPerDeg
            if (kmPerPixel > 0) {
                var niceSteps = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
                var targetKm = width * 0.26 * kmPerPixel
                var barKm = niceSteps[0]
                for (var ns = 0; ns < niceSteps.length; ns++) {
                    if (niceSteps[ns] <= targetKm) barKm = niceSteps[ns]
                }
                var barPixels = barKm / kmPerPixel
                var barX = Theme.paddingMedium
                var barY = height - Theme.paddingMedium
                var tick = 4 * scale

                ctx.strokeStyle = "rgba(40,40,40,0.85)"
                ctx.lineWidth = 2 * scale
                ctx.beginPath()
                ctx.moveTo(barX, barY)
                ctx.lineTo(barX + barPixels, barY)
                ctx.moveTo(barX, barY - tick)
                ctx.lineTo(barX, barY + tick)
                ctx.moveTo(barX + barPixels, barY - tick)
                ctx.lineTo(barX + barPixels, barY + tick)
                ctx.stroke()

                ctx.fillStyle = "rgba(40,40,40,0.9)"
                ctx.font = Math.round(Theme.fontSizeTiny) + "px sans-serif"
                ctx.textAlign = "left"
                ctx.textBaseline = "bottom"
                ctx.fillText(barKm + " km", barX, barY - tick - 2 * scale)
            }
        }
    }

    // Shared viewport for both canvases.
    //
    // Equirectangular projection centred on the trip, using the trip's own
    // latitude as the standard parallel: a degree of longitude covers
    // cos(latitude) as much ground as a degree of latitude, and ignoring
    // that stretches every shape east-west (by half in northern Europe).
    // Both axes then get the same pixels-per-degree, so the route and the
    // coastline keep their real proportions instead of being squashed to
    // whatever aspect ratio the widget happens to have.
    function computeViewport(w, h) {
        var line = routeLine
        var minLat = line[0].latitude, maxLat = minLat
        var minLon = line[0].longitude, maxLon = minLon
        for (var i = 1; i < line.length; i++) {
            minLat = Math.min(minLat, line[i].latitude)
            maxLat = Math.max(maxLat, line[i].latitude)
            minLon = Math.min(minLon, line[i].longitude)
            maxLon = Math.max(maxLon, line[i].longitude)
        }

        var centerLat = (minLat + maxLat) / 2
        var centerLon = (minLon + maxLon) / 2
        var lonScale = Math.max(0.05, Math.cos(centerLat * Math.PI / 180))

        var kmPerDegLat = GeoUtils.haversineKm(centerLat, centerLon, centerLat + 1, centerLon)
        var minSpanDeg = minSpanKm / kmPerDegLat

        var latSpan = Math.max(maxLat - minLat, minSpanDeg)
        var lonSpan = Math.max((maxLon - minLon) * lonScale, minSpanDeg)

        // The tighter axis sets the scale, with ~20% breathing room so the
        // route never touches the frame
        var pxPerDeg = Math.min(w / (lonSpan * 1.2), h / (latSpan * 1.2))

        return {
            centerLat: centerLat,
            centerLon: centerLon,
            lonScale: lonScale,
            pxPerDeg: pxPerDeg,
            kmPerDegLat: kmPerDegLat,
            // Actually visible bounds, for the coastline's bbox rejection
            minLat: centerLat - (h / 2) / pxPerDeg,
            maxLat: centerLat + (h / 2) / pxPerDeg,
            minLon: centerLon - (w / 2) / pxPerDeg / lonScale,
            maxLon: centerLon + (w / 2) / pxPerDeg / lonScale
        }
    }

    // Sample the gently curved route into a plain polyline: a quadratic
    // Bezier per interior stop, anchored on the midpoints to its neighbours
    // so the curve stays close to the real path instead of swinging wide.
    // Sampling it (rather than using quadraticCurveTo) is what lets the
    // dashes and the reveal below be measured in real path length.
    function routePolyline(pix) {
        if (pix.length < 2) {
            return []
        }
        if (pix.length === 2) {
            return [pix[0], pix[1]]
        }

        var mids = []
        for (var m = 0; m < pix.length - 1; m++) {
            mids.push([(pix[m][0] + pix[m + 1][0]) / 2, (pix[m][1] + pix[m + 1][1]) / 2])
        }

        var path = [pix[0], mids[0]]
        var steps = 12
        for (var u = 1; u <= pix.length - 2; u++) {
            var from = mids[u - 1], ctrl = pix[u], to = mids[u]
            for (var t = 1; t <= steps; t++) {
                var f = t / steps, g = 1 - f
                path.push([g * g * from[0] + 2 * g * f * ctrl[0] + f * f * to[0],
                           g * g * from[1] + 2 * g * f * ctrl[1] + f * f * to[1]])
            }
        }
        path.push(pix[pix.length - 1])
        return path
    }

    // Qt Quick's Canvas context has no setLineDash: calling it throws, and
    // the exception aborts the whole paint handler, which is why the map
    // used to render as an empty sheet of paper. So walk the path and lay
    // the dashes down by hand, stopping at the revealed fraction of the
    // total length (which also makes the reveal continuous instead of
    // jumping from stop to stop).
    function strokeDashed(ctx, path, dashOn, dashOff, fraction) {
        if (path.length < 2 || dashOn <= 0 || dashOff <= 0) {
            return
        }

        var lengths = []
        var total = 0
        for (var i = 1; i < path.length; i++) {
            var dx = path[i][0] - path[i - 1][0]
            var dy = path[i][1] - path[i - 1][1]
            var d = Math.sqrt(dx * dx + dy * dy)
            lengths.push(d)
            total += d
        }

        var limit = total * Math.max(0, Math.min(1, fraction))
        if (limit <= 0) {
            return
        }

        var travelled = 0
        var penDown = true
        var remaining = dashOn

        ctx.beginPath()
        ctx.moveTo(path[0][0], path[0][1])
        for (var s = 0; s < lengths.length; s++) {
            var len = lengths[s]
            if (len <= 0) {
                continue
            }
            var ax = path[s][0], ay = path[s][1]
            var ux = (path[s + 1][0] - ax) / len, uy = (path[s + 1][1] - ay) / len
            var pos = 0
            // Bounded: every iteration consumes at least one of the three
            // budgets, but a stray zero-length step must not hang the UI
            var guard = 0
            while (pos < len && guard++ < 4096) {
                if (travelled >= limit) {
                    ctx.stroke()
                    return
                }
                var step = Math.min(remaining, len - pos, limit - travelled)
                pos += step
                travelled += step
                remaining -= step
                if (penDown) {
                    ctx.lineTo(ax + ux * pos, ay + uy * pos)
                } else {
                    ctx.moveTo(ax + ux * pos, ay + uy * pos)
                }
                if (remaining <= 0.0001) {
                    penDown = !penDown
                    remaining = penDown ? dashOn : dashOff
                }
            }
        }
        ctx.stroke()
    }

    function toXY(lon, lat, viewport, w, h) {
        return [w / 2 + (lon - viewport.centerLon) * viewport.lonScale * viewport.pxPerDeg,
                // Screen Y grows downward, latitude grows northward
                h / 2 - (lat - viewport.centerLat) * viewport.pxPerDeg]
    }

    NumberAnimation {
        id: revealAnimation
        target: root
        property: "revealProgress"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.OutCubic
    }

    function repaintAll() {
        backdropCanvas.requestPaint()
        routeCanvas.requestPaint()
    }

    onPointsChanged: {
        repaintAll()
        revealProgress = 0
        revealAnimation.restart()
    }
    // Stops define the drawn line and therefore the viewport, so the
    // backdrop has to follow them too
    onStopsChanged: repaintAll()
    onRevealProgressChanged: routeCanvas.requestPaint()
    onWidthChanged: repaintAll()
    onHeightChanged: repaintAll()
    // Drives the zoom floor, so both layers have to be redrawn
    onMinSpanKmChanged: repaintAll()
}
