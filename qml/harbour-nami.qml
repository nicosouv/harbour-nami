import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"

ApplicationWindow {
    id: root

    initialPage: Component { MainPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // facePipeline is exposed from C++ via QML context
    // It's automatically available as a global property
    Component.onCompleted: {
        if (facePipeline && facePipeline.initialized) {
            console.log("Face pipeline initialized successfully")
        } else {
            console.warn("Face pipeline not initialized")
        }
    }

    Connections {
        target: facePipeline

        onError: {
            console.error("Face pipeline error:", message)
        }

        onScanProgress: {
            console.log("Scan progress:", current, "/", total, "-", currentFile)
        }

        onScanCompleted: {
            console.log("Scan completed:", photosProcessed, "photos,", facesDetected, "faces")
        }
    }
}
