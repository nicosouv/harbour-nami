#ifndef FACEDATABASE_H
#define FACEDATABASE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QSet>
#include <QVariantMap>
#include <QDateTime>
#include <QSqlDatabase>
#include <QJsonObject>
#include <QPair>
#include <QRectF>
#include "faceembedding.h"

/**
 * @brief Photo record
 */
struct Photo {
    int id;
    QString filePath;
    QDateTime dateTaken;
    int width;
    int height;
    QDateTime processedAt;
    int rotation;  // user-applied rotation in degrees (0/90/180/270)
    bool hasLocation;  // GPS coordinates were present in EXIF
    double latitude;
    double longitude;
    QString fileHash;  // SHA-256 of the file's bytes, empty until computed
};

/**
 * @brief A person's photo together with their best face in it
 *
 * Deliberately without the embedding: the grids never look at it, and
 * deserializing 512 bytes per face for a few hundred photos is pure waste.
 */
struct PersonPhoto {
    Photo photo;
    int faceId;
    QRectF bbox;
    float similarityScore;
    bool verified;
};

/**
 * @brief User-named group of day-events (e.g. a multi-day trip)
 */
struct Trip {
    int id;
    QString name;
    QDateTime createdAt;
    QStringList dateKeys;  // "yyyy-MM-dd" dates grouped into this trip
};

/**
 * @brief A generated story: an ordered set of photos with a title, a cover
 *        and a clip style
 *
 * Identified by (kind, sourceKey) rather than by id, so re-running a recipe
 * updates its memory instead of piling up duplicates.
 */
struct Memory {
    int id = -1;
    QString kind;        // anniversary|trip|event|person|duo|month
    QString sourceKey;   // what the recipe keyed on: "2023", a trip id, ...
    QString title;
    QString subtitle;
    QString coverPhoto;  // resolved on read: the chosen cover, else the first photo
    QString style;       // sentimental|energetic|polaroid|bauhaus
    QString trackId;     // empty means "whatever the style defaults to"
    QDateTime sortDate;  // what the memory is about, not when it was generated
    double score = 0.0;  // recipe confidence; ranks which one leads the home
    bool dismissed = false;
    bool edited = false; // the user reordered, excluded or renamed: stop regenerating
    QDateTime createdAt;
    int photoCount = 0;  // included photos, filled in by the read queries
};

/**
 * @brief A photo's place in a memory
 */
struct MemoryPhoto {
    Photo photo;
    int position;
    bool included;
};

/**
 * @brief A photo reduced to what the memory recipes rank and space out
 *
 * Deliberately not a Photo: a recipe looks at a few thousand candidates to
 * keep forty, and it only needs when the photo was taken and whether anyone
 * it knows is in it.
 */
struct MemoryCandidate {
    int photoId;
    QDateTime dateTaken;
    int faceCount;  // identified faces, so photos of people outrank scenery
};

/**
 * @brief Two people who keep turning up in the same photos
 */
struct PeoplePair {
    int personA;
    int personB;
    int sharedPhotos;
};

/**
 * @brief Person record
 */
struct Person {
    int id;
    QString name;
    QDateTime createdAt;
    int photoCount;
    QString contactId;  // linked device contact id, empty when unlinked
    QDateTime lastPhoto;  // capture date of their most recent photo; invalid
                          // when none of their photos carries a usable date
};

/**
 * @brief Face record
 */
struct Face {
    int id;
    int photoId;
    QRectF bbox;
    float confidence;
    FaceEmbedding embedding;
    int personId;  // -1 if unmapped
    float similarityScore;  // Similarity score when matched (0.0-1.0)
    bool verified;  // true if manually verified by user
    QDateTime detectedAt;
};

/**
 * @brief SQLite database manager for faces and photos
 *
 * Manages:
 * - Photos metadata
 * - Face detections with embeddings
 * - People and face mappings
 * - GDPR compliance (export, deletion)
 */
class FaceDatabase : public QObject
{
    Q_OBJECT

public:
    explicit FaceDatabase(QObject *parent = nullptr);
    ~FaceDatabase();

    /**
     * @brief Open database connection
     * @param dbPath Path to SQLite database file
     * @return true if opened successfully
     */
    bool open(const QString &dbPath);

    /**
     * @brief Close database connection
     */
    void close();

    /**
     * @brief Initialize database schema
     * @return true if successful
     */
    bool initializeSchema();

    // === Transactions (batch several writes, e.g. one photo commit) ===

    bool beginTransaction();
    bool commitTransaction();
    bool rollbackTransaction();

    // === Photo operations ===

    /**
     * @brief Add photo to database
     *
     * If the photo already exists (same file_path) and fileHash is given
     * while the stored row has none yet, the row is backfilled with it.
     *
     * @return Photo ID or -1 on error
     */
    int addPhoto(const QString &filePath, const QDateTime &dateTaken,
                 int width, int height, bool hasLocation = false,
                 double latitude = 0.0, double longitude = 0.0,
                 const QString &fileHash = QString());

    /**
     * @brief Store (or backfill) a photo's content hash
     */
    bool setPhotoHash(int photoId, const QString &fileHash);

    /**
     * @brief Find a photo by content hash (used when its path has changed)
     * @return Photo ID, or -1 if no photo has this hash
     */
    int findPhotoByHash(const QString &fileHash);

    /**
     * @brief (id, file_path) of every photo that has no stored hash yet
     */
    QVector<QPair<int, QString>> getPhotosMissingHash();

    /**
     * @brief Get photo by ID
     */
    Photo getPhoto(int photoId);

    /**
     * @brief Look a photo up by its file path
     * @return Photo with id == -1 when the path is not in the database
     */
    Photo getPhotoByPath(const QString &filePath);

    /**
     * @brief Forget photos whose file is no longer on disk
     *
     * Deleting a photo from the gallery leaves its row behind, which shows up
     * as an empty tile. This drops those rows along with their faces,
     * rejections and any event cover pointing at them.
     *
     * A photo whose whole folder has disappeared is left alone: that is what
     * an unmounted SD card looks like, and the identification work is not
     * recoverable once thrown away.
     *
     * @return Number of photos removed
     */
    int removeMissingPhotos();

    /**
     * @brief Get all photos
     */
    QVector<Photo> getAllPhotos();

    /**
     * @brief Mark photo as processed
     */
    bool markPhotoProcessed(int photoId);

    /**
     * @brief User-applied rotation for a photo (degrees, 0 when none)
     */
    int photoRotation(const QString &filePath);

    /**
     * @brief Persist a user-applied rotation for a photo
     */
    bool setPhotoRotation(const QString &filePath, int rotation);

    // === Face operations ===

    /**
     * @brief Add face detection to database
     * @return Face ID or -1 on error
     */
    int addFace(int photoId, const QRectF &bbox, float confidence,
                const FaceEmbedding &embedding, int personId = -1,
                float similarityScore = 0.0f, bool verified = false);

    /**
     * @brief Get face by ID
     */
    Face getFace(int faceId);

    /**
     * @brief Get all faces for a photo
     */
    QVector<Face> getFacesForPhoto(int photoId);

    /**
     * @brief Get all unmapped faces (personId = -1)
     */
    QVector<Face> getUnmappedFaces();

    /**
     * @brief Update face's person mapping
     */
    bool updateFacePersonMapping(int faceId, int personId);

    /**
     * @brief Update face metadata (similarity score, verified status)
     */
    bool updateFaceMetadata(int faceId, float similarityScore, bool verified);

    /**
     * @brief Remove face from person (set person_id to -1)
     */
    bool removeFaceFromPerson(int faceId);

    /**
     * @brief Unassign every face of a person within a single photo
     *
     * A photo may contain several faces mapped to the same person; removing
     * only the best one leaves the photo attached. This clears them all and
     * records a rejection for each so auto-matching won't reassign them.
     */
    bool removePersonFromPhoto(int personId, int photoId);

    /**
     * @brief Mark face as ignored (not a face / not worth identifying)
     */
    bool setFaceIgnored(int faceId, bool ignored);

    /**
     * @brief Record that a face must never be auto-matched to a person
     */
    bool addNegativeMatch(int faceId, int personId);

    /**
     * @brief Check if a face was rejected for a person
     */
    bool hasNegativeMatch(int faceId, int personId);

    /**
     * @brief Every person this face was rejected for, in one query
     *
     * Same answer as calling hasNegativeMatch() for each person, without
     * one round-trip per person when ranking suggestions.
     */
    QSet<int> getNegativeMatches(int faceId);

    /**
     * @brief People with a face on a photo taken around the given date
     *
     * Who you were with that day: a weak but useful hint when ranking
     * identification suggestions.
     *
     * @param days Half-width of the window, in days
     */
    QSet<int> getPeopleAroundDate(const QDateTime &date, int days = 1);

    /**
     * @brief Delete all faces of a photo (used when re-processing)
     */
    bool deleteFacesForPhoto(int photoId);

    /**
     * @brief File paths of photos already processed (for incremental scans)
     */
    QSet<QString> getProcessedFilePaths();

    // === Person operations ===

    /**
     * @brief Create new person
     * @return Person ID or -1 on error
     */
    int createPerson(const QString &name);

    /**
     * @brief Get person by ID
     */
    Person getPerson(int personId);

    /**
     * @brief Get all people
     */
    QVector<Person> getAllPeople();

    /**
     * @brief Update person name
     */
    bool updatePersonName(int personId, const QString &name);

    /**
     * @brief Link a person to a device contact (empty id unlinks)
     */
    bool setPersonContact(int personId, const QString &contactId);

    /**
     * @brief Delete person and unmap their faces
     */
    bool deletePerson(int personId);

    /**
     * @brief Merge fromPersonId into intoPersonId and delete fromPersonId
     *
     * Faces, verified flags and rejections carry over.
     */
    bool mergePersons(int fromPersonId, int intoPersonId);

    /**
     * @brief Every photo a person appears in, with their best face in each
     *
     * One joined query rather than a face query followed by a photo lookup
     * per photo: that N+1 was several hundred round trips to show one page.
     */
    QVector<PersonPhoto> getPhotosForPerson(int personId);

    /**
     * @brief Get all faces for a person
     */
    QVector<Face> getFacesForPerson(int personId);

    /**
     * @brief Best face of a person for display (verified first, then
     *        highest similarity, then detection confidence)
     * @return Face with id -1 when the person has no faces
     */
    Face getBestFaceForPerson(int personId);

    /**
     * @brief Exemplar embeddings representing a person for matching
     *
     * Up to maxCount embeddings, user-verified faces first (best
     * similarity), falling back to the most confident detections when the
     * person has no verified face yet. Multiple exemplars capture the
     * different looks of a person (glasses, age, lighting) better than a
     * single averaged centroid.
     */
    QVector<FaceEmbedding> getPersonExemplars(int personId, int maxCount = 5);

    // === GDPR compliance ===

    /**
     * @brief Export all data for a person (GDPR right to data portability)
     */
    QVariantMap exportPersonData(int personId);

    /**
     * @brief Delete all data (GDPR right to be forgotten)
     */
    bool deleteAllData();

    // === Full backup (device migration) ===

    /**
     * @brief Counts reported by importBackup()
     */
    struct ImportStats {
        int photosImported = 0;
        int photosRelinked = 0;  // matched by content hash after its path changed
        int photosSkipped = 0;   // file no longer exists on this device
        int peopleImported = 0;
        int facesImported = 0;
        int tripsImported = 0;
    };

    /**
     * @brief Export every table needed to fully restore the app on another
     *        device: photos, faces (including embeddings), people, trips
     *        and rejections. Unlike exportPersonData()/GDPR export, only
     *        the links to the local address book are omitted, since those
     *        contacts are unlikely to exist on the target device.
     */
    QJsonObject exportBackup();

    /**
     * @brief Restore a backup produced by exportBackup()
     *
     * Additive: a photo already in the database (same file_path) or a
     * person with the same name is reused rather than duplicated, so this
     * is safe to run on a database that already has some data. A photo
     * whose file no longer exists on this device is skipped, along with
     * its faces, since there is nothing on disk to attach them to.
     */
    ImportStats importBackup(const QJsonObject &root);

    /**
     * @brief Delete faces, people and rejections but keep photo records
     *
     * Used when the recognition engine changes and embeddings must be
     * recomputed. Photos are marked unprocessed.
     */
    bool clearFaceData();

    // === Settings ===

    /**
     * @brief Get a value from the settings table
     */
    QString getSetting(const QString &key, const QString &defaultValue = QString());

    /**
     * @brief Store a value in the settings table
     */
    bool setSetting(const QString &key, const QString &value);

    // === Statistics ===

    /**
     * @brief Get database statistics
     */
    QVariantMap getStatistics();

    // === Trips ===

    /**
     * @brief Create a trip grouping the given day-event dates
     * @return Trip ID or -1 on error
     */
    int createTrip(const QString &name, const QStringList &dateKeys);

    /**
     * @brief Rename an existing trip
     */
    bool renameTrip(int tripId, const QString &name);

    /**
     * @brief Delete a trip (its dates go back to separate day-events)
     */
    bool deleteTrip(int tripId);

    /**
     * @brief Get all trips with their grouped dates
     */
    QVector<Trip> getAllTrips();

    /**
     * @brief Merge fromTripId's dates into intoTripId and delete fromTripId
     */
    bool mergeTrips(int fromTripId, int intoTripId);

    /**
     * @brief Add more day-event dates to an existing trip
     *
     * Dates already claimed by another trip are left alone (a date belongs
     * to at most one trip); the caller is expected to only offer ungrouped
     * days for selection.
     */
    bool addDatesToTrip(int tripId, const QStringList &dateKeys);

    // === Hidden events (user dismissed a day or trip from the Events list) ===

    /**
     * @brief Hide a day ("day:yyyy-MM-dd") or trip ("trip:<id>") event key
     *        from the Events list without touching its photos
     */
    bool hideEvent(const QString &eventKey);

    /**
     * @brief Reverse hideEvent()
     */
    bool unhideEvent(const QString &eventKey);

    /**
     * @brief All currently hidden event keys
     */
    QStringList getHiddenEvents();

    // === Event covers (user-chosen cover photo for a day or trip) ===

    /**
     * @brief Set the cover photo for a day ("day:yyyy-MM-dd") or trip
     *        ("trip:<id>") event key
     */
    bool setEventCover(const QString &eventKey, const QString &photoPath);

    /**
     * @brief Clear a stored cover, reverting to the automatic choice
     */
    bool clearEventCover(const QString &eventKey);

    /**
     * @brief All stored covers, event key -> photo file path
     */
    QVariantMap getEventCovers();

    // === Memories (generated stories) ===

    /**
     * @brief Create or refresh the memory identified by (kind, sourceKey)
     *
     * Idempotent, so a recipe can run every day without duplicating its
     * output. On an existing row the user's own choices are preserved
     * (style, track, cover, dismissed) while the generated fields (title,
     * subtitle, sort date, score, photo set) are refreshed. A memory the
     * user has edited is left completely alone.
     *
     * @param photoIds Photos in playback order
     * @return Memory ID or -1 on error
     */
    int upsertMemory(const Memory &memory, const QVector<int> &photoIds);

    /**
     * @brief All memories, best first (score, then most recent subject)
     *
     * Memories whose photos have all been deleted from disk are left out:
     * there is nothing left to show.
     */
    QVector<Memory> getMemories(bool includeDismissed = false);

    /**
     * @brief A single memory; its id is -1 when there is no such row
     */
    Memory getMemory(int memoryId);

    /**
     * @brief A memory's photos in playback order
     * @param includedOnly Skip the ones the user excluded (what a clip plays);
     *        pass false to get the full set the editor needs
     */
    QVector<MemoryPhoto> getMemoryPhotos(int memoryId, bool includedOnly = true);

    /**
     * @brief Rename a memory; marks it edited, so recipes stop refreshing it
     */
    bool renameMemory(int memoryId, const QString &title);

    /**
     * @brief Choose the clip style (sentimental|energetic|polaroid|bauhaus)
     */
    bool setMemoryStyle(int memoryId, const QString &style);

    /**
     * @brief Choose the music track; empty reverts to the style's default
     */
    bool setMemoryTrack(int memoryId, const QString &trackId);

    /**
     * @brief Pin a cover photo; empty reverts to "the first photo"
     */
    bool setMemoryCover(int memoryId, const QString &photoPath);

    /**
     * @brief Reorder a memory's photos
     *
     * Ids that are not part of the memory are ignored, the ones left out
     * keep their relative order after the listed ones, and whether a photo
     * is included is untouched. Marks the memory edited.
     */
    bool reorderMemoryPhotos(int memoryId, const QVector<int> &photoIds);

    /**
     * @brief Take a photo out of a memory's clip, or put it back
     *
     * The row is kept either way, so an exclusion can be undone. Marks the
     * memory edited.
     */
    bool setMemoryPhotoIncluded(int memoryId, int photoId, bool included);

    /**
     * @brief Hide a memory from the lists without deleting it
     *
     * Recipes see the dismissed row and will not resurrect it, which is why
     * this is what the UI should offer rather than deleteMemory().
     */
    bool setMemoryDismissed(int memoryId, bool dismissed);

    /**
     * @brief Drop a memory outright (its recipe may generate it again)
     */
    bool deleteMemory(int memoryId);

    // === Memory recipes (what MemoryGenerator asks for) ===
    //
    // Every one of these answers a whole question in SQL rather than handing
    // back the gallery for C++ to sift: the pages that group photos in
    // JavaScript already walk every person's every photo on each opening,
    // and that is exactly what this must not become.

    /**
     * @brief Photos taken on any of the given "MM-dd" days, before a year
     *
     * The caller passes the days rather than a window because the window is
     * circular: 30 December is three days from 2 January, which SQL date
     * arithmetic on ISO strings will not tell you.
     */
    QVector<MemoryCandidate> photosOnMonthDays(const QStringList &monthDays, int beforeYear);

    /**
     * @brief Photos taken on any of the given "yyyy-MM-dd" dates
     */
    QVector<MemoryCandidate> photosOnDates(const QStringList &dateKeys);

    /**
     * @brief Day keys holding at least minPhotos photos, most recent first
     */
    QVector<QPair<QString, int>> busiestDays(int minPhotos, int limit);

    /**
     * @brief Photos a person appears in, optionally only since a date
     */
    QVector<MemoryCandidate> photosOfPerson(int personId, const QDateTime &since = QDateTime());

    /**
     * @brief People who appear together on at least minPhotos photos,
     *        most shared photos first
     */
    QVector<PeoplePair> peopleSeenTogether(int minPhotos, int limit);

    /**
     * @brief Photos both of these people appear in
     */
    QVector<MemoryCandidate> photosOfPeoplePair(int personA, int personB);

    /**
     * @brief Photos of a chosen set of people
     *
     * @param together true for the photos where all of them appear at once,
     *        false for every photo any of them is in. With three or four
     *        people the two answers are worlds apart, which is why the
     *        caller says which one it means rather than being given a
     *        default that is wrong half the time.
     */
    QVector<MemoryCandidate> photosOfPeople(const QVector<int> &personIds, bool together);

    /**
     * @brief Photos taken in a calendar month
     */
    QVector<MemoryCandidate> photosInMonth(int year, int month);

    /**
     * @brief Every face box in a memory's photos, keyed by photo id
     *
     * One query for the whole memory rather than one per photo: composing a
     * clip needs all forty at once, and the boxes are what let the camera
     * move end on somebody's face instead of on the middle of the frame.
     * Embeddings are deliberately not read; nothing here compares anyone.
     */
    QHash<int, QVector<QRectF>> faceBoxesForMemory(int memoryId);

    // === Recent photos (cover page) ===

    /**
     * @brief Most recently taken photos, newest first
     */
    QVector<Photo> getRecentPhotos(int limit);

signals:
    void error(const QString &message);

private:
    QSqlDatabase m_db;
    QString m_dbPath;
    bool m_isOpen;

    // Helper: Serialize embedding to BLOB
    QByteArray serializeEmbedding(const FaceEmbedding &embedding);

    // Helper: Deserialize embedding from BLOB
    FaceEmbedding deserializeEmbedding(const QByteArray &data);

    // Helper: Execute query and log errors
    bool executeQuery(const QString &query);

    // Helper: Best unassigned face of a photo overlapping the given bbox
    // (import reconciliation after a photo was relinked by content hash)
    // Returns -1 when no unassigned face overlaps closely enough
    int findClosestUnassignedFace(int photoId, const QRectF &bbox);
};

#endif // FACEDATABASE_H
