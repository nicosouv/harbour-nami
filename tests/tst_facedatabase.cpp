// Unit tests for FaceDatabase: the schema, the backup format, and the
// helpers behind identification suggestions. No models, no camera, no
// device - an SQLite file in a temp dir is all this needs, so it runs
// headless in CI.

#include <QtTest>
#include <QTemporaryDir>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QFile>

#include "facedatabase.h"

class TstFaceDatabase : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void opensAndCreatesSchema();
    void storesAndReadsBackAPerson();
    void exportedBackupLeavesOutContactLinks();
    void backupRoundTripKeepsPeopleFacesAndTrips();
    void importIsAdditiveOnExistingPeople();
    void importSkipsPhotosThatNoLongerExist();
    void negativeMatchesComeBackInOneQuery();
    void peopleAroundDateHonoursTheWindow();
    void exemplarsPreferVerifiedFaces();

private:
    // A photo file has to exist on disk for the import to accept it
    QString makePhotoFile(const QString &name);
    int addPhotoWithFace(const QString &name, const QDateTime &taken,
                         int personId, bool verified = true, float seed = 0.1f);

    QTemporaryDir *m_dir = nullptr;
    FaceDatabase *m_db = nullptr;
};

void TstFaceDatabase::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
    m_db = new FaceDatabase;
    QVERIFY2(m_db->open(m_dir->filePath("test.db")), "could not open the database");
}

void TstFaceDatabase::cleanup()
{
    m_db->close();
    delete m_db;
    m_db = nullptr;
    delete m_dir;
    m_dir = nullptr;
}

QString TstFaceDatabase::makePhotoFile(const QString &name)
{
    const QString path = m_dir->filePath(name);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write("not really a jpeg");
        file.close();
    }
    return path;
}

int TstFaceDatabase::addPhotoWithFace(const QString &name, const QDateTime &taken,
                                      int personId, bool verified, float seed)
{
    const QString path = makePhotoFile(name);
    const int photoId = m_db->addPhoto(path, taken, 1000, 800);
    Q_ASSERT(photoId > 0);

    FaceEmbedding embedding(128, seed);
    return m_db->addFace(photoId, QRectF(0.1, 0.1, 0.2, 0.2), 0.9f,
                         embedding, personId, 1.0f, verified);
}

void TstFaceDatabase::opensAndCreatesSchema()
{
    // open() runs initializeSchema(), so the tables must already be usable
    QCOMPARE(m_db->getAllPeople().size(), 0);
    QCOMPARE(m_db->getAllPhotos().size(), 0);
    QCOMPARE(m_db->getUnmappedFaces().size(), 0);
}

void TstFaceDatabase::storesAndReadsBackAPerson()
{
    const int personId = m_db->createPerson("Alice");
    QVERIFY(personId > 0);

    const Person person = m_db->getPerson(personId);
    QCOMPARE(person.id, personId);
    QCOMPARE(person.name, QStringLiteral("Alice"));

    QCOMPARE(m_db->getAllPeople().size(), 1);
    QCOMPARE(m_db->getPerson(-1).id, -1);
}

void TstFaceDatabase::exportedBackupLeavesOutContactLinks()
{
    const int personId = m_db->createPerson("Alice");
    QVERIFY(m_db->setPersonContact(personId, "sailfish-contact-42"));
    QCOMPARE(m_db->getPerson(personId).contactId, QStringLiteral("sailfish-contact-42"));

    const QJsonObject backup = m_db->exportBackup();
    const QJsonArray people = backup["people"].toArray();
    QCOMPARE(people.size(), 1);

    // A contact id points at the address book of the device the backup was
    // made on, and means nothing on the one it is restored to
    const QJsonObject exported = people.at(0).toObject();
    QCOMPARE(exported["name"].toString(), QStringLiteral("Alice"));
    QVERIFY2(!exported.contains("contact_id"), "the backup still carries contact links");
}

void TstFaceDatabase::backupRoundTripKeepsPeopleFacesAndTrips()
{
    const int alice = m_db->createPerson("Alice");
    const int bob = m_db->createPerson("Bob");
    const QDateTime taken = QDateTime::fromString("2026-07-14T10:00:00", Qt::ISODate);

    const int aliceFace = addPhotoWithFace("alice.jpg", taken, alice);
    addPhotoWithFace("bob.jpg", taken.addDays(1), bob);
    QVERIFY(aliceFace > 0);
    QVERIFY(m_db->addNegativeMatch(aliceFace, bob));
    QVERIFY(m_db->createTrip("Summer", QStringList() << "2026-07-14" << "2026-07-15") > 0);

    const QJsonObject backup = m_db->exportBackup();
    QCOMPARE(backup["app"].toString(), QStringLiteral("harbour-nami"));
    QCOMPARE(backup["people"].toArray().size(), 2);
    QCOMPARE(backup["photos"].toArray().size(), 2);
    QCOMPARE(backup["faces"].toArray().size(), 2);
    QCOMPARE(backup["negative_matches"].toArray().size(), 1);
    QCOMPARE(backup["trips"].toArray().size(), 1);

    // Restore into an empty database, as a device migration would
    FaceDatabase fresh;
    QVERIFY(fresh.open(m_dir->filePath("restored.db")));
    const FaceDatabase::ImportStats stats = fresh.importBackup(backup);

    QCOMPARE(stats.peopleImported, 2);
    QCOMPARE(stats.photosImported, 2);
    QCOMPARE(stats.facesImported, 2);
    QCOMPARE(stats.tripsImported, 1);

    QCOMPARE(fresh.getAllPeople().size(), 2);
    QCOMPARE(fresh.getAllPhotos().size(), 2);
    QCOMPARE(fresh.getAllTrips().size(), 1);

    // And the restored people carry no contact link
    for (const Person &person : fresh.getAllPeople()) {
        QVERIFY2(person.contactId.isEmpty(), "a contact link survived the round trip");
    }
    fresh.close();
}

void TstFaceDatabase::importIsAdditiveOnExistingPeople()
{
    m_db->createPerson("Alice");
    addPhotoWithFace("alice.jpg", QDateTime::currentDateTime(), m_db->getAllPeople().first().id);
    const QJsonObject backup = m_db->exportBackup();

    // Importing into the very database it came from must not duplicate
    // anything: same person name, same photo path
    const FaceDatabase::ImportStats stats = m_db->importBackup(backup);
    QCOMPARE(stats.peopleImported, 0);
    QCOMPARE(stats.photosImported, 0);
    QCOMPARE(m_db->getAllPeople().size(), 1);
    QCOMPARE(m_db->getAllPhotos().size(), 1);
}

void TstFaceDatabase::importSkipsPhotosThatNoLongerExist()
{
    const int alice = m_db->createPerson("Alice");
    addPhotoWithFace("gone.jpg", QDateTime::currentDateTime(), alice);
    const QJsonObject backup = m_db->exportBackup();

    QVERIFY(QFile::remove(m_dir->filePath("gone.jpg")));

    FaceDatabase fresh;
    QVERIFY(fresh.open(m_dir->filePath("restored2.db")));
    const FaceDatabase::ImportStats stats = fresh.importBackup(backup);

    // The person is still worth keeping; the photo has nothing to attach to
    QCOMPARE(stats.peopleImported, 1);
    QCOMPARE(stats.photosSkipped, 1);
    QCOMPARE(stats.facesImported, 0);
    fresh.close();
}

void TstFaceDatabase::negativeMatchesComeBackInOneQuery()
{
    const int alice = m_db->createPerson("Alice");
    const int bob = m_db->createPerson("Bob");
    const int faceId = addPhotoWithFace("face.jpg", QDateTime::currentDateTime(), -1);

    QVERIFY(m_db->getNegativeMatches(faceId).isEmpty());

    QVERIFY(m_db->addNegativeMatch(faceId, alice));
    QVERIFY(m_db->addNegativeMatch(faceId, bob));
    // Recording the same rejection twice must stay harmless
    QVERIFY(m_db->addNegativeMatch(faceId, alice));

    const QSet<int> rejected = m_db->getNegativeMatches(faceId);
    QCOMPARE(rejected.size(), 2);
    QVERIFY(rejected.contains(alice));
    QVERIFY(rejected.contains(bob));
    QVERIFY(m_db->hasNegativeMatch(faceId, alice));
    QVERIFY(!m_db->hasNegativeMatch(faceId + 999, alice));
}

void TstFaceDatabase::peopleAroundDateHonoursTheWindow()
{
    const int alice = m_db->createPerson("Alice");
    const int bob = m_db->createPerson("Bob");
    const QDateTime day = QDateTime::fromString("2026-07-14T12:00:00", Qt::ISODate);

    addPhotoWithFace("alice.jpg", day, alice);
    addPhotoWithFace("bob.jpg", day.addDays(30), bob);

    const QSet<int> sameDay = m_db->getPeopleAroundDate(day, 1);
    QVERIFY2(sameDay.contains(alice), "the person photographed that day is missing");
    QVERIFY2(!sameDay.contains(bob), "someone a month away counted as the same day");

    // Widen the window and Bob comes into view
    QVERIFY(m_db->getPeopleAroundDate(day, 40).contains(bob));

    // An invalid date must not throw the net over everyone
    QVERIFY(m_db->getPeopleAroundDate(QDateTime(), 1).isEmpty());
}

void TstFaceDatabase::exemplarsPreferVerifiedFaces()
{
    const int alice = m_db->createPerson("Alice");
    const QDateTime now = QDateTime::currentDateTime();

    // One auto-matched face only: the fallback has to return it, otherwise a
    // freshly grouped person could never be suggested
    addPhotoWithFace("auto.jpg", now, alice, /*verified*/ false, 0.25f);
    QVector<FaceEmbedding> exemplars = m_db->getPersonExemplars(alice);
    QCOMPARE(exemplars.size(), 1);
    QCOMPARE(exemplars.first().at(0), 0.25f);

    // Once the user confirms a face, unverified ones stop defining the person
    addPhotoWithFace("verified.jpg", now, alice, /*verified*/ true, 0.75f);
    exemplars = m_db->getPersonExemplars(alice);
    QCOMPARE(exemplars.size(), 1);
    QCOMPARE(exemplars.first().at(0), 0.75f);
}

QTEST_MAIN(TstFaceDatabase)
#include "tst_facedatabase.moc"
