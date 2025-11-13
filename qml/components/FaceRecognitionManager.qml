import QtQuick 2.0
import io.thp.pyotherside 1.5

/**
 * Face Recognition Manager
 * QML wrapper for Python backend via PyOtherSide
 */
Item {
    id: manager

    // Signals for UI updates
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

    // Properties
    property bool ready: false
    property bool processing: false
    property var statistics: ({})
    property string pythonVersion: ""

    // Settings
    property real detectorConfidence: 0.6
    property real recognitionThreshold: 0.65

    // Python bridge
    Python {
        id: python

        Component.onCompleted: {
            // Add Python module path
            var pythonPath = Qt.resolvedUrl("../../python").toString()
            pythonPath = pythonPath.replace("file://", "")
            addImportPath(pythonPath)

            // Import bridge module
            importModule('nami_bridge', function() {
                console.log("Python bridge module loaded")
                pythonVersion = "Python bridge ready"

                // Initialize pipeline
                manager.initialize()
            })
        }

        onError: {
            console.error("Python error: " + traceback)
            manager.error(traceback)
        }

        onReceived: {
            console.log("Python signal received: " + data)
        }
    }

    // Check if ML models are available
    function checkModels(callback) {
        if (!python.ready) {
            console.warn("Python not ready yet")
            return
        }

        python.call('nami_bridge.check_models', [], function(result) {
            if (callback) callback(result)
        })
    }

    // Initialize face recognition pipeline
    function initialize(dbPath, detectorConf, recognitionThresh) {
        if (!python.ready) {
            console.warn("Python not ready yet")
            return
        }

        var dbPathStr = dbPath || ""
        var detConf = detectorConf || detectorConfidence
        var recThresh = recognitionThresh || recognitionThreshold

        python.call('nami_bridge.initialize', [dbPathStr, detConf, recThresh], function(result) {
            if (result.success) {
                manager.ready = true
                manager.statistics = result.statistics
                manager.initialized(result.statistics)
                console.log("Pipeline initialized:", JSON.stringify(result.statistics))
            } else {
                if (result.models_missing) {
                    manager.error("ML models not available. Please download them first.")
                    // Show model download page
                    // This will be handled by main app
                } else {
                    manager.error("Initialization failed: " + result.error)
                }
            }
        })
    }

    // Process single photo
    function processPhoto(photoPath, autoRecognize) {
        if (!ready) {
            console.warn("Pipeline not ready")
            return
        }

        var autoRec = (autoRecognize !== undefined) ? autoRecognize : true

        processing = true

        python.call('nami_bridge.process_photo', [photoPath, autoRec], function(result) {
            processing = false

            if (result.error) {
                manager.error("Failed to process photo: " + result.error)
            } else {
                manager.photoProcessed(result)
                console.log("Photo processed:", result.detections, "faces detected")

                // Update statistics
                refreshStatistics()
            }
        })
    }

    // Scan entire gallery
    function scanGallery(galleryPath) {
        if (!ready) {
            console.warn("Pipeline not ready")
            return
        }

        if (processing) {
            console.warn("Already processing")
            return
        }

        processing = true
        manager.scanStarted(galleryPath)

        // Set up signal handlers
        setHandler('scan-progress', function(progress) {
            manager.scanProgress(progress)
        })

        setHandler('scan-completed', function(summary) {
            processing = false
            manager.scanCompleted(summary)
            refreshStatistics()
        })

        python.call('nami_bridge.scan_gallery', [galleryPath], function(result) {
            if (result.error) {
                processing = false
                manager.error("Scan failed: " + result.error)
            }
        })
    }

    // Get all people
    function getAllPeople(callback) {
        if (!ready) return

        python.call('nami_bridge.get_all_people', [], function(result) {
            if (result.error) {
                manager.error("Failed to get people: " + result.error)
            } else {
                if (callback) callback(result)
            }
        })
    }

    // Get photos for person
    function getPersonPhotos(personId, callback) {
        if (!ready) return

        python.call('nami_bridge.get_person_photos', [personId], function(result) {
            if (result.error) {
                manager.error("Failed to get photos: " + result.error)
            } else {
                if (callback) callback(result)
            }
        })
    }

    // Create person from face
    function createPerson(faceId, name, contactId) {
        if (!ready) return

        var contact = contactId || null

        python.call('nami_bridge.create_person', [faceId, name, contact], function(result) {
            if (result.error) {
                manager.error("Failed to create person: " + result.error)
            } else {
                manager.personCreated(result)
                console.log("Person created:", result.name)
                refreshStatistics()
            }
        })
    }

    // Update person
    function updatePerson(personId, name, contactId) {
        if (!ready) return

        var nameArg = name || null
        var contactArg = contactId || null

        python.call('nami_bridge.update_person', [personId, nameArg, contactArg], function(result) {
            if (result.error) {
                manager.error("Failed to update person: " + result.error)
            } else {
                manager.personUpdated(result)
                console.log("Person updated:", result.name)
            }
        })
    }

    // Delete person
    function deletePerson(personId) {
        if (!ready) return

        python.call('nami_bridge.delete_person', [personId], function(result) {
            if (result.error) {
                manager.error("Failed to delete person: " + result.error)
            } else {
                manager.personDeleted(personId)
                console.log("Person deleted:", personId)
                refreshStatistics()
            }
        })
    }

    // Assign face to person
    function assignFaceToPerson(faceId, personId) {
        if (!ready) return

        python.call('nami_bridge.assign_face_to_person', [faceId, personId], function(result) {
            if (result.error) {
                manager.error("Failed to assign face: " + result.error)
            } else {
                manager.faceAssigned(faceId, personId)
                console.log("Face assigned:", faceId, "->", personId)
                refreshStatistics()
            }
        })
    }

    // Get unmapped faces
    function getUnmappedFaces(callback) {
        if (!ready) return

        python.call('nami_bridge.get_unmapped_faces', [], function(result) {
            if (result.error) {
                manager.error("Failed to get unmapped faces: " + result.error)
            } else {
                if (callback) callback(result)
            }
        })
    }

    // Group unknown faces by similarity
    function groupUnknownFaces(similarityThreshold, callback) {
        if (!ready) return

        var threshold = similarityThreshold || 0.7

        python.call('nami_bridge.group_unknown_faces', [threshold], function(result) {
            if (result.error) {
                manager.error("Failed to group faces: " + result.error)
            } else {
                manager.facesGrouped({
                    groups: result.length,
                    totalFaces: result.reduce(function(sum, group) { return sum + group.length }, 0)
                })
                if (callback) callback(result)
            }
        })
    }

    // Export data (GDPR)
    function exportData(exportPath) {
        if (!ready) return

        python.call('nami_bridge.export_data', [exportPath], function(result) {
            if (result.error) {
                manager.error("Failed to export data: " + result.error)
            } else {
                manager.dataExported(result.path)
                console.log("Data exported to:", result.path)
            }
        })
    }

    // Clear all data (GDPR)
    function clearAllData() {
        if (!ready) return

        python.call('nami_bridge.clear_all_data', [], function(result) {
            if (result.error) {
                manager.error("Failed to clear data: " + result.error)
            } else {
                manager.dataCleared()
                console.log("All data cleared")
                refreshStatistics()
            }
        })
    }

    // Get statistics
    function refreshStatistics() {
        if (!ready) return

        python.call('nami_bridge.get_statistics', [], function(result) {
            if (result.error) {
                manager.error("Failed to get statistics: " + result.error)
            } else {
                manager.statistics = result
            }
        })
    }

    // Helper to set PyOtherSide signal handlers
    function setHandler(signal, handler) {
        python.setHandler(signal, handler)
    }
}
