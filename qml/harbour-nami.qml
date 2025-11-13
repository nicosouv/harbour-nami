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

        Component.onCompleted: {
            // Check models first, then initialize
            checkModels(function(result) {
                if (result.success && result.models_ready) {
                    // Models available, initialize
                    initialize()
                } else {
                    // Models missing, show download page
                    console.log("ML models not available")
                    pageStack.replace(Qt.resolvedUrl("pages/ModelDownloadPage.qml"))
                }
            })
        }

        onInitialized: {
            console.log("Face recognition initialized")
            console.log("Statistics:", JSON.stringify(statistics))
        }

        onError: {
            console.error("Face recognition error:", message)

            // Check if error is due to missing models
            if (message.indexOf("models") !== -1 || message.indexOf("Models") !== -1) {
                pageStack.replace(Qt.resolvedUrl("pages/ModelDownloadPage.qml"))
            }
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
