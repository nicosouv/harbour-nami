import QtQuick 2.0
import Sailfish.Silica 1.0
import "pages"
import "components"

ApplicationWindow {
    id: root

    initialPage: Component { MainPage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Global Face Recognition Manager
    FaceRecognitionManager {
        id: faceManager

        onInitialized: {
            console.log("Face recognition initialized")
            console.log("Statistics:", JSON.stringify(statistics))
        }

        onError: {
            console.error("Face recognition error:", message)
        }

        onScanProgress: {
            console.log("Scan progress:", progress.percentage + "%",
                       "(" + progress.current + "/" + progress.total + ")")
        }

        onScanCompleted: {
            console.log("Scan completed:", summary.total_photos, "photos,",
                       summary.total_faces, "faces detected")
        }
    }

    // Make face manager accessible globally
    property alias faceRecognition: faceManager
}
