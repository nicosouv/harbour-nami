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

    // Guard against a share so large it will never complete. Bluetooth and
    // e-mail both fall over well before this, and the share sheet gives no
    // feedback when it does.
    readonly property int recommendedMax: 50
    readonly property bool tooMany: count > recommendedMax

    function isSelected(path) {
        return paths.indexOf(path) >= 0
    }

    function toggle(path) {
        if (!path) return
        var next = paths.slice()
        var at = next.indexOf(path)
        if (at >= 0) {
            next.splice(at, 1)
        } else {
            next.push(path)
        }
        paths = next
    }

    function selectAll(allPaths) {
        paths = allPaths ? allPaths.slice() : []
    }

    function begin(path) {
        paths = path ? [path] : []
        active = true
    }

    function end() {
        active = false
        paths = []
    }
}
