import QtQuick 2.6
import Sailfish.Silica 1.0
import "../js/geoutils.js" as GeoUtils
import "../js/worldcoastlines.js" as WorldCoastlines

// A schematic, offline "route map": no tiles, no network, no API key, just
// a sketch of the trip's shape against a simplified world coastline (bundled
// from Natural Earth 1:110m, public domain) so the app stays fully offline.
Item {
    id: root

    // Array of {latitude, longitude} in chronological order, for the route
    property var points: []
    // Array of {latitude, longitude} in chronological visit order, one per
    // numbered marker (matches the "Stop N" grouping); optional
    property var stops: []

    property real revealProgress: 0

    height: visible ? Theme.itemSizeExtraLarge * 1.8 : 0
    visible: points.length >= 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.paddingMedium
        color: "transparent"
        border.color: Theme.rgba(Theme.highlightColor, 0.25)
        border.width: 1
        z: 10
    }

    // Bottom layer: paper background, graticule and coastline. Repainted
    // only when the data or size changes, not on every reveal animation
    // frame (those are comparatively expensive: up to ~130 world polylines).
    Canvas {
        id: backdropCanvas
        anchors.fill: parent
        anchors.margins: 1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.points.length < 2 || width <= 0 || height <= 0) return

            var viewport = root.computeViewport()

            var grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, "#faf5e8")
            grad.addColorStop(1, "#f1e8d2")
            ctx.fillStyle = grad
            ctx.fillRect(0, 0, width, height)

            // Decorative graticule (not real degree lines, just a map "feel")
            ctx.strokeStyle = "rgba(110,90,60,0.12)"
            ctx.lineWidth = 1
            var divisions = 4
            for (var g = 1; g < divisions; g++) {
                var gx = width * g / divisions
                var gy = height * g / divisions
                ctx.beginPath(); ctx.moveTo(gx, 0); ctx.lineTo(gx, height); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
            }

            // World coastline, clipped to the viewport (cheap bbox reject
            // per polyline keeps this fast even though the dataset covers
            // the whole planet)
            ctx.strokeStyle = "rgba(140,115,85,0.6)"
            ctx.lineWidth = 1.1
            var lines = WorldCoastlines.COASTLINES
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
                for (var q = 0; q < line.length; q += 2) {
                    var xy = root.toXY(line[q], line[q + 1], viewport, width, height)
                    if (q === 0) ctx.moveTo(xy[0], xy[1])
                    else ctx.lineTo(xy[0], xy[1])
                }
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
            if (root.points.length < 2 || width <= 0 || height <= 0) return

            var viewport = root.computeViewport()

            // Route line: dashed, gently curved through the points (a
            // quadratic Bezier per interior point, using the midpoint to
            // the next point as the curve's anchor keeps it close to the
            // real path instead of a wide swing), revealed progressively
            var pix = []
            for (var i = 0; i < root.points.length; i++) {
                pix.push(root.toXY(root.points[i].longitude, root.points[i].latitude, viewport, width, height))
            }

            ctx.lineWidth = 2.5
            ctx.strokeStyle = "rgba(51,51,51,0.85)"
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.setLineDash([7, 5])
            ctx.beginPath()
            ctx.moveTo(pix[0][0], pix[0][1])

            var revealFraction = Math.max(0, Math.min(1, root.revealProgress))
            if (pix.length === 2) {
                ctx.lineTo(pix[0][0] + (pix[1][0] - pix[0][0]) * revealFraction,
                           pix[0][1] + (pix[1][1] - pix[0][1]) * revealFraction)
            } else {
                var mids = []
                for (var m = 0; m < pix.length - 1; m++) {
                    mids.push([(pix[m][0] + pix[m + 1][0]) / 2, (pix[m][1] + pix[m + 1][1]) / 2])
                }

                // Units: straight to mid[0], one quadratic curve per interior
                // point ending at its midpoint, then a final straight to the
                // last point - "pix.length" units total, revealed by count
                var totalUnits = pix.length
                var revealUnits = Math.ceil(totalUnits * revealFraction)
                var drawn = 0

                if (revealUnits > drawn) {
                    ctx.lineTo(mids[0][0], mids[0][1])
                    drawn++
                }
                for (var u = 1; u <= pix.length - 2 && drawn < revealUnits; u++) {
                    ctx.quadraticCurveTo(pix[u][0], pix[u][1], mids[u][0], mids[u][1])
                    drawn++
                }
                if (drawn < revealUnits) {
                    ctx.lineTo(pix[pix.length - 1][0], pix[pix.length - 1][1])
                    drawn++
                }
            }
            ctx.stroke()
            ctx.setLineDash([])

            // Numbered stop markers when available, else plain start/end dots
            if (root.stops.length > 0) {
                ctx.font = "bold " + Math.round(Theme.fontSizeExtraSmall) + "px sans-serif"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"
                for (var s = 0; s < root.stops.length; s++) {
                    var sp = root.toXY(root.stops[s].longitude, root.stops[s].latitude, viewport, width, height)
                    ctx.beginPath()
                    ctx.arc(sp[0], sp[1], 9, 0, 2 * Math.PI)
                    ctx.fillStyle = Theme.highlightColor
                    ctx.fill()
                    ctx.fillStyle = "white"
                    ctx.fillText(String(s + 1), sp[0], sp[1] + 1)
                }
            } else {
                for (var k = 0; k < root.points.length; k += root.points.length - 1) {
                    var pt = root.toXY(root.points[k].longitude, root.points[k].latitude, viewport, width, height)
                    ctx.beginPath()
                    ctx.arc(pt[0], pt[1], 6, 0, 2 * Math.PI)
                    ctx.fillStyle = k === 0 ? "#4CAF50" : "#F44336"
                    ctx.fill()
                }
            }

            // Scale bar: km per pixel measured along the horizontal axis at
            // the viewport's vertical center (the projection isn't a true
            // equirectangular one, so this is an approximation, not a ruler)
            var centerLat = (viewport.minLat + viewport.maxLat) / 2
            var kmPerDegLon = GeoUtils.haversineKm(centerLat, viewport.minLon, centerLat, viewport.minLon + 1)
            var kmPerPixel = (viewport.lonSpan * kmPerDegLon) / width
            if (kmPerPixel > 0) {
                var niceSteps = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
                var targetKm = width * 0.26 * kmPerPixel
                var barKm = niceSteps[0]
                for (var ns = 0; ns < niceSteps.length; ns++) {
                    if (niceSteps[ns] <= targetKm) barKm = niceSteps[ns]
                }
                var barPixels = barKm / kmPerPixel
                var barX = 10
                var barY = height - 10

                ctx.strokeStyle = "rgba(40,40,40,0.85)"
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(barX, barY)
                ctx.lineTo(barX + barPixels, barY)
                ctx.moveTo(barX, barY - 4)
                ctx.lineTo(barX, barY + 4)
                ctx.moveTo(barX + barPixels, barY - 4)
                ctx.lineTo(barX + barPixels, barY + 4)
                ctx.stroke()

                ctx.fillStyle = "rgba(40,40,40,0.9)"
                ctx.font = Math.round(Theme.fontSizeTiny) + "px sans-serif"
                ctx.textAlign = "left"
                ctx.textBaseline = "bottom"
                ctx.fillText(barKm + " km", barX, barY - 6)
            }
        }
    }

    // Shared bounding box (with padding) for both canvases
    function computeViewport() {
        var minLat = points[0].latitude, maxLat = minLat
        var minLon = points[0].longitude, maxLon = minLon
        for (var i = 1; i < points.length; i++) {
            minLat = Math.min(minLat, points[i].latitude)
            maxLat = Math.max(maxLat, points[i].latitude)
            minLon = Math.min(minLon, points[i].longitude)
            maxLon = Math.max(maxLon, points[i].longitude)
        }
        var latSpanRaw = Math.max(maxLat - minLat, 0.0005)
        var lonSpanRaw = Math.max(maxLon - minLon, 0.0005)
        var padLat = latSpanRaw * 0.15
        var padLon = lonSpanRaw * 0.15
        minLat -= padLat; maxLat += padLat
        minLon -= padLon; maxLon += padLon
        return {
            minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon,
            latSpan: maxLat - minLat, lonSpan: maxLon - minLon
        }
    }

    function toXY(lon, lat, viewport, w, h) {
        var x = (lon - viewport.minLon) / viewport.lonSpan * w
        // Screen Y grows downward, latitude grows northward
        var y = h - (lat - viewport.minLat) / viewport.latSpan * h
        return [x, y]
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

    onPointsChanged: {
        backdropCanvas.requestPaint()
        revealProgress = 0
        revealAnimation.restart()
    }
    onStopsChanged: routeCanvas.requestPaint()
    onRevealProgressChanged: routeCanvas.requestPaint()
    onWidthChanged: {
        backdropCanvas.requestPaint()
        routeCanvas.requestPaint()
    }
    onHeightChanged: {
        backdropCanvas.requestPaint()
        routeCanvas.requestPaint()
    }
}
