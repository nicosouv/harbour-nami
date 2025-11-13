#ifndef FACEDATABASE_H
#define FACEDATABASE_H

#include <QObject>
#include <QString>
#include <QVector>
#include <QVariantMap>
#include <QDateTime>
#include <QSqlDatabase>
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
};

/**
 * @brief Person record
 */
struct Person {
    int id;
    QString name;
    QDateTime createdAt;
    int photoCount;
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

    // === Photo operations ===

    /**
     * @brief Add photo to database
     * @return Photo ID or -1 on error
     */
    int addPhoto(const QString &filePath, const QDateTime &dateTaken,
                 int width, int height);

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

    // === Face operations ===

    /**
     * @brief Add face detection to database
     * @return Face ID or -1 on error
     */
    int addFace(int photoId, const QRectF &bbox, float confidence,
                const FaceEmbedding &embedding, int personId = -1);

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
     * @brief Delete person and unmap their faces
     */
    bool deletePerson(int personId);

    /**
     * @brief Get all faces for a person
     */
    QVector<Face> getFacesForPerson(int personId);

    /**
     * @brief Get average embedding for a person
     */
    FaceEmbedding getAverageEmbedding(int personId);

    /**
     * @brief Get all person embeddings for matching
     * @return Vector of (personId, averageEmbedding) pairs
     */
    QVector<QPair<int, FaceEmbedding>> getAllPersonEmbeddings();

    // === GDPR compliance ===

    /**
     * @brief Export all data for a person (GDPR right to data portability)
     */
    QVariantMap exportPersonData(int personId);

    /**
     * @brief Delete all data (GDPR right to be forgotten)
     */
    bool deleteAllData();

    // === Statistics ===

    /**
     * @brief Get database statistics
     */
    QVariantMap getStatistics();

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
};

#endif // FACEDATABASE_H
