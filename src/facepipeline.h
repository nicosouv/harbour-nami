#ifndef FACEPIPELINE_H
#define FACEPIPELINE_H

#include <QObject>
#include <QString>
#include <QImage>
#include <QVector>
#include <QFuture>
#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"

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

public:
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
     * @param galleryPath Path to gallery (e.g., ~/Pictures)
     * @param recursive Scan subdirectories
     */
    Q_INVOKABLE void scanGallery(const QString &galleryPath, bool recursive = true);

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
    Q_INVOKABLE int groupUnknownFaces(float similarityThreshold = 0.7f);

    /**
     * @brief Identify a face as a person
     * @param faceId Face ID
     * @param personId Person ID (or -1 to create new person)
     * @param personName Name for new person (if personId == -1)
     */
    Q_INVOKABLE bool identifyFace(int faceId, int personId, const QString &personName = QString());

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
     * @brief Get all unmapped faces
     * @return List of faces as QVariantList
     */
    Q_INVOKABLE QVariantList getUnmappedFaces();

    /**
     * @brief Remove face from person (unassign)
     * @param faceId Face ID to remove from person
     * @return true if successful
     */
    Q_INVOKABLE bool removeFaceFromPerson(int faceId);

    /**
     * @brief Get database statistics
     * @return QVariantMap with stats (total_photos, total_faces, total_people, db_size_bytes)
     */
    Q_INVOKABLE QVariantMap getStatistics();

    /**
     * @brief Delete all face recognition data
     * @return true if successful
     */
    Q_INVOKABLE bool deleteAllData();

    // === Property getters ===

    bool isInitialized() const { return m_initialized; }
    bool isProcessing() const { return m_processing; }
    int totalPhotos() const { return m_totalPhotos; }
    int processedPhotos() const { return m_processedPhotos; }

signals:
    void initializedChanged();
    void processingChanged();
    void totalPhotosChanged();
    void processedPhotosChanged();

    void scanStarted(int totalPhotos);
    void scanProgress(int current, int total, const QString &currentFile);
    void scanCompleted(int photosProcessed, int facesDetected);
    void scanFailed(const QString &error);

    void photoProcessed(const PhotoProcessingResult &result);

    void error(const QString &message);

private:
    FaceDetector *m_detector;
    FaceRecognizer *m_recognizer;
    FaceDatabase *m_database;

    bool m_initialized;
    bool m_processing;
    bool m_cancelRequested;
    int m_totalPhotos;
    int m_processedPhotos;
    int m_totalFacesDetected;
    QStringList m_pendingFiles;

    // Helper: Batch processing
    void processBatch();

    // Helper: Find image files in directory
    QStringList findImageFiles(const QString &directory, bool recursive);

    // Helper: Load and validate image
    QImage loadImage(const QString &filePath);

    // Helper: Extract face region from image
    cv::Mat extractFaceRegion(const cv::Mat &image, const QRectF &bbox,
                              const QVector<QPointF> &landmarks);

    // Helper: Process single photo (internal)
    PhotoProcessingResult processPhotoInternal(const QString &photoPath);

    // Helper: Match face against database
    FaceMatch matchFaceToDatabase(const FaceEmbedding &embedding, float threshold = 0.7f);
};

#endif // FACEPIPELINE_H
