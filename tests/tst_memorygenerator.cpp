// Unit tests for the six memory recipes. The date is injected rather than
// read from the clock: an anniversary recipe tested against "today" would
// pass in August and fail in December.
//
// The gallery each test builds is deliberately small and explicit, so what
// a recipe picked is readable from the test rather than from a debugger.

#include <QtTest>
#include <QTemporaryDir>
#include <QDateTime>
#include <QFile>

#include "facedatabase.h"
#include "memorygenerator.h"

class TstMemoryGenerator : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void anniversaryGroupsPreviousYearsSeparately();
    void anniversaryIgnoresThisYearAndDistantDates();
    void anActualAnniversaryOutranksANearMiss();
    void tripsBecomeMemoriesUnderTheirOwnName();
    void busyDaysBecomeEventsUnlessATripClaimedThem();
    void dismissedDaysStayDismissed();
    void aRegularFaceGetsTheirOwnMemory();
    void peopleWhoAppearTogetherGetAPair();
    void lastMonthIsSummarisedButNotTheCurrentOne();
    void tooFewPhotosProduceNothing();
    void aSecondRunChangesNothing();
    void theThrottleHoldsUntilTheNextDay();
    void titlesAreStoredUntranslated();
    void aLongMemoryIsSpreadAcrossItsWholeRange();
    void burstShotsCollapseToOneFrame();

private:
    int addPhoto(const QDateTime &taken, int personId = -1, int secondPersonId = -1);
    int addPerson(const QString &name);
    Memory memoryOf(const QString &kind, const QString &sourceKey);
    static QDate today();

    QTemporaryDir *m_dir = nullptr;
    FaceDatabase *m_db = nullptr;
    MemoryGenerator *m_generator = nullptr;
    int m_photoCounter = 0;
};

// A fixed "today" so every expectation below is arithmetic, not calendar
// luck. Mid-June, far from a year boundary, so the circular window does not
// quietly become the interesting case in tests that are not about it.
QDate TstMemoryGenerator::today()
{
    return QDate(2026, 6, 15);
}

void TstMemoryGenerator::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
    m_db = new FaceDatabase;
    QVERIFY(m_db->open(m_dir->filePath("test.db")));
    m_generator = new MemoryGenerator(m_db);
    m_photoCounter = 0;
}

void TstMemoryGenerator::cleanup()
{
    delete m_generator;
    m_generator = nullptr;
    m_db->close();
    delete m_db;
    m_db = nullptr;
    delete m_dir;
    m_dir = nullptr;
}

int TstMemoryGenerator::addPhoto(const QDateTime &taken, int personId, int secondPersonId)
{
    const QString path = m_dir->filePath(QString("photo-%1.jpg").arg(m_photoCounter++));
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write("not really a jpeg");
        file.close();
    }

    const int photoId = m_db->addPhoto(path, taken, 4000, 3000);

    // A recipe only cares that a face is there and whose it is, so a
    // one-element embedding is enough to make the row real
    const FaceEmbedding embedding(1, 0.5f);
    if (personId > 0) {
        m_db->addFace(photoId, QRectF(0.4, 0.3, 0.1, 0.1), 0.95f, embedding, personId);
    }
    if (secondPersonId > 0) {
        m_db->addFace(photoId, QRectF(0.6, 0.3, 0.1, 0.1), 0.95f, embedding, secondPersonId);
    }
    return photoId;
}

int TstMemoryGenerator::addPerson(const QString &name)
{
    return m_db->createPerson(name);
}

Memory TstMemoryGenerator::memoryOf(const QString &kind, const QString &sourceKey)
{
    for (const Memory &memory : m_db->getMemories(true)) {
        if (memory.kind == kind && memory.sourceKey == sourceKey) {
            return memory;
        }
    }
    return Memory();
}

void TstMemoryGenerator::anniversaryGroupsPreviousYearsSeparately()
{
    // Same mid-June week, two different years
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 14), QTime(10, i)));
        addPhoto(QDateTime(QDate(2021, 6, 17), QTime(10, i)));
    }

    QVERIFY(m_generator->generate(true, today()) > 0);

    const Memory y2023 = memoryOf("anniversary", "2023");
    const Memory y2021 = memoryOf("anniversary", "2021");

    QVERIFY2(y2023.id > 0, "2023 should have its own memory");
    QVERIFY2(y2021.id > 0, "2021 should have its own memory");
    QCOMPARE(y2023.photoCount, 6);
    QCOMPARE(y2021.photoCount, 6);
}

void TstMemoryGenerator::anniversaryIgnoresThisYearAndDistantDates()
{
    // This year: not a memory yet, it is the present
    for (int i = 0; i < 8; i++) {
        addPhoto(QDateTime(QDate(2026, 6, 14), QTime(10, i)));
    }
    // Previous year but months away from today
    for (int i = 0; i < 8; i++) {
        addPhoto(QDateTime(QDate(2024, 11, 3), QTime(10, i)));
    }

    m_generator->generate(true, today());

    QCOMPARE(memoryOf("anniversary", "2026").id, -1);
    QCOMPARE(memoryOf("anniversary", "2024").id, -1);
}

void TstMemoryGenerator::anActualAnniversaryOutranksANearMiss()
{
    // 2023: exactly today's date three years ago
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 15), QTime(10, i)));
    }
    // 2021: inside the window but a week off
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2021, 6, 8), QTime(10, i)));
    }

    m_generator->generate(true, today());

    const Memory onTheDay = memoryOf("anniversary", "2023");
    const Memory nearMiss = memoryOf("anniversary", "2021");

    QVERIFY(onTheDay.score > nearMiss.score);

    // And the ordering the home will use follows from it
    const QVector<Memory> all = m_db->getMemories();
    QVERIFY(!all.isEmpty());
    QCOMPARE(all.first().sourceKey, QStringLiteral("2023"));
}

void TstMemoryGenerator::tripsBecomeMemoriesUnderTheirOwnName()
{
    for (int i = 0; i < 4; i++) {
        addPhoto(QDateTime(QDate(2025, 4, 10), QTime(9, i)));
        addPhoto(QDateTime(QDate(2025, 4, 11), QTime(9, i)));
    }
    const int tripId = m_db->createTrip("Lisbonne", { "2025-04-10", "2025-04-11" });
    QVERIFY(tripId > 0);

    m_generator->generate(true, today());

    const Memory trip = memoryOf("trip", QString::number(tripId));
    QVERIFY(trip.id > 0);
    // The user named this one, so the title is theirs, verbatim
    QCOMPARE(trip.title, QStringLiteral("Lisbonne"));
    QCOMPARE(trip.photoCount, 8);
    QCOMPARE(trip.style, QStringLiteral("energetic"));
}

void TstMemoryGenerator::busyDaysBecomeEventsUnlessATripClaimedThem()
{
    // An ordinary busy day
    for (int i = 0; i < 14; i++) {
        addPhoto(QDateTime(QDate(2025, 9, 20), QTime(11, i)));
    }
    // Another one, but grouped into a trip: it belongs to the trip's memory
    for (int i = 0; i < 14; i++) {
        addPhoto(QDateTime(QDate(2025, 3, 5), QTime(11, i)));
    }
    m_db->createTrip("Rome", { "2025-03-05" });

    m_generator->generate(true, today());

    QVERIFY(memoryOf("event", "2025-09-20").id > 0);
    QCOMPARE(memoryOf("event", "2025-03-05").id, -1);
}

void TstMemoryGenerator::dismissedDaysStayDismissed()
{
    for (int i = 0; i < 14; i++) {
        addPhoto(QDateTime(QDate(2025, 9, 20), QTime(11, i)));
    }
    // The user already threw this day out of the Events list
    QVERIFY(m_db->hideEvent("day:2025-09-20"));

    m_generator->generate(true, today());

    QCOMPARE(memoryOf("event", "2025-09-20").id, -1);
}

void TstMemoryGenerator::aRegularFaceGetsTheirOwnMemory()
{
    const int marie = addPerson("Marie");
    const int passerby = addPerson("Passerby");

    for (int i = 0; i < 14; i++) {
        addPhoto(QDateTime(QDate(2026, 2, 10), QTime(12, i)), marie);
    }
    // Two photos is not a presence
    for (int i = 0; i < 2; i++) {
        addPhoto(QDateTime(QDate(2026, 2, 10), QTime(15, i)), passerby);
    }

    m_generator->generate(true, today());

    const Memory hers = memoryOf("person", QString::number(marie));
    QVERIFY(hers.id > 0);
    QCOMPARE(hers.title, QStringLiteral("Marie"));
    QCOMPARE(memoryOf("person", QString::number(passerby)).id, -1);
}

void TstMemoryGenerator::peopleWhoAppearTogetherGetAPair()
{
    const int marie = addPerson("Marie");
    const int paul = addPerson("Paul");

    for (int i = 0; i < 10; i++) {
        addPhoto(QDateTime(QDate(2025, 7, 4), QTime(13, i)), marie, paul);
    }

    m_generator->generate(true, today());

    const Memory duo = memoryOf("duo", QString("%1-%2").arg(marie).arg(paul));
    QVERIFY(duo.id > 0);
    QCOMPARE(duo.title, QStringLiteral("Marie & Paul"));
    QCOMPARE(duo.photoCount, 10);
}

void TstMemoryGenerator::lastMonthIsSummarisedButNotTheCurrentOne()
{
    for (int i = 0; i < 8; i++) {
        addPhoto(QDateTime(QDate(2026, 5, 12), QTime(14, i)));   // last month
        addPhoto(QDateTime(QDate(2026, 6, 2), QTime(14, i)));    // this month
    }

    m_generator->generate(true, today());

    QVERIFY(memoryOf("month", "2026-05").id > 0);
    // The current month is still being lived in, and regenerating it daily
    // over a moving photo set would never settle
    QCOMPARE(memoryOf("month", "2026-06").id, -1);
}

void TstMemoryGenerator::tooFewPhotosProduceNothing()
{
    // Four photos on a perfect anniversary: still not a story
    for (int i = 0; i < 4; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 15), QTime(10, i)));
    }

    m_generator->generate(true, today());

    QCOMPARE(m_db->getMemories(true).size(), 0);
}

void TstMemoryGenerator::aSecondRunChangesNothing()
{
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 14), QTime(10, i)));
    }

    m_generator->generate(true, today());
    const int afterFirst = m_db->getMemories(true).size();
    QVERIFY(afterFirst > 0);

    // Forced, so the throttle is not what is being tested here: the recipes
    // must be idempotent on their own
    m_generator->generate(true, today());
    QCOMPARE(m_db->getMemories(true).size(), afterFirst);
}

void TstMemoryGenerator::theThrottleHoldsUntilTheNextDay()
{
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 14), QTime(10, i)));
    }

    QVERIFY(m_generator->generate(false, today()) > 0);
    // Same day again: the recipes must not even run
    QCOMPARE(m_generator->generate(false, today()), 0);
    // Tomorrow they may
    QVERIFY(m_generator->generate(false, today().addDays(1)) > 0);
}

void TstMemoryGenerator::titlesAreStoredUntranslated()
{
    for (int i = 0; i < 6; i++) {
        addPhoto(QDateTime(QDate(2023, 6, 14), QTime(10, i)));
        addPhoto(QDateTime(QDate(2026, 5, 12), QTime(14, i)));
    }

    m_generator->generate(true, today());

    // Raw material for QML to translate at display time, never a rendered
    // phrase: a stored "3 years ago" would be stuck in whatever language was
    // active the day the recipe ran, and the app lets the user change it
    QCOMPARE(memoryOf("anniversary", "2023").title, QStringLiteral("2023"));
    QCOMPARE(memoryOf("month", "2026-05").title, QStringLiteral("2026-05"));
}

void TstMemoryGenerator::aLongMemoryIsSpreadAcrossItsWholeRange()
{
    // A fortnight, heavily front-loaded: 100 photos on the first day and a
    // handful on each of the rest. Taking the first forty would hand back a
    // clip of one morning.
    for (int i = 0; i < 100; i++) {
        addPhoto(QDateTime(QDate(2025, 4, 1), QTime(9, 0)).addSecs(i * 60));
    }
    QStringList dates = { "2025-04-01" };
    for (int day = 2; day <= 14; day++) {
        const QDate date(2025, 4, day);
        dates << date.toString(Qt::ISODate);
        for (int i = 0; i < 3; i++) {
            addPhoto(QDateTime(date, QTime(12, 0)).addSecs(i * 600));
        }
    }

    const int tripId = m_db->createTrip("Fortnight", dates);
    m_generator->generate(true, today());

    const Memory trip = memoryOf("trip", QString::number(tripId));
    QVERIFY(trip.id > 0);
    QCOMPARE(trip.photoCount, MemoryGenerator::kMaxPhotos);

    const QVector<MemoryPhoto> photos = m_db->getMemoryPhotos(trip.id);
    const QDate firstDay = photos.first().photo.dateTaken.date();
    const QDate lastDay = photos.last().photo.dateTaken.date();

    QCOMPARE(firstDay, QDate(2025, 4, 1));
    QCOMPARE(lastDay, QDate(2025, 4, 14));

    // And the first day, which holds 100 of the 139 candidates, must not
    // have swallowed the selection
    int fromFirstDay = 0;
    for (const MemoryPhoto &entry : photos) {
        if (entry.photo.dateTaken.date() == firstDay) {
            fromFirstDay++;
        }
    }
    QVERIFY2(fromFirstDay < MemoryGenerator::kMaxPhotos / 2,
             qPrintable(QString("%1 of %2 photos came from the first day")
                        .arg(fromFirstDay).arg(photos.size())));
}

void TstMemoryGenerator::burstShotsCollapseToOneFrame()
{
    const QDateTime start(QDate(2025, 8, 1), QTime(10, 0));

    // Six frames of one instant, 300ms apart, then five real moments.
    // "One instant" means inside kBurstSeconds: frames spread over more
    // than that are several moments and are meant to survive as several.
    for (int i = 0; i < 6; i++) {
        addPhoto(start.addMSecs(i * 300));
    }
    for (int i = 1; i <= 5; i++) {
        addPhoto(start.addSecs(i * 3600));
    }

    m_db->createTrip("Burst", { "2025-08-01" });
    m_generator->generate(true, today());

    const Memory trip = memoryOf("trip", "1");
    QVERIFY(trip.id > 0);
    // The burst counts once: six near-identical frames make a clip stutter
    // in place rather than tell six seconds of story
    QCOMPARE(trip.photoCount, 6);
}

QTEST_MAIN(TstMemoryGenerator)
#include "tst_memorygenerator.moc"
