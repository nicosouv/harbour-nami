import QtQuick 2.6
import Sailfish.Silica 1.0

// Minimal offline sketch of a trip's route: draws the chronological path
// between GPS points on a blank canvas. Deliberately not a real map (no
// tiles, no network, no API key) so the app stays fully offline — just
// enough to see the shape of a multi-day trip at a glance.
Item {
    id: root

    // Array of {latitude, longitude} in chronological order
    property var points: []

    height: visible ? Theme.itemSizeExtraLarge * 1.6 : 0
    visible: points.length >= 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.paddingMedium
        color: Theme.rgba(Theme.highlightBackgroundColor, 0.08)
        border.color: Theme.rgba(Theme.highlightColor, 0.2)
        border.width: 1
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: Theme.paddingLarge * 1.5

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.points.length < 2) return

            var minLat = root.points[0].latitude, maxLat = minLat
            var minLon = root.points[0].longitude, maxLon = minLon
            for (var i = 1; i < root.points.length; i++) {
                minLat = Math.min(minLat, root.points[i].latitude)
                maxLat = Math.max(maxLat, root.points[i].latitude)
                minLon = Math.min(minLon, root.points[i].longitude)
                maxLon = Math.max(maxLon, root.points[i].longitude)
            }
            var latSpan = Math.max(maxLat - minLat, 0.0002)
            var lonSpan = Math.max(maxLon - minLon, 0.0002)

            function toXY(pt) {
                var px = (pt.longitude - minLon) / lonSpan * width
                // Screen Y grows downward, latitude grows northward
                var py = height - (pt.latitude - minLat) / latSpan * height
                return [px, py]
            }

            ctx.lineWidth = 2
            ctx.strokeStyle = Theme.highlightColor
            ctx.beginPath()
            for (var j = 0; j < root.points.length; j++) {
                var xy = toXY(root.points[j])
                if (j === 0) {
                    ctx.moveTo(xy[0], xy[1])
                } else {
                    ctx.lineTo(xy[0], xy[1])
                }
            }
            ctx.stroke()

            for (var k = 0; k < root.points.length; k++) {
                var p = toXY(root.points[k])
                var isStart = k === 0
                var isEnd = k === root.points.length - 1
                ctx.beginPath()
                ctx.arc(p[0], p[1], (isStart || isEnd) ? 6 : 3.5, 0, 2 * Math.PI)
                ctx.fillStyle = isStart ? "#4CAF50" : (isEnd ? "#F44336" : Theme.highlightColor)
                ctx.fill()
            }
        }

        Component.onCompleted: requestPaint()
    }

    // Legend
    Row {
        anchors {
            top: parent.top
            right: parent.right
            margins: Theme.paddingSmall
        }
        spacing: Theme.paddingMedium
        visible: root.points.length >= 2

        Row {
            spacing: Theme.paddingSmall / 2
            Rectangle { width: Theme.paddingSmall; height: width; radius: width / 2; color: "#4CAF50"; anchors.verticalCenter: parent.verticalCenter }
            Label { text: qsTr("Start"); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor }
        }
        Row {
            spacing: Theme.paddingSmall / 2
            Rectangle { width: Theme.paddingSmall; height: width; radius: width / 2; color: "#F44336"; anchors.verticalCenter: parent.verticalCenter }
            Label { text: qsTr("End"); font.pixelSize: Theme.fontSizeExtraSmall; color: Theme.secondaryColor }
        }
    }

    onPointsChanged: canvas.requestPaint()
}
