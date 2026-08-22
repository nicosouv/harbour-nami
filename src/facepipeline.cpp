#include "facepipeline.h"
#include "exifreader.h"
#include "filehash.h"
#include "backupcrypto.h"
#include <QDebug>
#include "logging.h"
#include <QDir>
#include <QImageReader>
#include <QFile>
#include <QFileInfo>
#include <QtConcurrent>
#include <QSet>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <algorithm>

FacePipeline::FacePipeline(QObject *parent)
    : QObject(parent)
    , m_detector(nullptr)
    , m_recognizer(nullptr)
    , m_database(nullptr)
    , m_initialized(false)
    , m_processing(false)
    , m_cancelRequested(false)
    , m_needsRescan(false)
    , m_contactsEnabled(true)
    , m_currentScanIsForced(false)
    , m_totalPhotos(0)
    , m_processedPhotos(0)
    , m_personProtoCacheValid(false)
    , m_autoMatchThreshold(AUTO_MATCH_THRESHOLD)
{
    connect(&m_extractionWatcher, &QFutureWatcher<PhotoExtraction>::finished,
            this, &FacePipeline::onExtractionFinished);
    connect(&m_hashBackfillWatcher, &QFutureWatcher<QVector<QPair<int, QString>>>::finished,
            this, &FacePipeline::onHashBackfillFinished);
}

FacePipeline::~FacePipeline()
{
    // The worker uses m_detector/m_recognizer; let it finish first
    if (m_extractionWatcher.isRunning()) {
        m_extractionWatcher.waitForFinished();
    }
    if (m_hashBackfillWatcher.isRunning()) {
        m_hashBackfillWatcher.waitForFinished();
    }

    delete m_detector;
    delete m_recognizer;
    delete m_database;
}

bool FacePipeline::initialize(const QString &detectorModelPath,
                              const QString &recognizerModelPath,
                              const QString &databasePath)
{
    qCDebug(lcNami) << "Initializing face pipeline...";
    qCDebug(lcNami) << "  Detector model:" << detectorModelPath;
    qCDebug(lcNami) << "  Recognizer model:" << recognizerModelPath;
    qCDebug(lcNami) << "  Database:" << databasePath;

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

    // Privacy switch for contact reading (defaults to enabled)
    m_contactsEnabled = m_database->getSetting("contacts_enabled", "true") != "false";
    emit contactsEnabledChanged();

    // User-tuned matching threshold
    bool thresholdOk = false;
    float storedThreshold = m_database->getSetting("auto_match_threshold").toFloat(&thresholdOk);
    if (thresholdOk && storedThreshold >= 0.5f && storedThreshold <= 0.95f) {
        m_autoMatchThreshold = storedThreshold;
    }

    // Embeddings computed by older engine versions are incompatible with
    // the current matching (different alignment/preprocessing)
    int storedVersion = m_database->getSetting("embedding_version", "1").toInt();
    m_needsRescan = (storedVersion != EMBEDDING_VERSION);
    if (m_needsRescan) {
        qWarning() << "Stored embeddings use version" << storedVersion
                   << "but engine is version" << EMBEDDING_VERSION
                   << "- a full re-scan is required";
        emit needsRescanChanged();
    }

    m_initialized = true;
    emit initializedChanged();

    // One-time, silent maintenance: photos scanned before the file_hash
    // column existed need it backfilled so backups can find them by
    // content after a device migration
    backfillPhotoHashes();

    qCDebug(lcNami) << "Face pipeline initialized successfully";
    return true;
}

void FacePipeline::scanGallery(const QString &galleryPath, bool recursive, bool forceRescan)
{
    scanGalleries(QStringList{galleryPath}, recursive, forceRescan);
}

void FacePipeline::scanGalleries(const QStringList &galleryPaths, bool recursive, bool forceRescan)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return;
    }

    if (m_processing) {
        emit error("Already processing");
        return;
    }

    // Outdated embeddings: wipe face data so old and new embeddings are
    // never mixed, then re-process everything
    if (m_needsRescan) {
        qWarning() << "Clearing face data computed with an outdated engine version";
        m_database->clearFaceData();
        invalidatePersonPrototypes();
        forceRescan = true;
    }

    m_processing = true;
    m_cancelRequested = false;
    m_currentScanIsForced = forceRescan;
    emit processingChanged();

    qCDebug(lcNami) << "Scanning galleries:" << galleryPaths << "(recursive:" << recursive
             << "force:" << forceRescan << ")";

    // Find all image files across every folder, deduplicated (folders may
    // overlap, e.g. an SD card mounted under a scanned parent)
    QStringList allFiles;
    QSet<QString> seen;
    for (const QString &path : galleryPaths) {
        if (path.isEmpty()) {
            continue;
        }
        const QStringList files = findImageFiles(path, recursive);
        for (const QString &file : files) {
            if (!seen.contains(file)) {
                seen.insert(file);
                allFiles.append(file);
            }
        }
    }
    m_pendingFiles = allFiles;

    // Incremental scan: skip photos already processed
    if (!forceRescan) {
        QSet<QString> processedPaths = m_database->getProcessedFilePaths();
        if (!processedPaths.isEmpty()) {
            QStringList newFiles;
            for (const QString &file : m_pendingFiles) {
                if (!processedPaths.contains(file)) {
                    newFiles.append(file);
                }
            }
            qCDebug(lcNami) << "Incremental scan:" << (m_pendingFiles.size() - newFiles.size())
                     << "photos already processed," << newFiles.size() << "to process";
            m_pendingFiles = newFiles;
        }
    }

    m_totalPhotos = m_pendingFiles.size();
    m_processedPhotos = 0;
    m_totalFacesDetected = 0;

    emit totalPhotosChanged();
    emit scanStarted(m_totalPhotos);

    qCDebug(lcNami) << "Found" << m_totalPhotos << "image files";

    processNextPhoto();
}

void FacePipeline::processNextPhoto()
{
    if (m_cancelRequested) {
        finishScan(true);
        return;
    }

    if (m_pendingFiles.isEmpty()) {
        finishScan(false);
        return;
    }

    QString filePath = m_pendingFiles.takeFirst();
    emit scanProgress(m_processedPhotos + 1, m_totalPhotos, filePath);

    // Decode + detect + embed on a worker thread; the UI thread only does
    // the DB commit in onExtractionFinished
    m_extractionWatcher.setFuture(
        QtConcurrent::run(this, &FacePipeline::extractPhotoData, filePath));
}

void FacePipeline::onExtractionFinished()
{
    if (!m_processing) {
        return;
    }

    PhotoProcessingResult result = commitExtraction(m_extractionWatcher.result(),
                                                    m_currentScanIsForced);

    if (result.success) {
        m_totalFacesDetected += result.facesDetected;
    }

    emit photoProcessed(result);

    m_processedPhotos++;
    emit processedPhotosChanged();

    processNextPhoto();
}

void FacePipeline::finishScan(bool cancelled)
{
    m_processing = false;
    emit processingChanged();

    if (cancelled) {
        qCDebug(lcNami) << "Scan cancelled by user";
        emit scanFailed("Cancelled by user");
        return;
    }

    // Stored embeddings now match the engine
    m_database->setSetting("embedding_version", QString::number(EMBEDDING_VERSION));
    if (m_needsRescan) {
        m_needsRescan = false;
        emit needsRescanChanged();
    }

    emit scanCompleted(m_processedPhotos, m_totalFacesDetected);
    qCDebug(lcNami) << "Scan completed:" << m_processedPhotos << "photos," << m_totalFacesDetected << "faces";
}

PhotoProcessingResult FacePipeline::processPhoto(const QString &photoPath)
{
    if (!m_initialized) {
        return PhotoProcessingResult{-1, photoPath, 0, 0, false, "Pipeline not initialized"};
    }

    return commitExtraction(extractPhotoData(photoPath), false);
}

PhotoExtraction FacePipeline::extractPhotoData(const QString &photoPath)
{
    PhotoExtraction extraction;
    extraction.filePath = photoPath;
    extraction.loaded = false;
    extraction.width = 0;
    extraction.height = 0;
    extraction.hasLocation = false;
    extraction.latitude = 0.0;
    extraction.longitude = 0.0;

    qCDebug(lcNami) << "Processing photo:" << photoPath;

    extraction.fileHash = computeFileSha256(photoPath);

    QImage image = loadImage(photoPath);
    if (image.isNull()) {
        return extraction;
    }

    extraction.loaded = true;
    extraction.width = image.width();
    extraction.height = image.height();

    // Capture date from EXIF; mtime only as fallback (it resets on copy/sync)
    ExifReader::Metadata metadata = ExifReader::readMetadata(photoPath);
    extraction.dateTaken = metadata.dateTaken;
    if (!extraction.dateTaken.isValid()) {
        extraction.dateTaken = QFileInfo(photoPath).lastModified();
    }
    extraction.hasLocation = metadata.hasLocation;
    extraction.latitude = metadata.latitude;
    extraction.longitude = metadata.longitude;

    QVector<FaceDetection> detections = m_detector->detect(image);
    qCDebug(lcNami) << "Detected" << detections.size() << "faces";

    if (detections.isEmpty()) {
        return extraction;
    }

    // Convert once for all faces of this photo
    cv::Mat cvImage = m_detector->qImageToCvMat(image);

    for (const FaceDetection &detection : detections) {
        // Alignment to the 112x112 template happens inside the recognizer
        // (FaceRecognizerSF::alignCrop) using the detected landmarks
        FaceEmbedding embedding = m_recognizer->extractEmbedding(cvImage, detection);
        if (embedding.empty()) {
            qCDebug(lcNami) << "Failed to extract embedding for a face in" << photoPath;
            continue;
        }

        ExtractedFace face;
        face.bbox = detection.bbox;
        face.confidence = detection.confidence;
        face.embedding = embedding;
        extraction.faces.append(face);
    }

    return extraction;
}

PhotoProcessingResult FacePipeline::commitExtraction(const PhotoExtraction &extraction,
                                                     bool reprocess)
{
    PhotoProcessingResult result;
    result.photoId = -1;
    result.filePath = extraction.filePath;
    result.facesDetected = 0;
    result.facesMatched = 0;
    result.success = false;

    if (!extraction.loaded) {
        qCDebug(lcNami) << "Failed to load image:" << extraction.filePath;
        result.errorMessage = "Failed to load image";
        return result;
    }

    // All writes for one photo in a single transaction
    m_database->beginTransaction();

    int photoId = m_database->addPhoto(extraction.filePath, extraction.dateTaken,
                                       extraction.width, extraction.height,
                                       extraction.hasLocation, extraction.latitude,
                                       extraction.longitude, extraction.fileHash);
    if (photoId < 0) {
        m_database->rollbackTransaction();
        result.errorMessage = "Failed to add photo to database";
        return result;
    }

    result.photoId = photoId;

    // The photo may already have faces from a previous scan; remove them
    // before re-adding, otherwise every scan duplicates all faces and
    // identified people keep reappearing as unknown
    if (reprocess) {
        m_database->deleteFacesForPhoto(photoId);
    } else if (m_database->getPhoto(photoId).processedAt.isValid()) {
        qCDebug(lcNami) << "Photo already processed, skipping:" << extraction.filePath;
        m_database->rollbackTransaction();
        result.success = true;
        return result;
    }

    result.facesDetected = extraction.faces.size();

    for (const ExtractedFace &face : extraction.faces) {
        FaceMatch match = matchFaceToDatabase(face.embedding, m_autoMatchThreshold);

        if (match.personId >= 0) {
            result.facesMatched++;
            qCDebug(lcNami) << "Matched face to person" << match.personId
                            << "with similarity" << match.similarity;
        }

        int faceId = m_database->addFace(photoId, face.bbox, face.confidence,
                                         face.embedding, match.personId,
                                         match.similarity, false);
        if (faceId < 0) {
            qCDebug(lcNami) << "Failed to add face to database for" << extraction.filePath;
        }
    }

    m_database->markPhotoProcessed(photoId);
    m_database->commitTransaction();

    result.success = true;
    return result;
}

int FacePipeline::groupUnknownFaces(float similarityThreshold)
{
    if (!m_initialized) {
        emit error("Pipeline not initialized");
        return 0;
    }

    qCDebug(lcNami) << "Grouping unknown faces with threshold:" << similarityThreshold;

    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qCDebug(lcNami) << "Found" << unmappedFaces.size() << "unmapped faces";

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

    qCDebug(lcNami) << "Created" << groupsCreated << "groups";
    invalidatePersonPrototypes();
    return groupsCreated;
}

bool FacePipeline::identifyFace(int faceId, int personId, const QString &personName, const QString &contactId)
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
        // Optionally link the freshly created person to a device contact
        if (!contactId.isEmpty()) {
            m_database->setPersonContact(personId, contactId);
        }
    }

    // Update face mapping
    if (!m_database->updateFacePersonMapping(faceId, personId)) {
        return false;
    }

    // Mark as verified (manually identified by user)
    if (!m_database->updateFaceMetadata(faceId, 1.0f, true)) {
        return false;
    }

    // Verified faces define the person prototype. Only this person changed,
    // so patch the cache instead of dropping it: suggestPeopleForFace() runs
    // right after every identification and would pay a full rebuild each time
    // (a query per person) while reviewing a scan.
    QVector<FaceEmbedding> exemplars = m_database->getPersonExemplars(personId);
    refreshPersonExemplars(personId, exemplars);

    // Automatic re-matching: After identifying a face, re-match unmapped faces
    // against the updated person profile
    qCDebug(lcNami) << "Re-matching unmapped faces against person" << personId;

    if (exemplars.isEmpty()) {
        qCDebug(lcNami) << "No exemplars for person" << personId;
        return true;  // Still return success, re-matching is optional
    }

    // Get all unmapped faces (excludes ignored ones)
    QVector<Face> unmappedFaces = m_database->getUnmappedFaces();
    qCDebug(lcNami) << "Found" << unmappedFaces.size() << "unmapped faces to check";

    // Match each unmapped face against the person
    int autoMatched = 0;
    for (const Face &face : unmappedFaces) {
        // Respect user corrections: never reassign a rejected face
        if (m_database->hasNegativeMatch(face.id, personId)) {
            continue;
        }

        float similarity = 0.0f;
        for (const FaceEmbedding &exemplar : exemplars) {
            similarity = qMax(similarity,
                              FaceRecognizer::computeSimilarity(face.embedding, exemplar));
        }

        // If similarity is above threshold, auto-assign to this person
        if (similarity >= m_autoMatchThreshold) {
            qCDebug(lcNami) << "Auto-matching face" << face.id << "to person" << personId
                     << "with similarity" << similarity;

            // Update face mapping with similarity score and verified=false (auto-matched)
            if (m_database->updateFacePersonMapping(face.id, personId)) {
                m_database->updateFaceMetadata(face.id, similarity, false);
                autoMatched++;
            }
        }
    }

    qCDebug(lcNami) << "Auto-matched" << autoMatched << "faces to person" << personId;

    return true;
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
        qCDebug(lcNami) << "Failed to load image:" << filePath << "-" << reader.errorString();
    }

    return image;
}

FaceMatch FacePipeline::matchFaceToDatabase(const FaceEmbedding &embedding, float threshold)
{
    FaceMatch bestMatch{-1, 0.0f};

    // A person is represented by several exemplar embeddings (different
    // looks: glasses, age, lighting); the person's score is the best
    // similarity over their exemplars
    for (const auto &entry : personExemplars()) {
        for (const FaceEmbedding &exemplar : entry.second) {
            float similarity = FaceRecognizer::computeSimilarity(embedding, exemplar);
            if (similarity > bestMatch.similarity) {
                bestMatch.personId = entry.first;
                bestMatch.similarity = similarity;
            }
        }
    }

    if (bestMatch.similarity < threshold) {
        return FaceMatch{-1, bestMatch.similarity};
    }

    return bestMatch;
}

const QVector<QPair<int, QVector<FaceEmbedding>>> &FacePipeline::personExemplars()
{
    // Exemplars only change when verified faces or people change
    // (identify, remove, merge, delete); unverified auto-assigns during a
    // scan don't affect them, so the cache stays valid for a whole scan
    if (!m_personProtoCacheValid) {
        m_personExemplarCache.clear();
        for (const Person &person : m_database->getAllPeople()) {
            QVector<FaceEmbedding> exemplars = m_database->getPersonExemplars(person.id);
            if (!exemplars.isEmpty()) {
                m_personExemplarCache.append(qMakePair(person.id, exemplars));
            }
        }
        m_personProtoCacheValid = true;
        qCDebug(lcNami) << "Person exemplar cache rebuilt:" << m_personExemplarCache.size() << "people";
    }

    return m_personExemplarCache;
}

void FacePipeline::invalidatePersonPrototypes()
{
    m_personProtoCacheValid = false;
}

void FacePipeline::refreshPersonExemplars(int personId, const QVector<FaceEmbedding> &exemplars)
{
    // Nothing to patch: the whole cache is rebuilt on next use anyway
    if (!m_personProtoCacheValid) {
        return;
    }

    for (int i = 0; i < m_personExemplarCache.size(); i++) {
        if (m_personExemplarCache[i].first == personId) {
            if (exemplars.isEmpty()) {
                m_personExemplarCache.remove(i);
            } else {
                m_personExemplarCache[i].second = exemplars;
            }
            return;
        }
    }

    // A person only enters the cache once they have at least one face
    if (!exemplars.isEmpty()) {
        m_personExemplarCache.append(qMakePair(personId, exemplars));
    }
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
        personMap["contact_id"] = person.contactId;
        // Unix epoch seconds, 0 when none of their photos has a usable date;
        // lets the people list sort by "most recently photographed"
        personMap["last_photo"] = person.lastPhoto.isValid()
            ? person.lastPhoto.toMSecsSinceEpoch() / 1000 : 0;
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

    // Group faces by photo ID to get the best match per photo
    QMap<int, Face> bestFacePerPhoto;
    for (const Face &face : faces) {
        if (!bestFacePerPhoto.contains(face.photoId) ||
            face.similarityScore > bestFacePerPhoto[face.photoId].similarityScore) {
            bestFacePerPhoto[face.photoId] = face;
        }
    }

    // Get photo paths with face metadata
    for (const Face &face : bestFacePerPhoto.values()) {
        Photo photo = m_database->getPhoto(face.photoId);
        if (!photo.filePath.isEmpty()) {
            QVariantMap photoMap;
            photoMap["photo_id"] = photo.id;
            photoMap["face_id"] = face.id;
            photoMap["file_path"] = photo.filePath;
            photoMap["date_taken"] = photo.dateTaken;
            // Unix epoch seconds; Events/Memories group photos by this
            photoMap["timestamp"] = photo.dateTaken.isValid()
                ? photo.dateTaken.toMSecsSinceEpoch() / 1000 : 0;
            photoMap["similarity_score"] = face.similarityScore;
            photoMap["verified"] = face.verified;
            photoMap["rotation"] = photo.rotation;
            // Already EXIF-corrected (the scanner reads them off an
            // auto-transformed image), so an aspect-ratio layout can use them
            // directly. 0 when the row predates them being recorded.
            photoMap["width"] = photo.width;
            photoMap["height"] = photo.height;
            photoMap["has_location"] = photo.hasLocation;
            photoMap["latitude"] = photo.latitude;
            photoMap["longitude"] = photo.longitude;
            photoMap["bbox_x"] = face.bbox.x();
            photoMap["bbox_y"] = face.bbox.y();
            photoMap["bbox_width"] = face.bbox.width();
            photoMap["bbox_height"] = face.bbox.height();
            result.append(photoMap);
        }
    }

    // QMap iterates by photo id, i.e. scan order, which looks random to the
    // user. Sort newest first; photos without EXIF date (timestamp 0) sink to
    // the bottom rather than pretending to be from 1970.
    std::sort(result.begin(), result.end(),
              [](const QVariant &a, const QVariant &b) {
                  const qint64 ta = a.toMap().value("timestamp").toLongLong();
                  const qint64 tb = b.toMap().value("timestamp").toLongLong();
                  if (ta != tb) {
                      return ta > tb;
                  }
                  // Stable tie-break so the order never shuffles between calls
                  return a.toMap().value("photo_id").toInt()
                       > b.toMap().value("photo_id").toInt();
              });

    return result;
}

QVariantList FacePipeline::getAllPhotos()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    for (const Photo &photo : m_database->getAllPhotos()) {
        QVariantMap photoMap;
        photoMap["photo_id"] = photo.id;
        photoMap["file_path"] = photo.filePath;
        photoMap["date_taken"] = photo.dateTaken;
        photoMap["timestamp"] = photo.dateTaken.isValid()
            ? photo.dateTaken.toMSecsSinceEpoch() / 1000 : 0;
        photoMap["rotation"] = photo.rotation;
        // EXIF-corrected already, so an aspect-ratio layout can use them
        photoMap["width"] = photo.width;
        photoMap["height"] = photo.height;
        photoMap["has_location"] = photo.hasLocation;
        photoMap["latitude"] = photo.latitude;
        photoMap["longitude"] = photo.longitude;
        result.append(photoMap);
    }

    return result;
}

QVariantMap FacePipeline::getPersonBestFace(int personId)
{
    QVariantMap result;

    if (!m_initialized || !m_database) {
        return result;
    }

    Face face = m_database->getBestFaceForPerson(personId);
    if (face.id < 0) {
        return result;
    }

    Photo photo = m_database->getPhoto(face.photoId);
    if (photo.filePath.isEmpty()) {
        return result;
    }

    result["face_id"] = face.id;
    result["photo_path"] = photo.filePath;
    result["bbox_x"] = face.bbox.x();
    result["bbox_y"] = face.bbox.y();
    result["bbox_width"] = face.bbox.width();
    result["bbox_height"] = face.bbox.height();

    return result;
}

bool FacePipeline::deletePerson(int personId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    invalidatePersonPrototypes();
    return m_database->deletePerson(personId);
}

bool FacePipeline::updatePersonName(int personId, const QString &name)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->updatePersonName(personId, name);
}

bool FacePipeline::linkPersonToContact(int personId, const QString &contactId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->setPersonContact(personId, contactId);
}

QString FacePipeline::personContactId(int personId)
{
    if (!m_initialized || !m_database) {
        return QString();
    }

    return m_database->getPerson(personId).contactId;
}

int FacePipeline::photoRotation(const QString &photoPath)
{
    if (!m_initialized || !m_database) {
        return 0;
    }

    return m_database->photoRotation(photoPath);
}

bool FacePipeline::setPhotoRotation(const QString &photoPath, int rotation)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->setPhotoRotation(photoPath, rotation);
}

qint64 FacePipeline::fileSize(const QString &photoPath)
{
    // Deliberately not going through photoDetails(): the selection bar calls
    // this on every tap, and a stat() is all it needs.
    const QFileInfo info(photoPath);
    return info.exists() ? info.size() : 0;
}

QVariantMap FacePipeline::photoDetails(const QString &photoPath)
{
    QVariantMap details;

    const QFileInfo info(photoPath);
    details["file_path"] = photoPath;
    details["file_name"] = info.fileName();
    details["folder"] = info.absolutePath();
    details["exists"] = info.exists();
    details["file_size"] = info.exists() ? info.size() : 0;

    // Defaults so QML never has to null-check
    details["in_library"] = false;
    details["width"] = 0;
    details["height"] = 0;
    details["date_taken"] = QDateTime();
    details["timestamp"] = 0;
    details["has_location"] = false;
    details["latitude"] = 0.0;
    details["longitude"] = 0.0;
    details["rotation"] = 0;

    if (m_initialized && m_database) {
        const Photo photo = m_database->getPhotoByPath(photoPath);
        if (photo.id >= 0) {
            details["in_library"] = true;
            details["width"] = photo.width;
            details["height"] = photo.height;
            details["date_taken"] = photo.dateTaken;
            details["timestamp"] = photo.dateTaken.isValid()
                ? photo.dateTaken.toMSecsSinceEpoch() / 1000 : 0;
            details["has_location"] = photo.hasLocation;
            details["latitude"] = photo.latitude;
            details["longitude"] = photo.longitude;
            details["rotation"] = photo.rotation;
        }
    }

    // Dimensions are missing for photos that were never scanned, and for older
    // rows written before width/height were recorded. Read the header directly
    // in that case - QImageReader does not decode the pixels.
    if (details["width"].toInt() <= 0 || details["height"].toInt() <= 0) {
        if (info.exists()) {
            QImageReader reader(photoPath);
            reader.setAutoTransform(true);
            const QSize size = reader.size();
            if (size.isValid()) {
                details["width"] = size.width();
                details["height"] = size.height();
            }
        }
    }

    // Same for the capture date and GPS: read EXIF directly, then fall back to
    // the file's own timestamp, so the panel is not blank for unscanned photos.
    const bool needsDate = !details["date_taken"].toDateTime().isValid();
    const bool needsLocation = !details["has_location"].toBool();
    if ((needsDate || needsLocation) && info.exists()) {
        const ExifReader::Metadata meta = ExifReader::readMetadata(photoPath);

        if (needsDate) {
            const QDateTime fallback = meta.dateTaken.isValid()
                ? meta.dateTaken : info.lastModified();
            if (fallback.isValid()) {
                details["date_taken"] = fallback;
                details["timestamp"] = fallback.toMSecsSinceEpoch() / 1000;
            }
        }

        if (needsLocation && meta.hasLocation) {
            details["has_location"] = true;
            details["latitude"] = meta.latitude;
            details["longitude"] = meta.longitude;
        }
    }

    return details;
}

void FacePipeline::setContactsEnabled(bool enabled)
{
    if (m_contactsEnabled == enabled) {
        return;
    }

    m_contactsEnabled = enabled;
    if (m_database) {
        m_database->setSetting("contacts_enabled", enabled ? "true" : "false");
    }
    emit contactsEnabledChanged();
}

bool FacePipeline::mergePersons(int fromPersonId, int intoPersonId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    if (fromPersonId == intoPersonId || fromPersonId < 0 || intoPersonId < 0) {
        return false;
    }

    invalidatePersonPrototypes();
    return m_database->mergePersons(fromPersonId, intoPersonId);
}

bool FacePipeline::removeFaceFromPerson(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    // Remember the rejection, otherwise the next auto-match run reassigns
    // the face to the same person and the correction is lost
    Face face = m_database->getFace(faceId);
    if (face.personId >= 0) {
        m_database->addNegativeMatch(faceId, face.personId);
    }

    invalidatePersonPrototypes();
    return m_database->removeFaceFromPerson(faceId);
}

bool FacePipeline::removePersonFromPhoto(int personId, int photoId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    invalidatePersonPrototypes();
    return m_database->removePersonFromPhoto(personId, photoId);
}

bool FacePipeline::ignoreFace(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    return m_database->setFaceIgnored(faceId, true);
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

QVariantList FacePipeline::suggestPeopleForFace(int faceId, int maxCount)
{
    QVariantList result;

    if (!m_initialized || !m_database || faceId < 0 || maxCount <= 0) {
        return result;
    }

    Face face = m_database->getFace(faceId);
    if (face.id < 0 || face.embedding.empty()) {
        return result;
    }

    // Someone already tagged on another face of this photo is almost never
    // this face too, and suggesting them invites a wrong tap
    QSet<int> alreadyInPhoto;
    for (const Face &other : m_database->getFacesForPhoto(face.photoId)) {
        if (other.id != face.id && other.personId > 0) {
            alreadyInPhoto.insert(other.personId);
        }
    }

    QSet<int> rejected = m_database->getNegativeMatches(faceId);

    Photo photo = m_database->getPhoto(face.photoId);
    QSet<int> sameDay = m_database->getPeopleAroundDate(photo.dateTaken);

    struct Candidate {
        int personId;
        float score;   // facial similarity, what gets shown
        float rank;    // score plus context, what sorts
        bool sameDay;
    };

    std::vector<Candidate> candidates;
    for (const auto &entry : personExemplars()) {
        int personId = entry.first;
        if (alreadyInPhoto.contains(personId) || rejected.contains(personId)) {
            continue;
        }

        float best = 0.0f;
        for (const FaceEmbedding &exemplar : entry.second) {
            best = qMax(best, FaceRecognizer::computeSimilarity(face.embedding, exemplar));
        }

        if (best < SUGGEST_THRESHOLD) {
            continue;
        }

        bool nearby = sameDay.contains(personId);
        candidates.push_back(Candidate{personId, best,
                                       best + (nearby ? SAME_DAY_BONUS : 0.0f), nearby});
    }

    // Stable so people the exemplar cache lists first keep their order on ties
    std::stable_sort(candidates.begin(), candidates.end(),
                     [](const Candidate &a, const Candidate &b) { return a.rank > b.rank; });

    for (const Candidate &c : candidates) {
        if (result.size() >= maxCount) {
            break;
        }
        Person person = m_database->getPerson(c.personId);
        if (person.id < 0) {
            continue;
        }
        QVariantMap map;
        map["person_id"] = person.id;
        map["name"] = person.name;
        map["score"] = c.score;
        map["strong"] = c.score >= GROUPING_THRESHOLD;
        map["same_day"] = c.sameDay;
        result.append(map);
    }

    return result;
}

QVariantMap FacePipeline::getStatistics()
{
    QVariantMap stats;

    if (!m_initialized || !m_database) {
        stats["total_photos"] = 0;
        stats["total_faces"] = 0;
        stats["total_people"] = 0;
        stats["db_size_bytes"] = 0;
        return stats;
    }

    return m_database->getStatistics();
}

bool FacePipeline::deleteAllData()
{
    if (!m_initialized || !m_database) {
        return false;
    }

    invalidatePersonPrototypes();

    // Face crops cached by the image provider are derived biometric data
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir(cacheDir + "/faces").removeRecursively();

    return m_database->deleteAllData();
}

QString FacePipeline::getSetting(const QString &key, const QString &defaultValue)
{
    if (!m_initialized || !m_database) {
        return defaultValue;
    }

    return m_database->getSetting(key, defaultValue);
}

bool FacePipeline::setSetting(const QString &key, const QString &value)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    if (key == QLatin1String("auto_match_threshold")) {
        bool ok = false;
        float threshold = value.toFloat(&ok);
        if (ok && threshold >= 0.5f && threshold <= 0.95f) {
            m_autoMatchThreshold = threshold;
        }
    }

    return m_database->setSetting(key, value);
}

bool FacePipeline::confirmFace(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    const Face face = m_database->getFace(faceId);
    if (face.id < 0 || face.verified) {
        return false;
    }

    if (!m_database->updateFaceMetadata(face.id, face.similarityScore, true)) {
        return false;
    }

    // Verified faces define the person prototype
    invalidatePersonPrototypes();
    return true;
}

bool FacePipeline::unconfirmFace(int faceId)
{
    if (!m_initialized || !m_database) {
        return false;
    }

    const Face face = m_database->getFace(faceId);
    if (face.id < 0 || !face.verified) {
        return false;
    }

    // The face stays attached to the person: this only takes back the user's
    // confirmation, which is the way out of a mistaken "Confirm all matches".
    // Removing the person from the photo is a different action.
    if (!m_database->updateFaceMetadata(face.id, face.similarityScore, false)) {
        return false;
    }

    invalidatePersonPrototypes();
    return true;
}

int FacePipeline::confirmAllFaces(int personId)
{
    if (!m_initialized || !m_database) {
        return 0;
    }

    int confirmed = 0;
    for (const Face &face : m_database->getFacesForPerson(personId)) {
        if (!face.verified) {
            if (m_database->updateFaceMetadata(face.id, face.similarityScore, true)) {
                confirmed++;
            }
        }
    }

    if (confirmed > 0) {
        // Verified faces define the person prototype
        invalidatePersonPrototypes();
    }

    return confirmed;
}

QVariantList FacePipeline::getTrips()
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    for (const Trip &trip : m_database->getAllTrips()) {
        QVariantMap tripMap;
        tripMap["trip_id"] = trip.id;
        tripMap["name"] = trip.name;
        tripMap["date_keys"] = trip.dateKeys;
        result.append(tripMap);
    }

    return result;
}

int FacePipeline::createTrip(const QString &name, const QStringList &dateKeys)
{
    if (!m_initialized || !m_database) {
        return -1;
    }
    return m_database->createTrip(name, dateKeys);
}

bool FacePipeline::renameTrip(int tripId, const QString &name)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->renameTrip(tripId, name);
}

bool FacePipeline::deleteTrip(int tripId)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->deleteTrip(tripId);
}

bool FacePipeline::mergeTrips(int fromTripId, int intoTripId)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->mergeTrips(fromTripId, intoTripId);
}

bool FacePipeline::addDatesToTrip(int tripId, const QStringList &dateKeys)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->addDatesToTrip(tripId, dateKeys);
}

bool FacePipeline::hideEvent(const QString &eventKey)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->hideEvent(eventKey);
}

bool FacePipeline::unhideEvent(const QString &eventKey)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->unhideEvent(eventKey);
}

QStringList FacePipeline::getHiddenEvents()
{
    if (!m_initialized || !m_database) {
        return QStringList();
    }
    return m_database->getHiddenEvents();
}

bool FacePipeline::setEventCover(const QString &eventKey, const QString &photoPath)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->setEventCover(eventKey, photoPath);
}

bool FacePipeline::clearEventCover(const QString &eventKey)
{
    if (!m_initialized || !m_database) {
        return false;
    }
    return m_database->clearEventCover(eventKey);
}

QVariantMap FacePipeline::getEventCovers()
{
    if (!m_initialized || !m_database) {
        return QVariantMap();
    }
    return m_database->getEventCovers();
}

QVariantList FacePipeline::getCoverPhotos(int limit)
{
    QVariantList result;

    if (!m_initialized || !m_database) {
        return result;
    }

    for (const Photo &photo : m_database->getRecentPhotos(limit)) {
        QVariantMap photoMap;
        photoMap["file_path"] = photo.filePath;
        photoMap["timestamp"] = photo.dateTaken.isValid()
            ? photo.dateTaken.toMSecsSinceEpoch() / 1000 : 0;
        photoMap["rotation"] = photo.rotation;
        photoMap["has_location"] = photo.hasLocation;
        photoMap["latitude"] = photo.latitude;
        photoMap["longitude"] = photo.longitude;
        result.append(photoMap);
    }

    return result;
}

QString FacePipeline::exportData()
{
    if (!m_initialized || !m_database) {
        return QString();
    }

    QJsonObject root;
    root["app"] = "harbour-nami";
    root["exported_at"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    root["statistics"] = QJsonObject::fromVariantMap(m_database->getStatistics());

    // Raw embeddings are deliberately not exported: they are biometric
    // templates with no human-readable value
    QJsonArray peopleArray;
    for (const Person &person : m_database->getAllPeople()) {
        QJsonObject personObj;
        personObj["id"] = person.id;
        personObj["name"] = person.name;
        personObj["created_at"] = person.createdAt.toString(Qt::ISODate);

        QJsonArray facesArray;
        for (const Face &face : m_database->getFacesForPerson(person.id)) {
            QJsonObject faceObj;
            faceObj["photo_path"] = m_database->getPhoto(face.photoId).filePath;
            faceObj["confidence"] = face.confidence;
            faceObj["similarity_score"] = face.similarityScore;
            faceObj["verified"] = face.verified;
            faceObj["detected_at"] = face.detectedAt.toString(Qt::ISODate);
            facesArray.append(faceObj);
        }
        personObj["faces"] = facesArray;

        peopleArray.append(personObj);
    }
    root["people"] = peopleArray;

    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QString filePath = dir + "/nami-export-"
        + QDateTime::currentDateTime().toString("yyyyMMdd-hhmmss") + ".json";

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit error("Failed to write export file: " + filePath);
        return QString();
    }

    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    file.close();

    // Contains names and photo paths
    QFile::setPermissions(filePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    qCDebug(lcNami) << "Data exported to" << filePath;
    return filePath;
}

QString FacePipeline::exportBackupData(const QString &passphrase)
{
    if (!m_initialized || !m_database || passphrase.isEmpty()) {
        return QString();
    }

    QJsonObject root = m_database->exportBackup();
    // Lets importBackupData() know whether these embeddings are compatible
    // with the engine that will read them back
    root["embedding_version"] = EMBEDDING_VERSION;

    int totalPhotos = root["photos"].toArray().size();
    int totalPeople = root["people"].toArray().size();
    QString exportedAt = root["exported_at"].toString();

    BackupCrypto::EncryptedPayload payload;
    if (!BackupCrypto::encrypt(QJsonDocument(root).toJson(QJsonDocument::Compact),
                               passphrase, payload)) {
        emit error("Failed to encrypt backup");
        return QString();
    }

    // Everything below is unencrypted: enough to list and pick a backup
    // (date, rough size) without needing the passphrase, but nothing
    // sensitive (no names, paths or embeddings - those are all inside
    // "ciphertext")
    QJsonObject envelope;
    envelope["app"] = "harbour-nami";
    envelope["backup_format"] = "encrypted-v1";
    envelope["exported_at"] = exportedAt;
    envelope["total_photos"] = totalPhotos;
    envelope["total_people"] = totalPeople;
    envelope["kdf"] = "pbkdf2-sha256";
    envelope["iterations"] = payload.iterations;
    envelope["salt"] = QString::fromLatin1(payload.salt.toBase64());
    envelope["iv"] = QString::fromLatin1(payload.iv.toBase64());
    envelope["tag"] = QString::fromLatin1(payload.tag.toBase64());
    envelope["ciphertext"] = QString::fromLatin1(payload.ciphertext.toBase64());

    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QString filePath = dir + "/nami-backup-"
        + QDateTime::currentDateTime().toString("yyyyMMdd-hhmmss") + ".json";

    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        emit error("Failed to write backup file: " + filePath);
        return QString();
    }

    file.write(QJsonDocument(envelope).toJson(QJsonDocument::Indented));
    file.close();

    QFile::setPermissions(filePath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    m_database->setSetting("last_backup_at", QDateTime::currentDateTime().toString(Qt::ISODate));

    qCDebug(lcNami) << "Encrypted backup written to" << filePath;
    return filePath;
}

QVariantList FacePipeline::listBackupFiles(const QString &folderPath)
{
    QVariantList result;
    QDir dir(folderPath);
    if (!dir.exists()) {
        return result;
    }

    // Sort explicitly by modification time (newest first) rather than
    // relying on QDir's platform-dependent default tie-breaking for QDir::Time
    QFileInfoList files = dir.entryInfoList(
        QStringList{"nami-backup-*.json"}, QDir::Files);
    std::sort(files.begin(), files.end(), [](const QFileInfo &a, const QFileInfo &b) {
        return a.lastModified() > b.lastModified();
    });

    for (const QFileInfo &info : files) {
        QString path = info.absoluteFilePath();
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            continue;
        }
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        file.close();
        if (!doc.isObject()) {
            continue;
        }

        QJsonObject root = doc.object();
        QVariantMap entry;
        entry["file_path"] = path;
        entry["exported_at"] = root["exported_at"].toString();
        if (root.contains("ciphertext")) {
            // Encrypted backup: counts are kept in the clear for the picker
            entry["total_photos"] = root["total_photos"].toInt();
            entry["total_people"] = root["total_people"].toInt();
        } else {
            // Legacy plaintext backup (written before encryption was added)
            entry["total_photos"] = root["photos"].toArray().size();
            entry["total_people"] = root["people"].toArray().size();
        }
        result.append(entry);
    }

    return result;
}

QVariantMap FacePipeline::importBackupData(const QString &filePath, const QString &passphrase)
{
    QVariantMap result;
    if (!m_initialized || !m_database) {
        return result;
    }

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        emit error("Failed to read backup file: " + filePath);
        return result;
    }

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) {
        emit error("Invalid backup file: " + filePath);
        return result;
    }

    QJsonObject envelope = doc.object();
    QJsonObject root;

    if (envelope.contains("ciphertext")) {
        if (passphrase.isEmpty()) {
            emit error("A passphrase is required to restore this backup");
            return result;
        }

        BackupCrypto::EncryptedPayload payload;
        payload.iterations = envelope["iterations"].toInt();
        payload.salt = QByteArray::fromBase64(envelope["salt"].toString().toLatin1());
        payload.iv = QByteArray::fromBase64(envelope["iv"].toString().toLatin1());
        payload.tag = QByteArray::fromBase64(envelope["tag"].toString().toLatin1());
        payload.ciphertext = QByteArray::fromBase64(envelope["ciphertext"].toString().toLatin1());

        QByteArray plaintext = BackupCrypto::decrypt(payload, passphrase);
        if (plaintext.isNull()) {
            emit error("Wrong passphrase or corrupted backup file");
            return result;
        }

        QJsonDocument innerDoc = QJsonDocument::fromJson(plaintext);
        if (!innerDoc.isObject()) {
            emit error("Corrupted backup file");
            return result;
        }
        root = innerDoc.object();
    } else {
        // Legacy plaintext backup (written before encryption was added)
        root = envelope;
    }

    int backupEmbeddingVersion = root["embedding_version"].toInt(-1);

    FaceDatabase::ImportStats stats = m_database->importBackup(root);

    // Same engine version as this backup: the restored embeddings are
    // usable as-is, so skip the "outdated embeddings" forced rescan that
    // would otherwise wipe what was just imported
    if (backupEmbeddingVersion == EMBEDDING_VERSION) {
        m_database->setSetting("embedding_version", QString::number(EMBEDDING_VERSION));
        if (m_needsRescan) {
            m_needsRescan = false;
            emit needsRescanChanged();
        }
    }

    invalidatePersonPrototypes();

    result["photos_imported"] = stats.photosImported;
    result["photos_relinked"] = stats.photosRelinked;
    result["photos_skipped"] = stats.photosSkipped;
    result["people_imported"] = stats.peopleImported;
    result["faces_imported"] = stats.facesImported;
    result["trips_imported"] = stats.tripsImported;

    qCDebug(lcNami) << "Backup restored from" << filePath << ":"
             << stats.photosImported << "photos," << stats.photosRelinked << "relinked by hash,"
             << stats.facesImported << "faces," << stats.peopleImported << "people,"
             << stats.tripsImported << "trips," << stats.photosSkipped << "photos skipped (missing on this device)";

    return result;
}

void FacePipeline::backfillPhotoHashes()
{
    if (!m_initialized || !m_database || m_hashBackfillWatcher.isRunning()) {
        return;
    }

    QVector<QPair<int, QString>> missing = m_database->getPhotosMissingHash();
    if (missing.isEmpty()) {
        emit hashBackfillCompleted(0);
        return;
    }

    qCDebug(lcNami) << "Backfilling file hash for" << missing.size() << "photos";

    m_hashBackfillWatcher.setFuture(QtConcurrent::run([missing]() {
        QVector<QPair<int, QString>> results;
        for (const auto &entry : missing) {
            QString hash = computeFileSha256(entry.second);
            if (!hash.isEmpty()) {
                results.append(qMakePair(entry.first, hash));
            }
        }
        return results;
    }));
}

void FacePipeline::onHashBackfillFinished()
{
    QVector<QPair<int, QString>> results = m_hashBackfillWatcher.result();

    if (!results.isEmpty()) {
        m_database->beginTransaction();
        for (const auto &entry : results) {
            m_database->setPhotoHash(entry.first, entry.second);
        }
        m_database->commitTransaction();
    }

    qCDebug(lcNami) << "Hash backfill applied to" << results.size() << "photos";
    emit hashBackfillCompleted(results.size());
}
