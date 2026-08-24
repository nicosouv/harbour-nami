#ifndef MEMORYGENERATOR_H
#define MEMORYGENERATOR_H

#include <QString>
#include <QDate>
#include <QVector>

class FaceDatabase;
struct MemoryCandidate;

/**
 * @brief Turns a gallery into memories worth showing
 *
 * Six recipes, each asking the database one question and materialising what
 * it finds through FaceDatabase::upsertMemory(), which is idempotent on
 * (kind, source_key). So this can run every day: it refreshes its own rows
 * rather than piling up duplicates, and it leaves alone anything the user
 * has edited or dismissed.
 *
 * ### Titles are not stored translated
 *
 * A memory's title lands in the database untranslated, as raw material:
 * "2023" for an anniversary, "2026-07" for a month, the trip or person name
 * where the title genuinely is user data. QML translates the computed ones
 * at display time (qml/js/memories.js).
 *
 * Baking "Il y a 3 ans" into the row instead would need translation
 * machinery on the C++ side that this project does not have, and, worse,
 * would freeze the title in whatever language was active the day the recipe
 * ran: the app has an in-app language override, and switching it would
 * leave every old memory speaking the previous language.
 */
class MemoryGenerator
{
public:
    explicit MemoryGenerator(FaceDatabase *database);

    /**
     * @brief Run every recipe
     *
     * @param force Skip the once-a-day throttle
     * @param today The day to generate for; injectable so tests do not
     *        depend on what the calendar says when they run
     * @return How many memories were created or refreshed
     */
    int generate(bool force = false, const QDate &today = QDate::currentDate());

    // Photos around today's date in previous years. Matching the exact day
    // almost never fires on a real gallery, which is why MemoriesPage has
    // always used a window.
    static const int kAnniversaryWindowDays = 10;

    // Below this a memory is a handful of photos and not a story
    static const int kMinPhotos = 5;

    // A day has to stand out from ordinary days to become an event. Eight
    // rather than twelve: on a gallery of a few thousand photos, twelve left
    // the home with a hero and almost nothing under it, and the emptiness
    // was a shortage of memories rather than a layout that failed to fill.
    static const int kEventMinPhotos = 8;

    // Someone has to be a regular presence before they get their own memory
    static const int kPersonMinPhotos = 12;
    static const int kDuoMinPhotos = 8;

    // A clip past this outstays its welcome, and every extra photo costs a
    // decode at render time
    static const int kMaxPhotos = 40;

    // Per run, for the recipes that would otherwise scale with the gallery:
    // fifty people means fifty person memories and a home nobody can read.
    // Six is what fills the strip without becoming that.
    static const int kMaxPerKind = 6;

    // Burst shots: keep one, drop the rest. Six frames of the same instant
    // make a clip stutter.
    static const int kBurstSeconds = 3;

private:
    // Trims candidates down to kMaxPhotos: drops bursts, then keeps the
    // best photo from each of kMaxPhotos equal slices of the time range, so
    // the result spans the whole memory instead of its busiest hour
    static QVector<int> selectPhotos(QVector<MemoryCandidate> candidates);

    // Shared tail of every recipe: bail out when there is too little, pick
    // the photos, write the row
    bool materialise(const QString &kind, const QString &sourceKey,
                     const QString &title, const QString &style,
                     double score, const QDateTime &sortDate,
                     QVector<MemoryCandidate> candidates);

    int generateAnniversaries(const QDate &today);
    int generateTrips();
    int generateEvents();
    int generatePeople(const QDate &today);
    int generateDuos();
    int generateLastMonth(const QDate &today);

    FaceDatabase *m_database;
    int m_created = 0;
};

#endif // MEMORYGENERATOR_H
