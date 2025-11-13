import QtQuick 2.0

/**
 * Face Recognition Manager
 * QML wrapper for C++ FacePipeline backend
 */
QtObject {
    id: manager

    // === Signals ===
    signal initialized(var statistics)
    signal photoProcessed(var result)
    signal scanStarted(string path)
    signal scanProgress(var progress)
    signal scanCompleted(var summary)
    signal personCreated(var person)
    signal personUpdated(var person)
    signal personDeleted(int personId)
    signal faceAssigned(int faceId, int personId)
    signal facesGrouped(var info)
    signal dataExported(string path)
    signal dataCleared()
    signal error(string message)

    // === Properties ===
    property bool ready: facePipeline && facePipeline.initialized
    property bool processing: facePipeline ? facePipeline.processing : false
    property var statistics: ({})

    // Settings
    property real detectorConfidence: 0.6
    property real recognitionThreshold: 0.65

    // === Connections to C++ FacePipeline ===
    Connections {
        target: facePipeline

        onError: {
            manager.error(message)
        }
    }

    // === Public Methods ===

    function checkModels(callback) {
        // In C++ version, models are checked during initialization
        var result = {
            success: true,
            models_ready: ready
        }
        if (callback) {
            callback(result)
        }
    }

    function initialize() {
        if (ready) {
            console.log("Face pipeline already initialized")
            manager.initialized(statistics)
        } else {
            error("Failed to initialize face pipeline - check ML models")
        }
    }

    function processPhoto(photoPath, autoRecognize, callback) {
        if (!ready) {
            console.warn("Pipeline not ready")
            if (callback) callback({ success: false, error: "Not initialized" })
            return
        }

        var result = facePipeline.processPhoto(photoPath)

        var processResult = {
            success: result.success,
            detections: result.facesDetected,
            faces_matched: result.facesMatched,
            error: result.errorMessage
        }

        manager.photoProcessed(processResult)

        if (callback) {
            callback(processResult)
        }
    }

    function scanGallery(galleryPath, callback) {
        if (!ready) {
            console.warn("Pipeline not ready")
            if (callback) callback({ success: false, error: "Not initialized" })
            return
        }

        console.log("Starting gallery scan:", galleryPath)
        manager.scanStarted(galleryPath)

        // Connect to C++ signals
        var progressConn = facePipeline.scanProgress.connect(function(current, total, currentFile) {
            var progressData = {
                current: current,
                total: total,
                percentage: Math.round((current / total) * 100),
                current_file: currentFile
            }
            manager.scanProgress(progressData)
        })

        var completedConn = facePipeline.scanCompleted.connect(function(photosProcessed, facesDetected) {
            // Disconnect signals
            facePipeline.scanProgress.disconnect(progressConn)
            facePipeline.scanCompleted.disconnect(completedConn)

            var summary = {
                total_photos: photosProcessed,
                total_faces: facesDetected
            }

            manager.scanCompleted(summary)

            if (callback) {
                callback({ success: true, summary: summary })
            }
        })

        var failedConn = facePipeline.scanFailed.connect(function(errorMsg) {
            // Disconnect signals
            facePipeline.scanProgress.disconnect(progressConn)
            facePipeline.scanCompleted.disconnect(completedConn)
            facePipeline.scanFailed.disconnect(failedConn)

            manager.error(errorMsg)

            if (callback) {
                callback({ success: false, error: errorMsg })
            }
        })

        // Start scan
        facePipeline.scanGallery(galleryPath, true)
    }

    function getAllPeople(callback) {
        if (!ready) {
            if (callback) callback({ error: "Not initialized" })
            return
        }

        // TODO: Implement in C++ - would need PeopleModel
        console.warn("getAllPeople not yet implemented in C++ backend")
        if (callback) callback({ people: [] })
    }

    function getPersonPhotos(personId, callback) {
        if (!ready) {
            if (callback) callback({ error: "Not initialized" })
            return
        }

        // TODO: Implement in C++ - would need PhotoModel
        console.warn("getPersonPhotos not yet implemented in C++ backend")
        if (callback) callback({ photos: [] })
    }

    function createPerson(faceId, name, contactId, callback) {
        if (!ready) {
            if (callback) callback({ error: "Not initialized" })
            return
        }

        var success = facePipeline.identifyFace(faceId, -1, name)

        if (success) {
            var person = {
                id: -1,  // Would need to query database for actual ID
                name: name
            }
            manager.personCreated(person)
            console.log("Person created:", name)

            if (callback) callback(person)
        } else {
            manager.error("Failed to create person")
            if (callback) callback({ error: "Failed to create person" })
        }
    }

    function updatePerson(personId, name, contactId, callback) {
        // TODO: Implement updatePersonName in C++ FaceDatabase
        console.warn("updatePerson not yet implemented in C++ backend")
        if (callback) callback({ error: "Not implemented" })
    }

    function deletePerson(personId, callback) {
        // TODO: Implement in C++ FaceDatabase
        console.warn("deletePerson not yet implemented in C++ backend")
        if (callback) callback({ error: "Not implemented" })
    }

    function assignFaceToPerson(faceId, personId, callback) {
        if (!ready) {
            if (callback) callback({ error: "Not initialized" })
            return
        }

        var success = facePipeline.identifyFace(faceId, personId, "")

        if (success) {
            manager.faceAssigned(faceId, personId)
            console.log("Face assigned:", faceId, "->", personId)

            if (callback) callback({ success: true })
        } else {
            manager.error("Failed to assign face")
            if (callback) callback({ error: "Failed to assign face" })
        }
    }

    function getUnmappedFaces(callback) {
        // TODO: Implement in C++ - would need FaceModel
        console.warn("getUnmappedFaces not yet implemented in C++ backend")
        if (callback) callback({ faces: [] })
    }

    function groupUnknownFaces(similarityThreshold, callback) {
        if (!ready) {
            if (callback) callback({ error: "Not initialized" })
            return
        }

        var threshold = similarityThreshold || 0.7
        var groupsCreated = facePipeline.groupUnknownFaces(threshold)

        var info = {
            groups: groupsCreated,
            threshold: threshold
        }

        manager.facesGrouped(info)

        if (callback) {
            callback({ success: true, groups: groupsCreated })
        }
    }

    function exportData(exportPath, callback) {
        // TODO: Implement GDPR export in C++ FaceDatabase
        console.warn("exportData not yet implemented in C++ backend")
        if (callback) callback({ error: "Not implemented" })
    }

    function clearAllData(callback) {
        // TODO: Implement GDPR deletion in C++ FaceDatabase
        console.warn("clearAllData not yet implemented in C++ backend")
        if (callback) callback({ error: "Not implemented" })
    }

    function refreshStatistics() {
        // TODO: Implement getStatistics in C++ FaceDatabase
        console.warn("refreshStatistics not yet implemented in C++ backend")
    }

    function cancel() {
        if (facePipeline) {
            facePipeline.cancel()
        }
    }
}
