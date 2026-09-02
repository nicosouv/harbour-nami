import QtQuick 2.6
import Sailfish.Share 1.0
import "../js/share.js" as Share

/*
 * Wraps Sailfish.Share's ShareAction for photo files, so every page shares the
 * same way and picks a sensible mime type.
 *
 * Usage:
 *     PhotoShareAction { id: shareAction }
 *     ...
 *     MenuItem {
 *         text: "Share"
 *         onClicked: shareAction.sharePhoto(model.file_path)
 *     }
 */
ShareAction {
    id: root

    // Jolla's own apps hand ShareAction plain absolute paths (no file://
    // prefix), so keep that convention.
    // A memory's exported clip goes out the same way a photo does: one
    // absolute path, and the mime type its extension implies
    function shareFile(path) {
        return sharePhoto(path)
    }

    function sharePhoto(path) {
        if (!path) {
            return false
        }
        return sharePhotos([path])
    }

    function sharePhotos(paths) {
        if (!paths || paths.length === 0) {
            return false
        }

        var clean = []
        for (var i = 0; i < paths.length; i++) {
            if (paths[i]) {
                clean.push(paths[i])
            }
        }
        if (clean.length === 0) {
            return false
        }

        root.mimeType = Share.mimeForPaths(clean)
        root.resources = clean
        root.trigger()
        return true
    }
}
