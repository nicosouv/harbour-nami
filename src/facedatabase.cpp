#include "facedatabase.h"
#include <QDebug>
#include "logging.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QVariant>
#include <QDataStream>
#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHash>

FaceDatabase::FaceDatabase(QObject *parent)
    : QObject(parent)
    , m_isOpen(false)
{
}

FaceDatabase::~FaceDatabase()
{
    close();
}

bool FaceDatabase::open(const QString &dbPath)
{
    if (m_isOpen) {
        qWarning() << "Database already open";
        return true;
    }

    m_dbPath = dbPath;
    m_db = QSqlDatabase::addDatabase("QSQLITE");
    m_db.setDatabaseName(dbPath);

    if (!m_db.open()) {
        emit error("Failed to open database: " + m_db.lastError().text());
        return false;
    }

    m_isOpen = true;
    qCDebug(lcNami) << "Database opened:" << dbPath;

    // Owner-only: the database holds biometric data (face embeddings)
    QFile::setPermissions(dbPath, QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    // FK constraints are declared in the schema but SQLite only enforces
    // them with this pragma; WAL avoids blocking readers during scans
    QSqlQuery pragma(m_db);
    pragma.exec("PRAGMA foreign_keys = ON");
    pragma.exec("PRAGMA journal_mode = WAL");
    pragma.exec("PRAGMA synchronous = NORMAL");

    // WAL side files inherit creation-time permissions, tighten them too
    QFile::setPermissions(dbPath + "-wal", QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    QFile::setPermissions(dbPath + "-shm", QFileDevice::ReadOwner | QFileDevice::WriteOwner);

    return initializeSchema();
}

void FaceDatabase::close()
{
    if (m_isOpen) {
        m_db.close();
        m_isOpen = false;
        qCDebug(lcNami) << "Database closed";
    }
}

bool FaceDatabase::initializeSchema()
{
    QSqlQuery query(m_db);

    // Photos table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS photos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            date_taken TEXT,
            width INTEGER,
            height INTEGER,
            processed_at TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )")) {
        emit error("Failed to create photos table: " + query.lastError().text());
        return false;
    }

    // Faces table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS faces (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            photo_id INTEGER NOT NULL,
            bbox_x REAL NOT NULL,
            bbox_y REAL NOT NULL,
            bbox_width REAL NOT NULL,
            bbox_height REAL NOT NULL,
            confidence REAL NOT NULL,
            embedding BLOB NOT NULL,
            person_id INTEGER DEFAULT -1,
            similarity_score REAL DEFAULT 0.0,
            verified INTEGER DEFAULT 0,
            ignored INTEGER DEFAULT 0,
            detected_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (photo_id) REFERENCES photos(id) ON DELETE CASCADE
        )
    )")) {
        emit error("Failed to create faces table: " + query.lastError().text());
        return false;
    }

    // Migrate existing database if needed (add new columns if they don't exist)
    query.exec("ALTER TABLE faces ADD COLUMN similarity_score REAL DEFAULT 0.0");
    query.exec("ALTER TABLE faces ADD COLUMN verified INTEGER DEFAULT 0");
    query.exec("ALTER TABLE faces ADD COLUMN ignored INTEGER DEFAULT 0");
    query.exec("ALTER TABLE photos ADD COLUMN rotation INTEGER DEFAULT 0");
    // NULL means "no GPS data in EXIF", not "0,0"
    query.exec("ALTER TABLE photos ADD COLUMN latitude REAL");
    query.exec("ALTER TABLE photos ADD COLUMN longitude REAL");
    // Content hash: finds a photo again after a device migration moved it
    // to a different path (backfilled lazily for photos scanned before
    // this column existed)
    query.exec("ALTER TABLE photos ADD COLUMN file_hash TEXT");

    // Rejections: "this face is NOT this person", so auto-matching never
    // reassigns a face the user explicitly removed from a person
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS negative_matches (
            face_id INTEGER NOT NULL,
            person_id INTEGER NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (face_id, person_id)
        )
    )")) {
        emit error("Failed to create negative_matches table: " + query.lastError().text());
        return false;
    }

    // People table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS people (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            contact_id TEXT
        )
    )")) {
        emit error("Failed to create people table: " + query.lastError().text());
        return false;
    }

    // Migrate existing database: link to device contacts
    query.exec("ALTER TABLE people ADD COLUMN contact_id TEXT");

    // Settings table
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    )")) {
        emit error("Failed to create settings table: " + query.lastError().text());
        return false;
    }

    // Trips: user-named groups of day-events (e.g. a holiday spanning
    // several non-contiguous dates)
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS trips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    )")) {
        emit error("Failed to create trips table: " + query.lastError().text());
        return false;
    }

    // date_key is the primary key: a date belongs to at most one trip
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS trip_dates (
            date_key TEXT PRIMARY KEY,
            trip_id INTEGER NOT NULL,
            FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE
        )
    )")) {
        emit error("Failed to create trip_dates table: " + query.lastError().text());
        return false;
    }

    // User-chosen cover photo for a day ("day:yyyy-MM-dd") or trip
    // ("trip:<id>") event; falls back to an automatic choice when absent
    if (!query.exec(R"(
        CREATE TABLE IF NOT EXISTS event_covers (
            event_key TEXT PRIMARY KEY,
            photo_path TEXT NOT NULL
        )
    )")) {
        emit error("Failed to create event_covers table: " + query.lastError().text());
        return false;
    }

    // Create indexes
    query.exec("CREATE INDEX IF NOT EXISTS idx_faces_photo ON faces(photo_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_faces_person ON faces(person_id)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_photos_path ON photos(file_path)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_photos_hash ON photos(file_hash)");
    query.exec("CREATE INDEX IF NOT EXISTS idx_trip_dates_trip ON trip_dates(trip_id)");

    qCDebug(lcNami) << "Database schema initialized";
    return true;
}

// === Transactions ===

bool FaceDatabase::beginTransaction()
{
    return m_db.transaction();
}

bool FaceDatabase::commitTransaction()
{
    return m_db.commit();
}

bool FaceDatabase::rollbackTransaction()
{
    return m_db.rollback();
}

// === Photo operations ===

int FaceDatabase::addPhoto(const QString &filePath, const QDateTime &dateTaken,
                           int width, int height, bool hasLocation,
                           double latitude, double longitude,
                           const QString &fileHash)
{
    qCDebug(lcNami) << "  → Attempting to insert photo:" << filePath;

    // Check if photo already exists
    QSqlQuery checkQuery(m_db);
    checkQuery.prepare("SELECT id FROM photos WHERE file_path = :file_path");
    checkQuery.bindValue(":file_path", filePath);

    if (checkQuery.exec() && checkQuery.next()) {
        int existingId = checkQuery.value(0).toInt();
        qCDebug(lcNami) << "  ℹ Photo already exists in DB with ID:" << existingId;
        if (!fileHash.isEmpty()) {
            setPhotoHash(existingId, fileHash);  // no-op if already set
        }
        return existingId;  // Return existing photo ID
    }

    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO photos (file_path, date_taken, width, height, latitude, longitude, file_hash)
        VALUES (:file_path, :date_taken, :width, :height, :latitude, :longitude, :file_hash)
    )");
    query.bindValue(":file_path", filePath);
    query.bindValue(":date_taken", dateTaken.toString(Qt::ISODate));
    query.bindValue(":width", width);
    query.bindValue(":height", height);
    query.bindValue(":file_hash", fileHash.isEmpty() ? QVariant(QVariant::String) : QVariant(fileHash));
    if (hasLocation) {
        query.bindValue(":latitude", latitude);
        query.bindValue(":longitude", longitude);
    } else {
        query.bindValue(":latitude", QVariant(QVariant::Double));
        query.bindValue(":longitude", QVariant(QVariant::Double));
    }

    if (!query.exec()) {
        QString errorMsg = "Failed to add photo: " + query.lastError().text();
        qWarning() << "  ✗ SQL Error:" << errorMsg;
        qWarning() << "  ✗ Query:" << query.lastQuery();
        qCDebug(lcNami) << "  ✗ File path:" << filePath;
        emit error(errorMsg);
        return -1;
    }

    int newId = query.lastInsertId().toInt();
    qCDebug(lcNami) << "  ✓ Photo inserted with ID:" << newId;
    return newId;
}

Photo FaceDatabase::getPhoto(int photoId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM photos WHERE id = :id");
    query.bindValue(":id", photoId);

    if (query.exec() && query.next()) {
        Photo photo;
        photo.id = query.value("id").toInt();
        photo.filePath = query.value("file_path").toString();
        photo.dateTaken = QDateTime::fromString(query.value("date_taken").toString(), Qt::ISODate);
        photo.width = query.value("width").toInt();
        photo.height = query.value("height").toInt();
        photo.processedAt = QDateTime::fromString(query.value("processed_at").toString(), Qt::ISODate);
        photo.rotation = query.value("rotation").toInt();
        QVariant lat = query.value("latitude");
        QVariant lon = query.value("longitude");
        photo.hasLocation = !lat.isNull() && !lon.isNull();
        photo.latitude = photo.hasLocation ? lat.toDouble() : 0.0;
        photo.longitude = photo.hasLocation ? lon.toDouble() : 0.0;
        photo.fileHash = query.value("file_hash").toString();
        return photo;
    }

    return Photo{-1, "", QDateTime(), 0, 0, QDateTime(), 0, false, 0.0, 0.0, ""};
}

int FaceDatabase::photoRotation(const QString &filePath)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT rotation FROM photos WHERE file_path = :path");
    query.bindValue(":path", filePath);

    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    return 0;
}

bool FaceDatabase::setPhotoRotation(const QString &filePath, int rotation)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE photos SET rotation = :rotation WHERE file_path = :path");
    query.bindValue(":rotation", rotation);
    query.bindValue(":path", filePath);

    return query.exec();
}

bool FaceDatabase::setPhotoHash(int photoId, const QString &fileHash)
{
    if (fileHash.isEmpty()) {
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare(R"(
        UPDATE photos SET file_hash = :hash
        WHERE id = :id AND (file_hash IS NULL OR file_hash = '')
    )");
    query.bindValue(":hash", fileHash);
    query.bindValue(":id", photoId);

    return query.exec();
}

int FaceDatabase::findPhotoByHash(const QString &fileHash)
{
    if (fileHash.isEmpty()) {
        return -1;
    }

    QSqlQuery query(m_db);
    query.prepare("SELECT id FROM photos WHERE file_hash = :hash LIMIT 1");
    query.bindValue(":hash", fileHash);

    if (query.exec() && query.next()) {
        return query.value(0).toInt();
    }
    return -1;
}

QVector<QPair<int, QString>> FaceDatabase::getPhotosMissingHash()
{
    QVector<QPair<int, QString>> result;
    QSqlQuery query(m_db);

    if (query.exec("SELECT id, file_path FROM photos WHERE file_hash IS NULL OR file_hash = ''")) {
        while (query.next()) {
            result.append(qMakePair(query.value(0).toInt(), query.value(1).toString()));
        }
    }

    return result;
}

QVector<Photo> FaceDatabase::getAllPhotos()
{
    QVector<Photo> photos;
    QSqlQuery query(m_db);

    if (query.exec("SELECT * FROM photos ORDER BY date_taken DESC")) {
        while (query.next()) {
            Photo photo;
            photo.id = query.value("id").toInt();
            photo.filePath = query.value("file_path").toString();
            photo.dateTaken = QDateTime::fromString(query.value("date_taken").toString(), Qt::ISODate);
            photo.width = query.value("width").toInt();
            photo.height = query.value("height").toInt();
            photo.processedAt = QDateTime::fromString(query.value("processed_at").toString(), Qt::ISODate);
            photo.rotation = query.value("rotation").toInt();
            QVariant lat = query.value("latitude");
            QVariant lon = query.value("longitude");
            photo.hasLocation = !lat.isNull() && !lon.isNull();
            photo.latitude = photo.hasLocation ? lat.toDouble() : 0.0;
            photo.longitude = photo.hasLocation ? lon.toDouble() : 0.0;
            photo.fileHash = query.value("file_hash").toString();
            photos.append(photo);
        }
    }

    return photos;
}

bool FaceDatabase::markPhotoProcessed(int photoId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE photos SET processed_at = :processed_at WHERE id = :id");
    query.bindValue(":processed_at", QDateTime::currentDateTime().toString(Qt::ISODate));
    query.bindValue(":id", photoId);

    return query.exec();
}

// === Face operations ===

int FaceDatabase::addFace(int photoId, const QRectF &bbox, float confidence,
                          const FaceEmbedding &embedding, int personId,
                          float similarityScore, bool verified)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        INSERT INTO faces (photo_id, bbox_x, bbox_y, bbox_width, bbox_height,
                          confidence, embedding, person_id, similarity_score, verified)
        VALUES (:photo_id, :bbox_x, :bbox_y, :bbox_width, :bbox_height,
                :confidence, :embedding, :person_id, :similarity_score, :verified)
    )");
    query.bindValue(":photo_id", photoId);
    query.bindValue(":bbox_x", bbox.x());
    query.bindValue(":bbox_y", bbox.y());
    query.bindValue(":bbox_width", bbox.width());
    query.bindValue(":bbox_height", bbox.height());
    query.bindValue(":confidence", confidence);
    query.bindValue(":embedding", serializeEmbedding(embedding));
    query.bindValue(":person_id", personId);
    query.bindValue(":similarity_score", similarityScore);
    query.bindValue(":verified", verified ? 1 : 0);

    if (!query.exec()) {
        emit error("Failed to add face: " + query.lastError().text());
        return -1;
    }

    return query.lastInsertId().toInt();
}

Face FaceDatabase::getFace(int faceId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE id = :id");
    query.bindValue(":id", faceId);

    if (query.exec() && query.next()) {
        Face face;
        face.id = query.value("id").toInt();
        face.photoId = query.value("photo_id").toInt();
        face.bbox = QRectF(
            query.value("bbox_x").toDouble(),
            query.value("bbox_y").toDouble(),
            query.value("bbox_width").toDouble(),
            query.value("bbox_height").toDouble()
        );
        face.confidence = query.value("confidence").toFloat();
        face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
        face.personId = query.value("person_id").toInt();
        face.similarityScore = query.value("similarity_score").toFloat();
        face.verified = query.value("verified").toInt() == 1;
        face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
        return face;
    }

    return Face{-1, -1, QRectF(), 0.0f, FaceEmbedding(), -1, 0.0f, false, QDateTime()};
}

QVector<Face> FaceDatabase::getFacesForPhoto(int photoId)
{
    QVector<Face> faces;
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE photo_id = :photo_id");
    query.bindValue(":photo_id", photoId);

    if (query.exec()) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

QVector<Face> FaceDatabase::getUnmappedFaces()
{
    QVector<Face> faces;
    QSqlQuery query(m_db);

    if (query.exec("SELECT * FROM faces WHERE person_id = -1 AND ignored = 0 ORDER BY detected_at DESC")) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

bool FaceDatabase::updateFacePersonMapping(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET person_id = :person_id WHERE id = :id");
    query.bindValue(":person_id", personId);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::updateFaceMetadata(int faceId, float similarityScore, bool verified)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET similarity_score = :similarity_score, verified = :verified WHERE id = :id");
    query.bindValue(":similarity_score", similarityScore);
    query.bindValue(":verified", verified ? 1 : 0);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::removeFaceFromPerson(int faceId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET person_id = -1, verified = 0 WHERE id = :id");
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::removePersonFromPhoto(int personId, int photoId)
{
    // Collect the affected faces first so each rejection is remembered
    QVector<int> faceIds;
    QSqlQuery sel(m_db);
    sel.prepare("SELECT id FROM faces WHERE photo_id = :photo AND person_id = :person");
    sel.bindValue(":photo", photoId);
    sel.bindValue(":person", personId);
    if (sel.exec()) {
        while (sel.next()) {
            faceIds.append(sel.value(0).toInt());
        }
    }

    for (int faceId : faceIds) {
        addNegativeMatch(faceId, personId);
    }

    QSqlQuery upd(m_db);
    upd.prepare("UPDATE faces SET person_id = -1, verified = 0 "
                "WHERE photo_id = :photo AND person_id = :person");
    upd.bindValue(":photo", photoId);
    upd.bindValue(":person", personId);

    return upd.exec();
}

bool FaceDatabase::setFaceIgnored(int faceId, bool ignored)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE faces SET ignored = :ignored WHERE id = :id");
    query.bindValue(":ignored", ignored ? 1 : 0);
    query.bindValue(":id", faceId);

    return query.exec();
}

bool FaceDatabase::addNegativeMatch(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO negative_matches (face_id, person_id) VALUES (:face_id, :person_id)");
    query.bindValue(":face_id", faceId);
    query.bindValue(":person_id", personId);

    return query.exec();
}

bool FaceDatabase::hasNegativeMatch(int faceId, int personId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT 1 FROM negative_matches WHERE face_id = :face_id AND person_id = :person_id");
    query.bindValue(":face_id", faceId);
    query.bindValue(":person_id", personId);

    return query.exec() && query.next();
}

bool FaceDatabase::deleteFacesForPhoto(int photoId)
{
    QSqlQuery cleanup(m_db);
    cleanup.prepare(R"(
        DELETE FROM negative_matches
        WHERE face_id IN (SELECT id FROM faces WHERE photo_id = :photo_id)
    )");
    cleanup.bindValue(":photo_id", photoId);
    cleanup.exec();

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM faces WHERE photo_id = :photo_id");
    query.bindValue(":photo_id", photoId);

    return query.exec();
}

QSet<QString> FaceDatabase::getProcessedFilePaths()
{
    QSet<QString> paths;
    QSqlQuery query(m_db);

    if (query.exec("SELECT file_path FROM photos WHERE processed_at IS NOT NULL")) {
        while (query.next()) {
            paths.insert(query.value(0).toString());
        }
    }

    return paths;
}

// === Person operations ===

int FaceDatabase::createPerson(const QString &name)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT INTO people (name) VALUES (:name)");
    query.bindValue(":name", name);

    if (!query.exec()) {
        emit error("Failed to create person: " + query.lastError().text());
        return -1;
    }

    return query.lastInsertId().toInt();
}

Person FaceDatabase::getPerson(int personId)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT p.*, COUNT(DISTINCT f.photo_id) as photo_count
        FROM people p
        LEFT JOIN faces f ON f.person_id = p.id
        WHERE p.id = :id
        GROUP BY p.id
    )");
    query.bindValue(":id", personId);

    if (query.exec() && query.next()) {
        Person person;
        person.id = query.value("id").toInt();
        person.name = query.value("name").toString();
        person.createdAt = QDateTime::fromString(query.value("created_at").toString(), Qt::ISODate);
        person.photoCount = query.value("photo_count").toInt();
        person.contactId = query.value("contact_id").toString();
        return person;
    }

    return Person{-1, "", QDateTime(), 0, QString()};
}

QVector<Person> FaceDatabase::getAllPeople()
{
    QVector<Person> people;
    QSqlQuery query(m_db);

    if (query.exec(R"(
        SELECT p.*, COUNT(DISTINCT f.photo_id) as photo_count
        FROM people p
        LEFT JOIN faces f ON f.person_id = p.id
        GROUP BY p.id
        ORDER BY p.name ASC
    )")) {
        while (query.next()) {
            Person person;
            person.id = query.value("id").toInt();
            person.name = query.value("name").toString();
            person.createdAt = QDateTime::fromString(query.value("created_at").toString(), Qt::ISODate);
            person.photoCount = query.value("photo_count").toInt();
            person.contactId = query.value("contact_id").toString();
            people.append(person);
        }
    }

    return people;
}

bool FaceDatabase::updatePersonName(int personId, const QString &name)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE people SET name = :name WHERE id = :id");
    query.bindValue(":name", name);
    query.bindValue(":id", personId);

    return query.exec();
}

bool FaceDatabase::setPersonContact(int personId, const QString &contactId)
{
    QSqlQuery query(m_db);
    query.prepare("UPDATE people SET contact_id = :contact_id WHERE id = :id");
    // Store NULL rather than "" when unlinking
    query.bindValue(":contact_id", contactId.isEmpty() ? QVariant() : QVariant(contactId));
    query.bindValue(":id", personId);

    return query.exec();
}

bool FaceDatabase::deletePerson(int personId)
{
    m_db.transaction();

    // Unmap all faces for this person
    QSqlQuery query1(m_db);
    query1.prepare("UPDATE faces SET person_id = -1 WHERE person_id = :person_id");
    query1.bindValue(":person_id", personId);

    if (!query1.exec()) {
        m_db.rollback();
        return false;
    }

    // Delete person
    QSqlQuery query2(m_db);
    query2.prepare("DELETE FROM people WHERE id = :id");
    query2.bindValue(":id", personId);

    if (!query2.exec()) {
        m_db.rollback();
        return false;
    }

    // Drop rejections referencing this person
    QSqlQuery query3(m_db);
    query3.prepare("DELETE FROM negative_matches WHERE person_id = :person_id");
    query3.bindValue(":person_id", personId);
    query3.exec();

    m_db.commit();
    return true;
}

bool FaceDatabase::mergePersons(int fromPersonId, int intoPersonId)
{
    m_db.transaction();

    // Reassign faces (verified flags and similarity scores carry over)
    QSqlQuery moveFaces(m_db);
    moveFaces.prepare("UPDATE faces SET person_id = :into WHERE person_id = :from");
    moveFaces.bindValue(":into", intoPersonId);
    moveFaces.bindValue(":from", fromPersonId);
    if (!moveFaces.exec()) {
        m_db.rollback();
        return false;
    }

    // A rejection of the duplicate is a rejection of the same human
    QSqlQuery moveRejections(m_db);
    moveRejections.prepare(R"(
        INSERT OR IGNORE INTO negative_matches (face_id, person_id)
        SELECT face_id, :into FROM negative_matches WHERE person_id = :from
    )");
    moveRejections.bindValue(":into", intoPersonId);
    moveRejections.bindValue(":from", fromPersonId);
    if (!moveRejections.exec()) {
        m_db.rollback();
        return false;
    }

    QSqlQuery dropRejections(m_db);
    dropRejections.prepare("DELETE FROM negative_matches WHERE person_id = :from");
    dropRejections.bindValue(":from", fromPersonId);
    dropRejections.exec();

    QSqlQuery dropPerson(m_db);
    dropPerson.prepare("DELETE FROM people WHERE id = :from");
    dropPerson.bindValue(":from", fromPersonId);
    if (!dropPerson.exec()) {
        m_db.rollback();
        return false;
    }

    m_db.commit();
    return true;
}

QVector<Face> FaceDatabase::getFacesForPerson(int personId)
{
    QVector<Face> faces;
    QSqlQuery query(m_db);
    query.prepare("SELECT * FROM faces WHERE person_id = :person_id");
    query.bindValue(":person_id", personId);

    if (query.exec()) {
        while (query.next()) {
            Face face;
            face.id = query.value("id").toInt();
            face.photoId = query.value("photo_id").toInt();
            face.bbox = QRectF(
                query.value("bbox_x").toDouble(),
                query.value("bbox_y").toDouble(),
                query.value("bbox_width").toDouble(),
                query.value("bbox_height").toDouble()
            );
            face.confidence = query.value("confidence").toFloat();
            face.embedding = deserializeEmbedding(query.value("embedding").toByteArray());
            face.personId = query.value("person_id").toInt();
            face.similarityScore = query.value("similarity_score").toFloat();
            face.verified = query.value("verified").toInt() == 1;
            face.detectedAt = QDateTime::fromString(query.value("detected_at").toString(), Qt::ISODate);
            faces.append(face);
        }
    }

    return faces;
}

Face FaceDatabase::getBestFaceForPerson(int personId)
{
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT id FROM faces
        WHERE person_id = :person_id
        ORDER BY verified DESC, similarity_score DESC, confidence DESC
        LIMIT 1
    )");
    query.bindValue(":person_id", personId);

    if (query.exec() && query.next()) {
        return getFace(query.value(0).toInt());
    }

    return Face{-1, -1, QRectF(), 0.0f, FaceEmbedding(), -1, 0.0f, false, QDateTime()};
}

QVector<FaceEmbedding> FaceDatabase::getPersonExemplars(int personId, int maxCount)
{
    QVector<FaceEmbedding> exemplars;

    // User-verified faces define the person; only fall back to unverified
    // detections when there is no verified face yet, so a bad auto-match
    // cannot poison the person's representation
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT embedding FROM faces
        WHERE person_id = :person_id AND verified = 1
        ORDER BY similarity_score DESC, confidence DESC
        LIMIT :limit
    )");
    query.bindValue(":person_id", personId);
    query.bindValue(":limit", maxCount);

    if (query.exec()) {
        while (query.next()) {
            exemplars.append(deserializeEmbedding(query.value(0).toByteArray()));
        }
    }

    if (exemplars.isEmpty()) {
        QSqlQuery fallback(m_db);
        fallback.prepare(R"(
            SELECT embedding FROM faces
            WHERE person_id = :person_id
            ORDER BY confidence DESC
            LIMIT :limit
        )");
        fallback.bindValue(":person_id", personId);
        fallback.bindValue(":limit", maxCount);

        if (fallback.exec()) {
            while (fallback.next()) {
                exemplars.append(deserializeEmbedding(fallback.value(0).toByteArray()));
            }
        }
    }

    return exemplars;
}

// === GDPR ===

QVariantMap FaceDatabase::exportPersonData(int personId)
{
    QVariantMap data;
    Person person = getPerson(personId);

    data["person_id"] = person.id;
    data["name"] = person.name;
    data["created_at"] = person.createdAt.toString(Qt::ISODate);

    QVariantList facesData;
    QVector<Face> faces = getFacesForPerson(personId);

    for (const Face &face : faces) {
        QVariantMap faceData;
        faceData["face_id"] = face.id;
        faceData["photo_id"] = face.photoId;
        faceData["confidence"] = face.confidence;
        faceData["detected_at"] = face.detectedAt.toString(Qt::ISODate);
        facesData.append(faceData);
    }

    data["faces"] = facesData;
    data["total_faces"] = faces.size();

    return data;
}

// === Full backup ===

QJsonObject FaceDatabase::exportBackup()
{
    QJsonObject root;
    root["app"] = "harbour-nami";
    root["backup_version"] = 1;
    root["exported_at"] = QDateTime::currentDateTime().toString(Qt::ISODate);

    QVector<Person> people = getAllPeople();
    QHash<int, int> personIndexById;
    QJsonArray peopleArray;
    for (const Person &person : people) {
        personIndexById[person.id] = peopleArray.size();
        QJsonObject p;
        p["name"] = person.name;
        p["contact_id"] = person.contactId;
        p["created_at"] = person.createdAt.toString(Qt::ISODate);
        peopleArray.append(p);
    }
    root["people"] = peopleArray;

    QVector<Photo> photos = getAllPhotos();
    QHash<int, QString> photoPathById;
    QJsonArray photosArray;
    for (const Photo &photo : photos) {
        photoPathById[photo.id] = photo.filePath;
        QJsonObject ph;
        ph["file_path"] = photo.filePath;
        ph["date_taken"] = photo.dateTaken.toString(Qt::ISODate);
        ph["width"] = photo.width;
        ph["height"] = photo.height;
        ph["rotation"] = photo.rotation;
        ph["file_hash"] = photo.fileHash;
        if (photo.hasLocation) {
            ph["latitude"] = photo.latitude;
            ph["longitude"] = photo.longitude;
        }
        photosArray.append(ph);
    }
    root["photos"] = photosArray;

    QJsonArray facesArray;
    QSqlQuery faceQuery(m_db);
    if (faceQuery.exec("SELECT * FROM faces")) {
        while (faceQuery.next()) {
            int photoId = faceQuery.value("photo_id").toInt();
            if (!photoPathById.contains(photoId)) {
                continue;
            }
            QJsonObject f;
            f["photo_path"] = photoPathById[photoId];
            f["bbox"] = QJsonArray{
                faceQuery.value("bbox_x").toDouble(),
                faceQuery.value("bbox_y").toDouble(),
                faceQuery.value("bbox_width").toDouble(),
                faceQuery.value("bbox_height").toDouble()
            };
            f["confidence"] = faceQuery.value("confidence").toDouble();
            int personId = faceQuery.value("person_id").toInt();
            f["person_index"] = personIndexById.contains(personId) ? personIndexById[personId] : -1;
            f["similarity_score"] = faceQuery.value("similarity_score").toDouble();
            f["verified"] = faceQuery.value("verified").toInt() == 1;
            f["ignored"] = faceQuery.value("ignored").toInt() == 1;
            f["detected_at"] = faceQuery.value("detected_at").toString();
            f["embedding"] = QString::fromLatin1(faceQuery.value("embedding").toByteArray().toBase64());
            facesArray.append(f);
        }
    }
    root["faces"] = facesArray;

    QJsonArray negativeArray;
    QSqlQuery negQuery(m_db);
    if (negQuery.exec(R"(
        SELECT f.photo_id, f.bbox_x, f.bbox_y, f.bbox_width, f.bbox_height, nm.person_id
        FROM negative_matches nm
        JOIN faces f ON f.id = nm.face_id
    )")) {
        while (negQuery.next()) {
            int photoId = negQuery.value(0).toInt();
            int personId = negQuery.value(5).toInt();
            if (!photoPathById.contains(photoId) || !personIndexById.contains(personId)) {
                continue;
            }
            QJsonObject n;
            n["photo_path"] = photoPathById[photoId];
            n["bbox"] = QJsonArray{
                negQuery.value(1).toDouble(), negQuery.value(2).toDouble(),
                negQuery.value(3).toDouble(), negQuery.value(4).toDouble()
            };
            n["person_index"] = personIndexById[personId];
            negativeArray.append(n);
        }
    }
    root["negative_matches"] = negativeArray;

    QJsonArray tripsArray;
    for (const Trip &trip : getAllTrips()) {
        QJsonObject t;
        t["name"] = trip.name;
        t["date_keys"] = QJsonArray::fromStringList(trip.dateKeys);
        tripsArray.append(t);
    }
    root["trips"] = tripsArray;

    return root;
}

namespace {
// Identifies a face across the export/import boundary, since DB ids are
// not stable: a photo can only have one face at a given bounding box
QString faceKey(const QString &photoPath, const QJsonArray &bbox)
{
    return QString("%1|%2,%3,%4,%5").arg(photoPath)
        .arg(bbox.at(0).toDouble(), 0, 'f', 6)
        .arg(bbox.at(1).toDouble(), 0, 'f', 6)
        .arg(bbox.at(2).toDouble(), 0, 'f', 6)
        .arg(bbox.at(3).toDouble(), 0, 'f', 6);
}
}

FaceDatabase::ImportStats FaceDatabase::importBackup(const QJsonObject &root)
{
    ImportStats stats;

    if (root["app"].toString() != "harbour-nami") {
        return stats;
    }

    beginTransaction();

    // People: reuse an existing person with the same name rather than
    // creating a duplicate when merging into a non-empty database
    QHash<QString, int> personIdByName;
    for (const Person &p : getAllPeople()) {
        personIdByName[p.name.toLower()] = p.id;
    }

    QVector<int> personIdByIndex;
    for (const QJsonValue &v : root["people"].toArray()) {
        QJsonObject p = v.toObject();
        QString name = p["name"].toString();
        int personId = personIdByName.value(name.toLower(), -1);
        if (personId == -1) {
            personId = createPerson(name);
            if (personId != -1) {
                QString contactId = p["contact_id"].toString();
                if (!contactId.isEmpty()) {
                    setPersonContact(personId, contactId);
                }
                personIdByName[name.toLower()] = personId;
                stats.peopleImported++;
            }
        }
        personIdByIndex.append(personId);
    }

    // Photos: matched by path when the file is still there; otherwise by
    // content hash, which survives a photo being moved to a different path
    // (e.g. a renamed SD card after a device migration)
    QHash<QString, int> photoIdByPath;
    for (const QJsonValue &v : root["photos"].toArray()) {
        QJsonObject ph = v.toObject();
        QString path = ph["file_path"].toString();
        QString hash = ph["file_hash"].toString();
        int photoId = -1;

        if (QFileInfo::exists(path)) {
            QSqlQuery check(m_db);
            check.prepare("SELECT id FROM photos WHERE file_path = :path");
            check.bindValue(":path", path);
            if (check.exec() && check.next()) {
                photoId = check.value(0).toInt();
                if (!hash.isEmpty()) {
                    setPhotoHash(photoId, hash);
                }
            } else {
                bool hasLocation = ph.contains("latitude") && ph.contains("longitude");
                photoId = addPhoto(path,
                                    QDateTime::fromString(ph["date_taken"].toString(), Qt::ISODate),
                                    ph["width"].toInt(), ph["height"].toInt(),
                                    hasLocation, ph["latitude"].toDouble(), ph["longitude"].toDouble(),
                                    hash);
                if (photoId != -1) {
                    int rotation = ph["rotation"].toInt();
                    if (rotation != 0) {
                        setPhotoRotation(path, rotation);
                    }
                    stats.photosImported++;
                }
            }
            if (photoId != -1) {
                markPhotoProcessed(photoId);
            }
        } else if (!hash.isEmpty()) {
            photoId = findPhotoByHash(hash);
            if (photoId != -1) {
                stats.photosRelinked++;
            }
        }

        if (photoId != -1) {
            photoIdByPath[path] = photoId;
        } else {
            stats.photosSkipped++;
        }
    }

    // A photo already has faces when it was scanned locally before being
    // restored (either at its original path, or at a new one and relinked
    // by hash above); don't duplicate its faces
    QSet<int> photosWithExistingFaces;
    for (int photoId : photoIdByPath) {
        QSqlQuery check(m_db);
        check.prepare("SELECT 1 FROM faces WHERE photo_id = :id LIMIT 1");
        check.bindValue(":id", photoId);
        if (check.exec() && check.next()) {
            photosWithExistingFaces.insert(photoId);
        }
    }

    QHash<QString, int> faceIdByKey;
    for (const QJsonValue &v : root["faces"].toArray()) {
        QJsonObject f = v.toObject();
        QString photoPath = f["photo_path"].toString();
        if (!photoIdByPath.contains(photoPath)) {
            continue;
        }
        int photoId = photoIdByPath[photoPath];

        QJsonArray bboxArr = f["bbox"].toArray();
        QRectF bbox(bboxArr.at(0).toDouble(), bboxArr.at(1).toDouble(),
                    bboxArr.at(2).toDouble(), bboxArr.at(3).toDouble());

        int personIndex = f["person_index"].toInt(-1);
        int personId = (personIndex >= 0 && personIndex < personIdByIndex.size())
            ? personIdByIndex.at(personIndex) : -1;

        if (photosWithExistingFaces.contains(photoId)) {
            // Already scanned locally (found by path or relinked by hash):
            // carry the identification over onto the matching local face
            // instead of inserting a duplicate
            if (personId != -1) {
                int localFaceId = findClosestUnassignedFace(photoId, bbox);
                if (localFaceId != -1) {
                    updateFacePersonMapping(localFaceId, personId);
                    updateFaceMetadata(localFaceId, f["similarity_score"].toDouble(), f["verified"].toBool());
                    stats.facesImported++;
                    faceIdByKey[faceKey(photoPath, bboxArr)] = localFaceId;
                }
            }
            continue;
        }

        FaceEmbedding embedding = deserializeEmbedding(
            QByteArray::fromBase64(f["embedding"].toString().toLatin1()));

        int faceId = addFace(photoId, bbox, f["confidence"].toDouble(),
                              embedding, personId,
                              f["similarity_score"].toDouble(), f["verified"].toBool());
        if (faceId != -1) {
            if (f["ignored"].toBool()) {
                setFaceIgnored(faceId, true);
            }
            stats.facesImported++;
            faceIdByKey[faceKey(photoPath, bboxArr)] = faceId;
        }
    }

    for (const QJsonValue &v : root["negative_matches"].toArray()) {
        QJsonObject n = v.toObject();
        QString photoPath = n["photo_path"].toString();
        QJsonArray bboxArr = n["bbox"].toArray();
        QString key = faceKey(photoPath, bboxArr);
        if (!faceIdByKey.contains(key)) {
            continue;
        }
        int personIndex = n["person_index"].toInt(-1);
        if (personIndex < 0 || personIndex >= personIdByIndex.size()) {
            continue;
        }
        addNegativeMatch(faceIdByKey[key], personIdByIndex.at(personIndex));
    }

    QHash<QString, int> tripIdByName;
    for (const Trip &t : getAllTrips()) {
        tripIdByName[t.name.toLower()] = t.id;
    }
    for (const QJsonValue &v : root["trips"].toArray()) {
        QJsonObject t = v.toObject();
        QString name = t["name"].toString();
        if (tripIdByName.contains(name.toLower())) {
            continue;  // already grouped locally, don't override
        }
        QStringList dateKeys;
        for (const QJsonValue &d : t["date_keys"].toArray()) {
            dateKeys.append(d.toString());
        }
        if (createTrip(name, dateKeys) != -1) {
            stats.tripsImported++;
        }
    }

    commitTransaction();
    return stats;
}

bool FaceDatabase::deleteAllData()
{
    m_db.transaction();

    QSqlQuery query(m_db);

    if (!query.exec("DELETE FROM negative_matches") ||
        !query.exec("DELETE FROM faces") ||
        !query.exec("DELETE FROM people") ||
        !query.exec("DELETE FROM photos") ||
        !query.exec("DELETE FROM trip_dates") ||
        !query.exec("DELETE FROM trips") ||
        !query.exec("DELETE FROM event_covers")) {
        m_db.rollback();
        return false;
    }

    m_db.commit();

    // Reclaim space and purge deleted embeddings from free pages
    query.exec("VACUUM");
    return true;
}

bool FaceDatabase::clearFaceData()
{
    m_db.transaction();

    QSqlQuery query(m_db);

    // Photos records are kept, but they must be re-processed
    if (!query.exec("DELETE FROM negative_matches") ||
        !query.exec("DELETE FROM faces") ||
        !query.exec("DELETE FROM people") ||
        !query.exec("UPDATE photos SET processed_at = NULL")) {
        m_db.rollback();
        return false;
    }

    m_db.commit();
    return true;
}

QString FaceDatabase::getSetting(const QString &key, const QString &defaultValue)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT value FROM settings WHERE key = :key");
    query.bindValue(":key", key);

    if (query.exec() && query.next()) {
        return query.value(0).toString();
    }

    return defaultValue;
}

bool FaceDatabase::setSetting(const QString &key, const QString &value)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR REPLACE INTO settings (key, value) VALUES (:key, :value)");
    query.bindValue(":key", key);
    query.bindValue(":value", value);

    return query.exec();
}

QVariantMap FaceDatabase::getStatistics()
{
    QVariantMap stats;
    QSqlQuery query(m_db);

    if (query.exec("SELECT COUNT(*) FROM photos")) {
        query.next();
        stats["total_photos"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM faces")) {
        query.next();
        stats["total_faces"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM people")) {
        query.next();
        stats["total_people"] = query.value(0).toInt();
    }

    if (query.exec("SELECT COUNT(*) FROM faces WHERE person_id = -1 AND ignored = 0")) {
        query.next();
        stats["unmapped_faces"] = query.value(0).toInt();
    }

    stats["db_size_bytes"] = QFileInfo(m_dbPath).size();

    return stats;
}

// === Trips ===

int FaceDatabase::createTrip(const QString &name, const QStringList &dateKeys)
{
    if (name.trimmed().isEmpty() || dateKeys.isEmpty()) {
        return -1;
    }

    QSqlQuery query(m_db);
    query.prepare("INSERT INTO trips (name) VALUES (:name)");
    query.bindValue(":name", name.trimmed());

    if (!query.exec()) {
        emit error("Failed to create trip: " + query.lastError().text());
        return -1;
    }

    int tripId = query.lastInsertId().toInt();

    for (const QString &dateKey : dateKeys) {
        // A date already grouped into another trip is left alone: the
        // caller only offers ungrouped days for selection
        QSqlQuery dateQuery(m_db);
        dateQuery.prepare("INSERT OR IGNORE INTO trip_dates (date_key, trip_id) VALUES (:date_key, :trip_id)");
        dateQuery.bindValue(":date_key", dateKey);
        dateQuery.bindValue(":trip_id", tripId);
        dateQuery.exec();
    }

    return tripId;
}

bool FaceDatabase::renameTrip(int tripId, const QString &name)
{
    if (name.trimmed().isEmpty()) {
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE trips SET name = :name WHERE id = :id");
    query.bindValue(":name", name.trimmed());
    query.bindValue(":id", tripId);

    return query.exec() && query.numRowsAffected() > 0;
}

bool FaceDatabase::deleteTrip(int tripId)
{
    clearEventCover(QString("trip:%1").arg(tripId));

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM trips WHERE id = :id");
    query.bindValue(":id", tripId);

    return query.exec() && query.numRowsAffected() > 0;
}

QVector<Trip> FaceDatabase::getAllTrips()
{
    QVector<Trip> trips;
    QSqlQuery query(m_db);

    if (!query.exec("SELECT id, name, created_at FROM trips ORDER BY created_at DESC")) {
        return trips;
    }

    while (query.next()) {
        Trip trip;
        trip.id = query.value("id").toInt();
        trip.name = query.value("name").toString();
        trip.createdAt = QDateTime::fromString(query.value("created_at").toString(), Qt::ISODate);

        QSqlQuery datesQuery(m_db);
        datesQuery.prepare("SELECT date_key FROM trip_dates WHERE trip_id = :trip_id ORDER BY date_key");
        datesQuery.bindValue(":trip_id", trip.id);
        if (datesQuery.exec()) {
            while (datesQuery.next()) {
                trip.dateKeys.append(datesQuery.value(0).toString());
            }
        }

        trips.append(trip);
    }

    return trips;
}

bool FaceDatabase::mergeTrips(int fromTripId, int intoTripId)
{
    if (fromTripId == intoTripId) {
        return false;
    }

    QSqlQuery reassign(m_db);
    reassign.prepare("UPDATE trip_dates SET trip_id = :into WHERE trip_id = :from");
    reassign.bindValue(":into", intoTripId);
    reassign.bindValue(":from", fromTripId);
    if (!reassign.exec()) {
        emit error("Failed to merge trips: " + reassign.lastError().text());
        return false;
    }

    // The dissolved trip's cover no longer applies to anything
    clearEventCover(QString("trip:%1").arg(fromTripId));

    QSqlQuery del(m_db);
    del.prepare("DELETE FROM trips WHERE id = :id");
    del.bindValue(":id", fromTripId);
    return del.exec();
}

// === Event covers ===

bool FaceDatabase::setEventCover(const QString &eventKey, const QString &photoPath)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR REPLACE INTO event_covers (event_key, photo_path) VALUES (:key, :path)");
    query.bindValue(":key", eventKey);
    query.bindValue(":path", photoPath);
    return query.exec();
}

bool FaceDatabase::clearEventCover(const QString &eventKey)
{
    QSqlQuery query(m_db);
    query.prepare("DELETE FROM event_covers WHERE event_key = :key");
    query.bindValue(":key", eventKey);
    return query.exec();
}

QVariantMap FaceDatabase::getEventCovers()
{
    QVariantMap covers;
    QSqlQuery query(m_db);

    if (query.exec("SELECT event_key, photo_path FROM event_covers")) {
        while (query.next()) {
            covers[query.value(0).toString()] = query.value(1).toString();
        }
    }

    return covers;
}

// === Recent photos ===

QVector<Photo> FaceDatabase::getRecentPhotos(int limit)
{
    QVector<Photo> photos;
    QSqlQuery query(m_db);
    query.prepare(R"(
        SELECT * FROM photos
        WHERE date_taken IS NOT NULL AND date_taken != ''
        ORDER BY date_taken DESC
        LIMIT :limit
    )");
    query.bindValue(":limit", limit);

    if (query.exec()) {
        while (query.next()) {
            Photo photo;
            photo.id = query.value("id").toInt();
            photo.filePath = query.value("file_path").toString();
            photo.dateTaken = QDateTime::fromString(query.value("date_taken").toString(), Qt::ISODate);
            photo.width = query.value("width").toInt();
            photo.height = query.value("height").toInt();
            photo.processedAt = QDateTime::fromString(query.value("processed_at").toString(), Qt::ISODate);
            photo.rotation = query.value("rotation").toInt();
            QVariant lat = query.value("latitude");
            QVariant lon = query.value("longitude");
            photo.hasLocation = !lat.isNull() && !lon.isNull();
            photo.latitude = photo.hasLocation ? lat.toDouble() : 0.0;
            photo.longitude = photo.hasLocation ? lon.toDouble() : 0.0;
            photos.append(photo);
        }
    }

    return photos;
}

// === Helpers ===

QByteArray FaceDatabase::serializeEmbedding(const FaceEmbedding &embedding)
{
    QByteArray data;
    QDataStream stream(&data, QIODevice::WriteOnly);

    stream << static_cast<quint32>(embedding.size());
    for (float val : embedding) {
        stream << val;
    }

    return data;
}

FaceEmbedding FaceDatabase::deserializeEmbedding(const QByteArray &data)
{
    QDataStream stream(data);
    quint32 size;
    stream >> size;

    FaceEmbedding embedding(size);
    for (quint32 i = 0; i < size; i++) {
        stream >> embedding[i];
    }

    return embedding;
}

int FaceDatabase::findClosestUnassignedFace(int photoId, const QRectF &bbox)
{
    int bestId = -1;
    double bestIoU = 0.5;  // same file, same detector: expect near-perfect overlap

    for (const Face &face : getFacesForPhoto(photoId)) {
        if (face.personId != -1) {
            continue;  // never override an identification already made locally
        }

        QRectF inter = face.bbox.intersected(bbox);
        double interArea = inter.isValid() ? inter.width() * inter.height() : 0.0;
        double unionArea = face.bbox.width() * face.bbox.height()
                          + bbox.width() * bbox.height() - interArea;
        double iou = unionArea > 0.0 ? interArea / unionArea : 0.0;

        if (iou > bestIoU) {
            bestIoU = iou;
            bestId = face.id;
        }
    }

    return bestId;
}
