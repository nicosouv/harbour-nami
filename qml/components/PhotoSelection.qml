import QtQuick 2.6

/*
 * Selection state for a photo grid.
 *
 * Sharing a whole event is impractical once it holds a few hundred photos,
 * so every photo page can switch into a selection mode and share only what
 * the user picked. Kept in one place so all of them behave the same.
 *
 * Paths are held in a plain array, reassigned on every change: mutating it
 * in place would not re-evaluate the bindings that read count/isSelected.
 */
QtObject {
    id: root

    property bool active: false
    property var paths: []

    readonly property int count: paths.length

    // What makes a share fail is the payload size, not the number of files:
    // 200 thumbnails go through where 12 raw camera shots do not. Kept as a
    // running total, updated per tap, rather than restatting every file on
    // each change.
    property real totalBytes: 0

    // Roughly where e-mail attachment limits sit, and past which Bluetooth
    // becomes a long silent wait. The share sheet gives no feedback when a
    // transfer is too big, so the warning has to come from here.
    readonly property real maxShareBytes: 20 * 1024 * 1024
    readonly property bool tooLarge: totalBytes > maxShareBytes

    function sizeOf(path) {
        if (!path || !facePipeline || !facePipeline.initialized) return 0
        return facePipeline.fileSize(path)
    }

    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return ""
        if (bytes < 1024) return qsTr("%1 B").arg(bytes)
        if (bytes < 1024 * 1024) return qsTr("%1 kB").arg((bytes / 1024).toFixed(0))
        return qsTr("%1 MB").arg((bytes / (1024 * 1024)).toFixed(1))
    }

    function isSelected(path) {
        return paths.indexOf(path) >= 0
    }

    function toggle(path) {
        if (!path) return
        var next = paths.slice()
        var at = next.indexOf(path)
        if (at >= 0) {
            next.splice(at, 1)
            totalBytes = Math.max(0, totalBytes - sizeOf(path))
        } else {
            next.push(path)
            totalBytes += sizeOf(path)
        }
        paths = next
    }

    function selectAll(allPaths) {
        var next = allPaths ? allPaths.slice() : []
        var total = 0
        for (var i = 0; i < next.length; i++) {
            total += sizeOf(next[i])
        }
        paths = next
        totalBytes = total
    }

    function begin(path) {
        paths = path ? [path] : []
        totalBytes = path ? sizeOf(path) : 0
        active = true
    }

    function end() {
        active = false
        paths = []
        totalBytes = 0
    }
}
