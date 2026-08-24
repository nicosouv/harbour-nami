// Unit tests for the memories storage layer: idempotent regeneration, the
// line between what a recipe owns and what the user owns, and the photo
// set's ordering and exclusions. Like the other tests here, this needs
// nothing but an SQLite file in a temp dir.

#include <QtTest>
#include <QTemporaryDir>
#include <QDateTime>
#include <QFile>

#include "facedatabase.h"

class TstMemories : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void rerunningARecipeRefreshesInsteadOfDuplicating();
    void regenerationKeepsTheChoicesTheUserMade();
    void anEditedMemoryIsLeftAlone();
    void coverFallsBackToTheFirstPhoto();
    void excludingAPhotoKeepsItAroundToUndo();
    void reorderPutsTheListedPhotosFirst();
    void aMemoryWithNoPhotosIsNotListed();
    void dismissedMemoriesAreHiddenButStillRegenerated();
    void pruningAPhotoTakesItOutOfItsMemories();
    void faceBoxesComeBackForTheWholeMemoryAtOnce();
    void photosOfPeopleTellTogetherFromAnyOfThem();

private:
    QString makePhotoFile(const QString &name);
    int addPhoto(const QString &name, int daysAgo);
    Memory recipeMemory(const QString &title = QStringLiteral("Il y a 3 ans"));

    QTemporaryDir *m_dir = nullptr;
    FaceDatabase *m_db = nullptr;
};

void TstMemories::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
    m_db = new FaceDatabase;
    QVERIFY2(m_db->open(m_dir->filePath("test.db")), "could not open the database");
}

void TstMemories::cleanup()
{
    m_db->close();
    delete m_db;
    m_db = nullptr;
    delete m_dir;
    m_dir = nullptr;
}

QString TstMemories::makePhotoFile(const QString &name)
{
    const QString path = m_dir->filePath(name);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write("not really a jpeg");
        file.close();
    }
    return path;
}

int TstMemories::addPhoto(const QString &name, int daysAgo)
{
    const QString path = makePhotoFile(name);
    return m_db->addPhoto(path, QDateTime::currentDateTime().addDays(-daysAgo),
                          4000, 3000);
}

Memory TstMemories::recipeMemory(const QString &title)
{
    Memory memory;
    memory.kind = "anniversary";
    memory.sourceKey = "2023";
    memory.title = title;
    memory.subtitle = "14 août 2023";
    memory.style = "sentimental";
    memory.sortDate = QDateTime::currentDateTime().addYears(-3);
    memory.score = 0.8;
    return memory;
}

void TstMemories::rerunningARecipeRefreshesInsteadOfDuplicating()
{
    const int first = addPhoto("a.jpg", 1);
    const int second = addPhoto("b.jpg", 2);

    const int id = m_db->upsertMemory(recipeMemory(), { first });
    QVERIFY(id > 0);

    // Same (kind, source_key): the recipe updates its own row
    const int again = m_db->upsertMemory(recipeMemory("Il y a 4 ans"), { first, second });
    QCOMPARE(again, id);

    const QVector<Memory> memories = m_db->getMemories();
    QCOMPARE(memories.size(), 1);
    QCOMPARE(memories.first().title, QStringLiteral("Il y a 4 ans"));
    QCOMPARE(memories.first().photoCount, 2);
}

void TstMemories::regenerationKeepsTheChoicesTheUserMade()
{
    const int photo = addPhoto("a.jpg", 1);
    const int id = m_db->upsertMemory(recipeMemory(), { photo });

    QVERIFY(m_db->setMemoryStyle(id, "bauhaus"));
    QVERIFY(m_db->setMemoryTrack(id, "chromatic"));
    QVERIFY(m_db->setMemoryCover(id, m_dir->filePath("a.jpg")));

    // A regeneration refreshes the title but must not undo any of that
    m_db->upsertMemory(recipeMemory("Refreshed"), { photo });

    const Memory memory = m_db->getMemory(id);
    QCOMPARE(memory.title, QStringLiteral("Refreshed"));
    QCOMPARE(memory.style, QStringLiteral("bauhaus"));
    QCOMPARE(memory.trackId, QStringLiteral("chromatic"));
    QCOMPARE(memory.coverPhoto, m_dir->filePath("a.jpg"));
    QVERIFY(!memory.edited);
}

void TstMemories::anEditedMemoryIsLeftAlone()
{
    const int first = addPhoto("a.jpg", 1);
    const int second = addPhoto("b.jpg", 2);
    const int id = m_db->upsertMemory(recipeMemory(), { first });

    // Renaming is the user taking ownership
    QVERIFY(m_db->renameMemory(id, "Notre été"));
    QVERIFY(m_db->getMemory(id).edited);

    m_db->upsertMemory(recipeMemory("Il y a 4 ans"), { first, second });

    const Memory memory = m_db->getMemory(id);
    QCOMPARE(memory.title, QStringLiteral("Notre été"));
    QCOMPARE(memory.photoCount, 1);
}

void TstMemories::coverFallsBackToTheFirstPhoto()
{
    const int first = addPhoto("a.jpg", 1);
    const int second = addPhoto("b.jpg", 2);
    const int id = m_db->upsertMemory(recipeMemory(), { first, second });

    // Nothing pinned: the card shows the photo the clip opens on
    QCOMPARE(m_db->getMemory(id).coverPhoto, m_dir->filePath("a.jpg"));

    QVERIFY(m_db->setMemoryCover(id, m_dir->filePath("b.jpg")));
    QCOMPARE(m_db->getMemory(id).coverPhoto, m_dir->filePath("b.jpg"));

    // Clearing it goes back to the automatic choice
    QVERIFY(m_db->setMemoryCover(id, QString()));
    QCOMPARE(m_db->getMemory(id).coverPhoto, m_dir->filePath("a.jpg"));
}

void TstMemories::excludingAPhotoKeepsItAroundToUndo()
{
    const int first = addPhoto("a.jpg", 1);
    const int second = addPhoto("b.jpg", 2);
    const int id = m_db->upsertMemory(recipeMemory(), { first, second });

    QVERIFY(m_db->setMemoryPhotoIncluded(id, second, false));

    QCOMPARE(m_db->getMemoryPhotos(id, true).size(), 1);
    QCOMPARE(m_db->getMemoryPhotos(id, false).size(), 2);
    QCOMPARE(m_db->getMemory(id).photoCount, 1);
    QVERIFY(m_db->getMemory(id).edited);

    QVERIFY(m_db->setMemoryPhotoIncluded(id, second, true));
    QCOMPARE(m_db->getMemoryPhotos(id, true).size(), 2);
}

void TstMemories::reorderPutsTheListedPhotosFirst()
{
    const int first = addPhoto("a.jpg", 1);
    const int second = addPhoto("b.jpg", 2);
    const int third = addPhoto("c.jpg", 3);
    const int id = m_db->upsertMemory(recipeMemory(), { first, second, third });

    // Only the last two are listed; the unlisted one keeps its relative
    // place after them, and an unknown id is ignored rather than fatal
    QVERIFY(m_db->reorderMemoryPhotos(id, { third, second, 9999 }));

    const QVector<MemoryPhoto> photos = m_db->getMemoryPhotos(id);
    QCOMPARE(photos.size(), 3);
    QCOMPARE(photos.at(0).photo.id, third);
    QCOMPARE(photos.at(1).photo.id, second);
    QCOMPARE(photos.at(2).photo.id, first);
    QVERIFY(m_db->getMemory(id).edited);
}

void TstMemories::aMemoryWithNoPhotosIsNotListed()
{
    const int photo = addPhoto("a.jpg", 1);
    const int id = m_db->upsertMemory(recipeMemory(), { photo });
    QCOMPARE(m_db->getMemories().size(), 1);

    // Every photo excluded: there is no story left to play
    QVERIFY(m_db->setMemoryPhotoIncluded(id, photo, false));
    QCOMPARE(m_db->getMemories().size(), 0);
}

void TstMemories::dismissedMemoriesAreHiddenButStillRegenerated()
{
    const int photo = addPhoto("a.jpg", 1);
    const int id = m_db->upsertMemory(recipeMemory(), { photo });

    QVERIFY(m_db->setMemoryDismissed(id, true));
    QCOMPARE(m_db->getMemories().size(), 0);
    QCOMPARE(m_db->getMemories(true).size(), 1);

    // The recipe sees the dismissed row and must not resurrect it
    m_db->upsertMemory(recipeMemory("Il y a 4 ans"), { photo });
    QCOMPARE(m_db->getMemories().size(), 0);
    QVERIFY(m_db->getMemory(id).dismissed);
}

void TstMemories::pruningAPhotoTakesItOutOfItsMemories()
{
    const int kept = addPhoto("kept.jpg", 1);
    const int gone = addPhoto("gone.jpg", 2);
    const int id = m_db->upsertMemory(recipeMemory(), { kept, gone });

    QVERIFY(QFile::remove(m_dir->filePath("gone.jpg")));
    QCOMPARE(m_db->removeMissingPhotos(), 1);

    const QVector<MemoryPhoto> photos = m_db->getMemoryPhotos(id);
    QCOMPARE(photos.size(), 1);
    QCOMPARE(photos.first().photo.id, kept);
}

void TstMemories::faceBoxesComeBackForTheWholeMemoryAtOnce()
{
    const int withFaces = addPhoto("people.jpg", 1);
    const int scenery = addPhoto("hills.jpg", 2);
    const int outside = addPhoto("elsewhere.jpg", 3);

    const FaceEmbedding embedding(1, 0.5f);
    m_db->addFace(withFaces, QRectF(0.10, 0.20, 0.12, 0.16), 0.95f, embedding);
    m_db->addFace(withFaces, QRectF(0.60, 0.22, 0.11, 0.15), 0.94f, embedding);
    // A face the user marked as not a face has no say in how a shot is framed
    const int ignored = m_db->addFace(withFaces, QRectF(0.9, 0.9, 0.05, 0.05),
                                      0.81f, embedding);
    m_db->setFaceIgnored(ignored, true);
    // And this one belongs to a photo that is not part of the memory
    m_db->addFace(outside, QRectF(0.4, 0.4, 0.1, 0.1), 0.93f, embedding);

    const int id = m_db->upsertMemory(recipeMemory(), { withFaces, scenery });
    QVERIFY(id > 0);

    const QHash<int, QVector<QRectF>> boxes = m_db->faceBoxesForMemory(id);

    QCOMPARE(boxes.value(withFaces).size(), 2);
    // A photo of nobody is simply absent rather than present and empty
    QVERIFY(!boxes.contains(scenery));
    QVERIFY(!boxes.contains(outside));
    QCOMPARE(boxes.value(withFaces).first(), QRectF(0.10, 0.20, 0.12, 0.16));
}

void TstMemories::photosOfPeopleTellTogetherFromAnyOfThem()
{
    const int marie = m_db->createPerson("Marie");
    const int paul = m_db->createPerson("Paul");
    const int lea = m_db->createPerson("Lea");

    const FaceEmbedding embedding(1, 0.5f);
    auto photoWith = [&](const QString &name, const QVector<int> &people) {
        const int photoId = addPhoto(name, 1);
        for (int i = 0; i < people.size(); i++) {
            m_db->addFace(photoId, QRectF(0.1 * (i + 1), 0.2, 0.1, 0.14),
                          0.95f, embedding, people.at(i));
        }
        return photoId;
    };

    photoWith("all-1.jpg", { marie, paul, lea });
    photoWith("all-2.jpg", { marie, paul, lea });
    photoWith("pair.jpg", { marie, paul });
    photoWith("lea.jpg", { lea });
    photoWith("nobody.jpg", {});

    const QVector<int> three = { marie, paul, lea };

    // Together: only the frames the whole group is actually in
    QCOMPARE(m_db->photosOfPeople(three, true).size(), 2);
    // Any of them: every photo one of them appears in, and none of the rest
    QCOMPARE(m_db->photosOfPeople(three, false).size(), 4);

    // With three or four people the two answers are worlds apart, which is
    // the whole reason the caller has to say which one it means
    QCOMPARE(m_db->photosOfPeople({ marie, paul }, true).size(), 3);
    QCOMPARE(m_db->photosOfPeople({ lea }, true).size(), 3);
    QCOMPARE(m_db->photosOfPeople({}, true).size(), 0);
}

QTEST_MAIN(TstMemories)
#include "tst_memories.moc"
