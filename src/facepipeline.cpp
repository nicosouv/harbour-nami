#include "facepipeline.h"
#include <QDebug>
#include <QDir>
#include <QImageReader>
#include <QFileInfo>
#include <QtConcurrent>
#include <QSet>

FacePipeline::FacePipeline(QObject *parent)
    : QObject(parent)
    , m_detector(nullptr)
    , m_recognizer(nullptr)
    , m_database(nullptr)
    , m_initialized(false)
    , m_processing(false)
    , m_cancelRequested(false)
    , m_totalPhotos(0)
    , m_processedPhotos(0)
{
}

FacePipeline::~FacePipeline()
{
    delete m_detector;
    delete m_recognizer;
    delete m_database;
}

bool FacePipeline::initialize(const QString &detectorModelPath,
                              const QString &recognizerModelPath,
                              const QString &databasePath)
{
    qDebug() << "Initializing face pipeline...";
    qDebug() << "  Detector model:" << detectorModelPath;
    qDebug() << "  Recognizer model:" << recognizerModelPath;
    qDebug() << "  Database:" << databasePath;

    // Create detector
    m_detector = new FaceDetector(this);
    if (!m_detector->loadModel(detectorModelPath)) {
        emit error("Failed to load face detector model");
        return false;
    }

    // Create recognizer
    m_recognizer = new FaceRecognizer(this);
    if (!m_recognizer->loadModel(recognizerModelPath)) {
        emit error("Failed to load face recognizer model");
        return false;
    }

    // Create database
    m_database = new FaceDatabase(this);
    if (!m_database->open(databasePath)) {
        emit error("Failed to open database");
        return false;
    }

    m_initialized = true;
    emit initializedChanged();

    qDebug() << "Face pipeline initialized successfully";
    return true;
}

void FacePipeline::scanGallery(const QString &galleryPath, bool recursive)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return;
    }

    if (m_processing) {
        emit error("Already processing");
        return;
    }

    m_processing = true;
    m_cancelRequested = false;
    emit processingChanged();

    qDebug() << "Scanning gallery:" << galleryPath << "(recursive:" << recursive << ")";

    // Find all image files
    QStringList imageFiles = findImageFiles(galleryPath, recursive);
    m_totalPhotos = imageFiles.size();
    m_processedPhotos = 0;

    emit totalPhotosChanged();
    emit scanStarted(m_totalPhotos);

    qDebug() << "Found" << m_totalPhotos << "image files";

    int facesDetected = 0;

    // Process each photo
    for (const QString &filePath : imageFiles) {
        if (m_cancelRequested) {
            qDebug() << "Scan cancelled by user";
            break;
        }

        emit scanProgress(m_processedPhotos + 1, m_totalPhotos, filePath);

        PhotoProcessingResult result = processPhotoInternal(filePath);

        if (result.success) {
            facesDetected += result.facesDetected;
        }

        emit photoProcessed(result);

        m_processedPhotos++;
        emit processedPhotosChanged();
    }

    m_processing = false;
    emit processingChanged();

    if (m_cancelRequested) {
        emit scanFailed("Cancelled by user");
    } else {
        emit scanCompleted(m_processedPhotos, facesDetected);
        qDebug() << "Scan completed:" << m_processedPhotos << "photos," << facesDetected << "faces";
    }
}

PhotoProcessingResult FacePipeline::processPhoto(const QString &photoPath)
{
    if (!m_initialized) {
        return PhotoProcessingResult{-1, photoPath, 0, 0, false, "Pipeline not initialized"};
    }

    return processPhotoInternal(photoPath);
}

PhotoProcessingResult FacePipeline::processPhotoInternal(const QString &photoPath)
{
    PhotoProcessingResult result;
    result.filePath = photoPath;
    result.facesDetected = 0;
    result.facesMatched = 0;
    result.success = false;

    qDebug() << "";
    qDebug() << "╔═══════════════════════════════════════════════════════════════╗";
    qDebug() << "║ Processing photo:" << photoPath;
    qDebug() << "╚═══════════════════════════════════════════════════════════════╝";

    // Load image
    qDebug() << "→ Loading image...";
    QImage image = loadImage(photoPath);
    if (image.isNull()) {
        qWarning() << "✗ Failed to load image";
        result.errorMessage = "Failed to load image";
        return result;
    }
    qDebug() << "✓ Image loaded:" << image.width() << "x" << image.height() << "format:" << image.format();

    // Get or create photo record
    QFileInfo fileInfo(photoPath);
    QDateTime dateTaken = fileInfo.lastModified();  // Could use EXIF data

    qDebug() << "→ Adding photo to database...";
    int photoId = m_database->addPhoto(photoPath, dateTaken, image.width(), image.height());
    if (photoId < 0) {
        qWarning() << "✗ Failed to add photo to database";
        result.errorMessage = "Failed to add photo to database";
        return result;
    }
    qDebug() << "✓ Photo added to DB with ID:" << photoId;

    result.photoId = photoId;

    // Detect faces
    qDebug() << "→ Starting face detection...";
    QVector<FaceDetection> detections = m_detector->detect(image);
    result.facesDetected = detections.size();

    qDebug() << "✓ Face detection complete:" << detections.size() << "faces found";

    if (detections.isEmpty()) {
        qDebug() << "⚠ No faces detected in this image";
    }

    // Process each detected face
    for (int i = 0; i < detections.size(); i++) {
        const FaceDetection &detection = detections[i];
        qDebug() << "  → Processing face" << (i+1) << "/" << detections.size()
                 << "- confidence:" << detection.confidence;

        // Extract face region
        cv::Mat cvImage = m_detector->qImageToCvMat(image);
        cv::Mat faceRegion = extractFaceRegion(cvImage, detection.bbox, detection.landmarks);
        qDebug() << "    ✓ Face region extracted:" << faceRegion.cols << "x" << faceRegion.rows;

        // Extract embedding
        qDebug() << "    → Extracting face embedding...";
        FaceEmbedding embedding = m_recognizer->extractEmbedding(faceRegion);

        if (embedding.empty()) {
            qWarning() << "    ✗ Failed to extract embedding for face";
            continue;
        }
        qDebug() << "    ✓ Embedding extracted (size:" << embedding.size() << ")";

        // Match against database
        qDebug() << "    → Matching against database...";
        int matchedPersonId = matchFaceToDatabase(embedding);

        if (matchedPersonId >= 0) {
            result.facesMatched++;
            qDebug() << "    ✓ Matched to person ID:" << matchedPersonId;
        } else {
            qDebug() << "    ○ No match found (new face)";
        }

        // Store in database
        qDebug() << "    → Storing face in database...";
        int faceId = m_database->addFace(photoId, detection.bbox, detection.confidence,
                                         embedding, matchedPersonId);

        if (faceId < 0) {
            qWarning() << "    ✗ Failed to add face to database";
        } else {
            qDebug() << "    ✓ Face stored with ID:" << faceId;
        }
    }

    // Mark photo as processed
    m_database->markPhotoProcessed(photoId);

    result.success = true;
    qDebug() << "═══════════════════════════════════════════════════════════════";
    qDebug() << "Photo processing summary:";
    qDebug() << "  Faces detected:" << result.facesDetected;
    qDebug() << "  Faces matched:" << result.facesMatched;
    qDebug() << "═══════════════════════════════════════════════════════════════";
    qDebug() << "";

    return result;
}

int FacePipeline::groupUnknownFaces(float similarityThreshold)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return 0;
    }

    qDebug() << "Grouping unknown faces with threshold:" << similarityThreshold;

    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qDebug() << "Found" << unmappedFaces.size() << "unmapped faces";

    if (unmappedFaces.isEmpty()) {
        return 0;
    }

    // Simple clustering by similarity
    int groupsCreated = 0;
    QVector<bool> processed(unmappedFaces.size(), false);

    for (int i = 0; i < unmappedFaces.size(); i++) {
        if (processed[i]) {
            continue;
        }

        // Create new person for this group
        QString groupName = QString("Person %1").arg(groupsCreated + 1);
        int personId = m_database->createPerson(groupName);

        if (personId < 0) {
            continue;
        }

        // Assign this face to the new person
        m_database->updateFacePersonMapping(unmappedFaces[i].id, personId);
        processed[i] = true;

        // Find similar faces
        for (int j = i + 1; j < unmappedFaces.size(); j++) {
            if (processed[j]) {
                continue;
            }

            float similarity = FaceRecognizer::computeSimilarity(
                unmappedFaces[i].embedding,
                unmappedFaces[j].embedding
            );

            if (similarity >= similarityThreshold) {
                m_database->updateFacePersonMapping(unmappedFaces[j].id, personId);
                processed[j] = true;
            }
        }

        groupsCreated++;
    }

    qDebug() << "Created" << groupsCreated << "groups";
    return groupsCreated;
}

bool FacePipeline::identifyFace(int faceId, int personId, const QString &personName)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return false;
    }

    // Create new person if needed
    if (personId < 0 && !personName.isEmpty()) {
        personId = m_database->createPerson(personName);
        if (personId < 0) {
            emit error("Failed to create person");
            return false;
        }
    }

    // Update face mapping
    return m_database->updateFacePersonMapping(faceId, personId);
}

void FacePipeline::cancel()
{
    m_cancelRequested = true;
}

// === Helpers ===

QStringList FacePipeline::findImageFiles(const QString &directory, bool recursive)
{
    QStringList imageFiles;
    QDir dir(directory);

    // Supported image formats
    QStringList nameFilters;
    nameFilters << "*.jpg" << "*.jpeg" << "*.png" << "*.bmp" << "*.gif";

    QDir::Filters filters = QDir::Files | QDir::Readable;
    if (recursive) {
        filters |= QDir::AllDirs | QDir::NoDotAndDotDot;
    }

    QFileInfoList entries = dir.entryInfoList(nameFilters, filters);

    for (const QFileInfo &entry : entries) {
        if (entry.isDir() && recursive) {
            imageFiles.append(findImageFiles(entry.absoluteFilePath(), true));
        } else if (entry.isFile()) {
            imageFiles.append(entry.absoluteFilePath());
        }
    }

    return imageFiles;
}

QImage FacePipeline::loadImage(const QString &filePath)
{
    QImageReader reader(filePath);
    reader.setAutoTransform(true);  // Handle EXIF orientation

    QImage image = reader.read();

    if (image.isNull()) {
        qWarning() << "Failed to load image:" << filePath << "-" << reader.errorString();
    }

    return image;
}

cv::Mat FacePipeline::extractFaceRegion(const cv::Mat &image, const QRectF &bbox,
                                       const QVector<QPointF> &landmarks)
{
    // Convert normalized bbox to pixel coordinates
    int x = static_cast<int>(bbox.x() * image.cols);
    int y = static_cast<int>(bbox.y() * image.rows);
    int w = static_cast<int>(bbox.width() * image.cols);
    int h = static_cast<int>(bbox.height() * image.rows);

    // Clamp to image bounds
    x = std::max(0, std::min(x, image.cols - 1));
    y = std::max(0, std::min(y, image.rows - 1));
    w = std::min(w, image.cols - x);
    h = std::min(h, image.rows - y);

    // Extract face ROI
    cv::Rect roi(x, y, w, h);
    cv::Mat faceRegion = image(roi).clone();

    // TODO: Align face using landmarks for better recognition accuracy
    // For now, just return the cropped region

    return faceRegion;
}

int FacePipeline::matchFaceToDatabase(const FaceEmbedding &embedding, float threshold)
{
    // Get all person embeddings
    QVector<QPair<int, FaceEmbedding>> personEmbeddings = m_database->getAllPersonEmbeddings();

    if (personEmbeddings.isEmpty()) {
        return -1;  // No people in database yet
    }

    // Match against database
    FaceMatch match = FaceRecognizer::matchFace(embedding, personEmbeddings, threshold);

    if (match.personId >= 0) {
        qDebug() << "Matched face to person" << match.personId
                 << "with similarity" << match.similarity;
    }

    return match.personId;
}

QVariantList FacePipeline::getAllPeople()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    QVector<Person> people = m_database->getAllPeople();

    for (const Person &person : people) {
        QVariantMap personMap;
        personMap["person_id"] = person.id;
        personMap["name"] = person.name;
        personMap["photo_count"] = person.photoCount;
        personMap["created_at"] = person.createdAt;
        result.append(personMap);
    }

    return result;
}

QVariantList FacePipeline::getPersonPhotos(int personId)
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    // Get all faces for this person
    QVector<Face> faces = m_database->getFacesForPerson(personId);

    // Collect unique photo IDs
    QSet<int> photoIds;
    for (const Face &face : faces) {
        photoIds.insert(face.photoId);
    }

    // Get photo paths
    for (int photoId : photoIds) {
        Photo photo = m_database->getPhoto(photoId);
        if (!photo.filePath.isEmpty()) {
            QVariantMap photoMap;
            photoMap["photo_id"] = photo.id;
            photoMap["file_path"] = photo.filePath;
            photoMap["date_taken"] = photo.dateTaken;
            result.append(photoMap);
        }
    }

    return result;
}

bool FacePipeline::deletePerson(int personId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->deletePerson(personId);
}

bool FacePipeline::updatePersonName(int personId, const QString &name)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->updatePersonName(personId, name);
}

QVariantList FacePipeline::getUnmappedFaces()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    QVector<Face> faces = m_database->getUnmappedFaces();

    for (const Face &face : faces) {
        Photo photo = m_database->getPhoto(face.photoId);

        QVariantMap faceMap;
        faceMap["face_id"] = face.id;
        faceMap["photo_id"] = face.photoId;
        faceMap["photo_path"] = photo.filePath;
        faceMap["bbox_x"] = face.bbox.x();
        faceMap["bbox_y"] = face.bbox.y();
        faceMap["bbox_width"] = face.bbox.width();
        faceMap["bbox_height"] = face.bbox.height();
        faceMap["confidence"] = face.confidence;
        result.append(faceMap);
    }

    return result;
}
