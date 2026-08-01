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
#include "facerecognizer.h"

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
 * @brief User-named group of day-events (e.g. a multi-day trip)
 */
struct Trip {
    int id;
    QString name;
    QDateTime createdAt;
    QStringList dateKeys;  // "yyyy-MM-dd" dates grouped into this trip
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
     *        and rejections. Unlike exportPersonData()/GDPR export, nothing
     *        is omitted here since this is meant to be re-imported.
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
