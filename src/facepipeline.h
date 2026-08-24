#ifndef FACEPIPELINE_H
#define FACEPIPELINE_H

#include <QObject>
#include <QString>
#include <QImage>
#include <QVector>
#include <QFuture>
#include <QFutureWatcher>
#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"
#include "memorycomposer.h"

/**
 * @brief Processing result for a single photo
 */
struct PhotoProcessingResult {
    int photoId;
    QString filePath;
    int facesDetected;
    int facesMatched;
    bool success;
    QString errorMessage;
};

/**
 * @brief One face extracted from a photo (detection + embedding, no DB state)
 */
struct ExtractedFace {
    QRectF bbox;
    float confidence;
    FaceEmbedding embedding;
};

/**
 * @brief CPU-heavy part of photo processing, computed on a worker thread.
 *
 * Deliberately contains no database identifiers: QSqlDatabase connections
 * are bound to the thread that created them, so all DB access stays on the
 * main thread while decoding/detection/embedding run in the background.
 */
struct PhotoExtraction {
    QString filePath;
    bool loaded;
    int width;
    int height;
    QDateTime dateTaken;
    bool hasLocation;
    double latitude;
    double longitude;
    QString fileHash;
    QVector<ExtractedFace> faces;
};

/**
 * @brief Main face recognition pipeline
 *
 * Orchestrates the complete face recognition workflow:
 * 1. Gallery scanning
 * 2. Face detection (YuNet)
 * 3. Face recognition (ArcFace)
 * 4. Database storage
 * 5. Automatic face grouping
 */
class FacePipeline : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool initialized READ isInitialized NOTIFY initializedChanged)
    Q_PROPERTY(bool processing READ isProcessing NOTIFY processingChanged)
    Q_PROPERTY(int totalPhotos READ totalPhotos NOTIFY totalPhotosChanged)
    Q_PROPERTY(int processedPhotos READ processedPhotos NOTIFY processedPhotosChanged)
    Q_PROPERTY(bool needsRescan READ needsRescan NOTIFY needsRescanChanged)
    // Privacy switch: when false the app never reads device contacts, even
    // though the Contacts permission is granted (persisted setting)
    Q_PROPERTY(bool contactsEnabled READ contactsEnabled WRITE setContactsEnabled NOTIFY contactsEnabledChanged)

public:
    // Bump when embedding computation changes (model, alignment,
    // preprocessing...); stored embeddings are then incompatible and a full
    // re-scan is forced
    static constexpr int EMBEDDING_VERSION = 3;

    // Thresholds on the rescaled similarity (cosine mapped from [-1,1] to
    // [0,1]). SFace's official same-identity cosine threshold is 0.363,
    // i.e. ~0.68 rescaled. Auto-assign must be stricter than interactive
    // suggestions: a silent wrong match poisons the person prototype.
    static constexpr float AUTO_MATCH_THRESHOLD = 0.72f;
    static constexpr float GROUPING_THRESHOLD = 0.68f;

    // Floor for offering a person as an identification suggestion. Well
    // below the same-identity threshold on purpose: the user confirms, so a
    // plausible-but-wrong name costs a glance, while a missing one costs
    // typing the whole name.
    static constexpr float SUGGEST_THRESHOLD = 0.55f;

    // Nudge for someone photographed around the same day. Small enough that
    // it only ever reorders candidates of comparable facial similarity.
    static constexpr float SAME_DAY_BONUS = 0.02f;

    explicit FacePipeline(QObject *parent = nullptr);
    ~FacePipeline();

    /**
     * @brief Initialize the pipeline
     * @param detectorModelPath Path to YuNet model
     * @param recognizerModelPath Path to ArcFace model
     * @param databasePath Path to SQLite database
     * @return true if initialized successfully
     */
    Q_INVOKABLE bool initialize(const QString &detectorModelPath,
                                const QString &recognizerModelPath,
                                const QString &databasePath);

    /**
     * @brief Scan gallery and process photos
     *
     * Incremental by default: photos already processed are skipped. When
     * forceRescan is true (or stored embeddings are outdated), existing
     * faces are recomputed.
     *
     * @param galleryPath Path to gallery (e.g., ~/Pictures)
     * @param recursive Scan subdirectories
     * @param forceRescan Re-process photos already scanned
     */
    Q_INVOKABLE void scanGallery(const QString &galleryPath, bool recursive = true,
                                 bool forceRescan = false);

    /**
     * @brief Scan several gallery folders in one pass
     *
     * Same behaviour as scanGallery but accumulates image files across all
     * given folders (deduplicated). Used by the folder whitelist so the SD
     * card and internal storage can be scanned together.
     */
    Q_INVOKABLE void scanGalleries(const QStringList &galleryPaths, bool recursive = true,
                                   bool forceRescan = false);

    /**
     * @brief Process a single photo
     * @param photoPath Path to photo file
     * @return Processing result
     */
    Q_INVOKABLE PhotoProcessingResult processPhoto(const QString &photoPath);

    /**
     * @brief Group unknown faces by similarity
     * @param similarityThreshold Threshold for grouping (default: 0.7)
     * @return Number of groups created
     */
    Q_INVOKABLE int groupUnknownFaces(float similarityThreshold = GROUPING_THRESHOLD);

    /**
     * @brief Identify a face as a person
     * @param faceId Face ID
     * @param personId Person ID (or -1 to create new person)
     * @param personName Name for new person (if personId == -1)
     */
    Q_INVOKABLE bool identifyFace(int faceId, int personId, const QString &personName = QString(),
                                  const QString &contactId = QString());

    /**
     * @brief Cancel current operation
     */
    Q_INVOKABLE void cancel();

    /**
     * @brief Get all people from database
     * @return List of people as QVariantList
     */
    Q_INVOKABLE QVariantList getAllPeople();

    /**
     * @brief Get photos for a specific person
     * @param personId Person ID
     * @return List of photo paths as QVariantList
     */
    Q_INVOKABLE QVariantList getPersonPhotos(int personId);

    /**
     * @brief Every scanned photo, regardless of whether it has an
     *        identified person (or any face at all)
     *
     * Used to optionally fill out Events with photos that have no
     * identified person, e.g. landscapes or unidentified faces.
     */
    Q_INVOKABLE QVariantList getAllPhotos();

    /**
     * @brief Best face of a person for avatar display
     * @param personId Person ID
     * @return Map with face_id, photo_path and normalized bbox fields,
     *         empty map when the person has no faces
     */
    Q_INVOKABLE QVariantMap getPersonBestFace(int personId);

    /**
     * @brief Delete a person and unmap their faces
     * @param personId Person ID
     * @return true if successful
     */
    Q_INVOKABLE bool deletePerson(int personId);

    /**
     * @brief Update person's name
     * @param personId Person ID
     * @param name New name
     * @return true if successful
     */
    Q_INVOKABLE bool updatePersonName(int personId, const QString &name);

    /**
     * @brief Link (or unlink with empty id) a person to a device contact
     * @return true if successful
     */
    Q_INVOKABLE bool linkPersonToContact(int personId, const QString &contactId);

    /**
     * @brief Contact id linked to a person, empty when none
     */
    Q_INVOKABLE QString personContactId(int personId);

    /**
     * @brief User-applied rotation for a photo (degrees, 0 when none)
     */
    Q_INVOKABLE int photoRotation(const QString &photoPath);

    /**
     * @brief Persist a user-applied rotation for a photo
     */
    Q_INVOKABLE bool setPhotoRotation(const QString &photoPath, int rotation);

    /**
     * @brief File and EXIF details for the photo viewer's info panel
     *
     * Works for any readable file: values known only from the database
     * (date taken, GPS) are filled in when the photo has been scanned, and
     * the file-level ones (name, folder, size, dimensions) always are.
     *
     * @return Map with file_name, folder, file_path, exists, file_size,
     *         width, height, date_taken, has_location, latitude, longitude,
     *         in_library
     */
    Q_INVOKABLE QVariantMap photoDetails(const QString &photoPath);

    /**
     * @brief Size on disk of one photo, in bytes (0 when unreadable)
     *
     * Used to keep a running total while selecting photos to share: what
     * makes a share fail is the payload size, not the number of files.
     */
    Q_INVOKABLE qint64 fileSize(const QString &photoPath);

    /**
     * @brief Forget photos that are no longer on disk
     *
     * Runs automatically at the end of every scan, which is free because the
     * gallery has just been walked. Exposed so the user can also trigger it
     * from Settings without waiting for a scan.
     *
     * @return Number of photos removed
     */
    Q_INVOKABLE int removeMissingPhotos();

    /**
     * @brief Merge one person into another
     *
     * All faces of fromPersonId are reassigned to intoPersonId and
     * fromPersonId is deleted. Needed to converge when clustering created
     * duplicates of the same human.
     *
     * @param fromPersonId Person to dissolve
     * @param intoPersonId Person that receives the faces
     * @return true if successful
     */
    Q_INVOKABLE bool mergePersons(int fromPersonId, int intoPersonId);

    /**
     * @brief Get all unmapped faces
     * @return List of faces as QVariantList
     */
    Q_INVOKABLE QVariantList getUnmappedFaces();

    /**
     * @brief People this face most likely belongs to, best first
     *
     * Ranks known people by how close their exemplars are to this face,
     * so identification usually costs one tap instead of typing a name.
     * Only candidates the user could plausibly accept are returned: people
     * already rejected for this face, or already tagged on another face of
     * the same photo, are left out.
     *
     * @return List of {person_id, name, score, strong, same_day}, where
     *         score is the raw similarity in [0,1] and strong marks a match
     *         above the same-identity threshold
     */
    Q_INVOKABLE QVariantList suggestPeopleForFace(int faceId, int maxCount = 3);

    /**
     * @brief Remove face from person (unassign)
     *
     * Records a rejection so auto-matching never reassigns this face to
     * the same person.
     *
     * @param faceId Face ID to remove from person
     * @return true if successful
     */
    Q_INVOKABLE bool removeFaceFromPerson(int faceId);

    /**
     * @brief Detach a person from a whole photo (all their faces in it)
     * @return true if successful
     */
    Q_INVOKABLE bool removePersonFromPhoto(int personId, int photoId);

    /**
     * @brief Permanently ignore a face (false positive, stranger, low quality)
     *
     * Ignored faces no longer appear in the identify flow or clustering.
     *
     * @param faceId Face ID to ignore
     * @return true if successful
     */
    Q_INVOKABLE bool ignoreFace(int faceId);

    /**
     * @brief Get database statistics
     * @return QVariantMap with stats (total_photos, total_faces, total_people, db_size_bytes)
     */
    Q_INVOKABLE QVariantMap getStatistics();

    /**
     * @brief How many photos in these folders have never been scanned
     *
     * Walks the folders and counts what is not already in the database. No
     * pixels are read, only names, but it is still a directory walk over a
     * whole gallery: call it off the first frame, not from a binding.
     *
     * The folders come from the caller because the settings that hold them
     * are already read in QML, where a scan is started from.
     */
    Q_INVOKABLE int unscannedPhotoCount(const QStringList &folders);

    /**
     * @brief Delete all face recognition data
     * @return true if successful
     */
    Q_INVOKABLE bool deleteAllData();

    /**
     * @brief Export all data to a JSON file (GDPR data portability)
     * @return Path of the written file, or empty string on failure
     */
    Q_INVOKABLE QString exportData();

    /**
     * @brief Write a complete backup (photos, faces incl. embeddings,
     *        people, trips) meant to be restored on another device
     *
     * Encrypted with the given passphrase (AES-256-GCM); there is no way
     * to recover the backup if the passphrase is lost.
     *
     * @return Path of the written file, or empty string on failure
     */
    Q_INVOKABLE QString exportBackupData(const QString &passphrase);

    /**
     * @brief List Nami backup files found directly in a folder
     * @return List of maps with file_path, exported_at, total_photos,
     *         total_people, sorted newest first
     */
    Q_INVOKABLE QVariantList listBackupFiles(const QString &folderPath);

    /**
     * @brief Restore a backup written by exportBackupData()
     *
     * passphrase is ignored for a (legacy, pre-encryption) plaintext
     * backup file.
     *
     * @return Map with photos_imported, photos_relinked, photos_skipped,
     *         people_imported, faces_imported, trips_imported, or an empty
     *         map if the file couldn't be read, or the passphrase was
     *         wrong / the file is corrupted
     */
    Q_INVOKABLE QVariantMap importBackupData(const QString &filePath, const QString &passphrase);

    /**
     * @brief Compute the content hash of every already-scanned photo that
     *        doesn't have one yet (photos scanned before this feature
     *        existed). Runs in the background; harmless to call repeatedly,
     *        a no-op once every photo has a hash. New scans always store a
     *        hash directly, this only backfills old ones.
     */
    Q_INVOKABLE void backfillPhotoHashes();

    /**
     * @brief Read a persisted app setting (settings table)
     */
    Q_INVOKABLE QString getSetting(const QString &key, const QString &defaultValue = QString());

    /**
     * @brief Persist an app setting; threshold changes take effect immediately
     */
    Q_INVOKABLE bool setSetting(const QString &key, const QString &value);

    /**
     * @brief Mark all auto-matched faces of a person as user-verified
     * @return Number of faces confirmed
     */
    Q_INVOKABLE int confirmAllFaces(int personId);

    /**
     * @brief Mark one auto-matched face as user-verified
     *
     * Lets the user accept a single suggestion from the person's photo grid
     * instead of confirming every match at once.
     *
     * @return true when the face existed and was not already verified
     */
    Q_INVOKABLE bool confirmFace(int faceId);

    /**
     * @brief Take back the confirmation on one face
     *
     * The face keeps its person; it simply stops being user-verified, so it
     * no longer defines the person's prototype. This is the undo for a
     * mistaken confirmation - to say "this is not them", remove the person
     * from the photo instead.
     *
     * @return true when the face existed and was verified
     */
    Q_INVOKABLE bool unconfirmFace(int faceId);

    // === Trips (user-named groups of day-events, e.g. a holiday) ===

    /**
     * @brief Get all trips
     * @return List of maps with trip_id, name, date_keys (yyyy-MM-dd list)
     */
    Q_INVOKABLE QVariantList getTrips();

    /**
     * @brief Group several day-events into a named trip
     * @param name Trip name (e.g. "Rome")
     * @param dateKeys Dates to group, each "yyyy-MM-dd"
     * @return Trip ID or -1 on error
     */
    Q_INVOKABLE int createTrip(const QString &name, const QStringList &dateKeys);

    /**
     * @brief Rename an existing trip
     */
    Q_INVOKABLE bool renameTrip(int tripId, const QString &name);

    /**
     * @brief Delete a trip; its dates go back to being separate day-events
     */
    Q_INVOKABLE bool deleteTrip(int tripId);

    /**
     * @brief Merge fromTripId's dates into intoTripId and delete fromTripId
     */
    Q_INVOKABLE bool mergeTrips(int fromTripId, int intoTripId);

    /**
     * @brief Add more day-event dates to an existing trip
     */
    Q_INVOKABLE bool addDatesToTrip(int tripId, const QStringList &dateKeys);

    /**
     * @brief Hide a day or trip event key from the Events list
     */
    Q_INVOKABLE bool hideEvent(const QString &eventKey);

    /**
     * @brief Reverse hideEvent()
     */
    Q_INVOKABLE bool unhideEvent(const QString &eventKey);

    /**
     * @brief All currently hidden event keys
     */
    Q_INVOKABLE QStringList getHiddenEvents();

    /**
     * @brief Set the cover photo for a day ("day:yyyy-MM-dd") or trip
     *        ("trip:<id>") event key
     */
    Q_INVOKABLE bool setEventCover(const QString &eventKey, const QString &photoPath);

    /**
     * @brief Clear a stored cover, reverting to the automatic choice
     */
    Q_INVOKABLE bool clearEventCover(const QString &eventKey);

    /**
     * @brief All stored covers, event key -> photo file path
     */
    Q_INVOKABLE QVariantMap getEventCovers();

    /**
     * @brief Most recently taken photos for the cover page animation
     * @param limit Maximum number of photos to return
     */
    Q_INVOKABLE QVariantList getCoverPhotos(int limit = 30);

    // === Memories (generated stories) ===

    /**
     * @brief Run the memory recipes
     *
     * Throttled to once a day internally, so QML can call it on every
     * launch. Cheap when it has already run: one settings lookup.
     *
     * @param force Skip the throttle (a manual refresh)
     * @return How many memories were created or refreshed
     */
    Q_INVOKABLE int generateMemories(bool force = false);

    /**
     * @brief All memories, best first
     * @return List of maps with memory_id, kind, title, subtitle, cover_photo,
     *         style, track_id, timestamp, photo_count, dismissed, edited
     */
    Q_INVOKABLE QVariantList getMemories(bool includeDismissed = false);

    /**
     * @brief A single memory; memory_id is -1 when there is no such row
     */
    Q_INVOKABLE QVariantMap getMemory(int memoryId);

    /**
     * @brief A memory's photos in playback order
     * @param includedOnly Skip the ones the user excluded (what a clip plays);
     *        pass false for the full set the editor shows
     */
    Q_INVOKABLE QVariantList getMemoryPhotos(int memoryId, bool includedOnly = true);

    /**
     * @brief Rename a memory; stops recipes from refreshing it
     */
    Q_INVOKABLE bool renameMemory(int memoryId, const QString &title);

    /**
     * @brief Choose the clip style (sentimental|energetic|polaroid|bauhaus)
     */
    Q_INVOKABLE bool setMemoryStyle(int memoryId, const QString &style);

    /**
     * @brief Choose the music track; empty reverts to the style's default
     */
    Q_INVOKABLE bool setMemoryTrack(int memoryId, const QString &trackId);

    /**
     * @brief Pin a cover photo; empty reverts to "the first photo"
     */
    Q_INVOKABLE bool setMemoryCover(int memoryId, const QString &photoPath);

    /**
     * @brief Reorder a memory's photos, listing their photo ids in order
     */
    Q_INVOKABLE bool reorderMemoryPhotos(int memoryId, const QVariantList &photoIds);

    /**
     * @brief Take a photo out of a memory's clip, or put it back
     */
    Q_INVOKABLE bool setMemoryPhotoIncluded(int memoryId, int photoId, bool included);

    /**
     * @brief Hide a memory from the lists; recipes will not resurrect it
     */
    Q_INVOKABLE bool setMemoryDismissed(int memoryId, bool dismissed);

    /**
     * @brief Drop a memory outright (its recipe may generate it again)
     */
    Q_INVOKABLE bool deleteMemory(int memoryId);

    /**
     * @brief How many photos a chosen group of people would give
     *
     * So a picker can say what it is about to make before making it, and so
     * choosing a fourth person who is never in the frame with the other
     * three shows as zero rather than as an empty memory afterwards.
     *
     * @param together Photos where all of them appear at once, rather than
     *        every photo any of them is in
     */
    Q_INVOKABLE int countPhotosOfPeople(const QVariantList &personIds, bool together);

    /**
     * @brief Make a memory out of a chosen group of people
     *
     * The recipes already do this for pairs that keep turning up together.
     * This is the same thing asked for rather than found, so it is marked
     * edited on creation: a recipe must never rewrite a choice somebody
     * made deliberately.
     *
     * @return Memory ID, or -1 when the group has too few photos between them
     */
    Q_INVOKABLE int createPeopleMemory(const QVariantList &personIds, bool together);

    /**
     * @brief Compose a memory into an edit the player can run
     *
     * The map holds duration_ms, track_start_ms, style, track_id, aspect, a
     * grade, and a shots list of { file_path, start_ms, duration_ms,
     * transition, transition_ms, from_x/y/w/h, to_x/y/w/h }. Rectangles are
     * normalized crops in the source photo, and the shot moves from the
     * first to the second.
     *
     * Empty when the memory has too few photos, or when the track cannot
     * hold a single shot.
     *
     * @param styleId Composes with this style instead of the stored one, so
     *        a picker can preview without writing anything down
     */
    Q_INVOKABLE QVariantMap composeMemoryClip(int memoryId,
                                              const QString &styleId = QString());

    /**
     * @brief The clip styles, in the order a picker should offer them
     * @return List of maps with id and default_track_id
     */
    Q_INVOKABLE QVariantList memoryStyles();

    /**
     * @brief Absolute path of a bundled track, empty when it is not there
     *
     * The tracks are supplied separately from the code, so a style whose
     * audio has not landed yet must play silently rather than not at all.
     */
    Q_INVOKABLE QString trackPath(const QString &trackId);

    /**
     * @brief Where the bundled music and beat grids live
     */
    void setMediaDir(const QString &dir) { m_mediaDir = dir; }

    // === Property getters ===

    bool isInitialized() const { return m_initialized; }
    bool isProcessing() const { return m_processing; }
    bool contactsEnabled() const { return m_contactsEnabled; }
    void setContactsEnabled(bool enabled);
    int totalPhotos() const { return m_totalPhotos; }
    int processedPhotos() const { return m_processedPhotos; }
    bool needsRescan() const { return m_needsRescan; }

signals:
    void initializedChanged();
    void processingChanged();
    void totalPhotosChanged();
    void processedPhotosChanged();
    void needsRescanChanged();
    void contactsEnabledChanged();

    void scanStarted(int totalPhotos);
    void scanProgress(int current, int total, const QString &currentFile);
    void scanCompleted(int photosProcessed, int facesDetected);
    void scanFailed(const QString &error);

    void photoProcessed(const PhotoProcessingResult &result);

    void error(const QString &message);

    // Emitted when backfillPhotoHashes() finishes (count of photos hashed)
    void hashBackfillCompleted(int count);

private:
    /**
     * @brief The track's analysed beat grid, or an even one at the style's
     *        tempo when there is none
     */
    BeatGrid loadBeatGrid(const QString &trackId, const MemoryStyle &style);

    FaceDetector *m_detector;
    FaceRecognizer *m_recognizer;
    FaceDatabase *m_database;

    // Bundled music and beat grids; set by main.cpp, empty in tests
    QString m_mediaDir;

    bool m_initialized;
    bool m_processing;
    bool m_cancelRequested;
    bool m_needsRescan;
    bool m_contactsEnabled;
    bool m_currentScanIsForced;
    int m_totalPhotos;
    int m_processedPhotos;
    int m_totalFacesDetected;
    QStringList m_pendingFiles;

    // One photo in flight at a time: extraction runs on a worker thread,
    // DB commit happens back on the main thread (QSqlDatabase affinity)
    QFutureWatcher<PhotoExtraction> m_extractionWatcher;

    // Backfills file_hash for photos scanned before that column existed;
    // computed as one batch on a worker thread, applied on completion
    QFutureWatcher<QVector<QPair<int, QString>>> m_hashBackfillWatcher;

    // Person exemplars cache (up to 5 verified embeddings per person);
    // recomputing them from the DB for every detected face is
    // O(persons x faces) queries per photo
    QVector<QPair<int, QVector<FaceEmbedding>>> m_personExemplarCache;
    bool m_personProtoCacheValid;

    // User-tunable auto-assign threshold (persisted in the settings table,
    // defaults to AUTO_MATCH_THRESHOLD)
    float m_autoMatchThreshold;

    // Helper: Start extraction of the next pending photo (scan loop)
    void processNextPhoto();

    // Helper: Commit a finished extraction and continue the scan loop
    void onExtractionFinished();

    // Helper: Apply hashes computed by backfillPhotoHashes()
    void onHashBackfillFinished();

    // Helper: Finish the scan (completed or cancelled)
    void finishScan(bool cancelled);

    // Helper: CPU-heavy part, safe to run on a worker thread (no DB)
    PhotoExtraction extractPhotoData(const QString &photoPath);

    // Helper: DB part, main thread only
    PhotoProcessingResult commitExtraction(const PhotoExtraction &extraction, bool reprocess);

    // Helper: Find image files in directory
    QStringList findImageFiles(const QString &directory, bool recursive);

    // Helper: Load and validate image
    QImage loadImage(const QString &filePath);

    // Helper: Match face against cached person exemplars (max similarity
    // over each person's exemplar embeddings)
    FaceMatch matchFaceToDatabase(const FaceEmbedding &embedding,
                                  float threshold = AUTO_MATCH_THRESHOLD);

    // Helper: Person exemplars, cached
    const QVector<QPair<int, QVector<FaceEmbedding>>> &personExemplars();
    void invalidatePersonPrototypes();

    // Helper: Replace one person's cached exemplars, when only they changed
    void refreshPersonExemplars(int personId, const QVector<FaceEmbedding> &exemplars);
};

#endif // FACEPIPELINE_H
