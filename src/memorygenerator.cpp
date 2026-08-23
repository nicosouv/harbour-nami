#include "memorygenerator.h"
#include "facedatabase.h"
#include "logging.h"

#include <QDateTime>
#include <QSet>
#include <QHash>
#include <QMap>
#include <algorithm>

namespace {

// Which style a recipe opens on. Only a default: the user picks their own
// on the memory page, and a regeneration never overwrites that choice.
//
// The split is by what the memory is about rather than by taste. Recipes
// built around people (an anniversary, someone's year, a pair) get the slow
// sentimental cut; recipes built around activity (a trip, a busy day) get
// the energetic one; the monthly round-up is a survey rather than a story,
// so it gets the graphic treatment.
QString defaultStyleFor(const QString &kind)
{
    if (kind == QLatin1String("trip") || kind == QLatin1String("event")) {
        return QStringLiteral("energetic");
    }
    if (kind == QLatin1String("month")) {
        return QStringLiteral("bauhaus");
    }
    return QStringLiteral("sentimental");
}

// More photos means a fuller story, but with sharply diminishing returns:
// forty photos is not four times the memory that ten is
double volumeBonus(int photoCount)
{
    return 0.10 * qMin(1.0, photoCount / 20.0);
}

}  // namespace

MemoryGenerator::MemoryGenerator(FaceDatabase *database)
    : m_database(database)
{
}

int MemoryGenerator::generate(bool force, const QDate &today)
{
    if (!m_database) {
        return 0;
    }

    // Once a day is enough: nothing a recipe looks at changes faster than
    // the gallery is scanned, and each run walks a good part of it
    const QString todayKey = today.toString(Qt::ISODate);
    if (!force && m_database->getSetting("memories_generated_on") == todayKey) {
        return 0;
    }

    m_created = 0;

    generateAnniversaries(today);
    generateTrips();
    generateEvents();
    generatePeople(today);
    generateDuos();
    generateLastMonth(today);

    m_database->setSetting("memories_generated_on", todayKey);

    qCDebug(lcNami) << "Memory recipes produced" << m_created << "memories";
    return m_created;
}

QVector<int> MemoryGenerator::selectPhotos(QVector<MemoryCandidate> candidates)
{
    QVector<int> chosen;
    if (candidates.isEmpty()) {
        return chosen;
    }

    std::sort(candidates.begin(), candidates.end(),
              [](const MemoryCandidate &a, const MemoryCandidate &b) {
                  return a.dateTaken < b.dateTaken;
              });

    // Bursts first: six frames of the same instant are one moment, and
    // keeping them all makes the clip stutter in place
    QVector<MemoryCandidate> deduped;
    for (const MemoryCandidate &candidate : candidates) {
        if (!deduped.isEmpty()
                && deduped.last().dateTaken.secsTo(candidate.dateTaken) < kBurstSeconds) {
            // Within a burst, keep whichever frame has more known faces
            if (candidate.faceCount > deduped.last().faceCount) {
                deduped.last() = candidate;
            }
            continue;
        }
        deduped.append(candidate);
    }

    if (deduped.size() <= kMaxPhotos) {
        for (const MemoryCandidate &candidate : deduped) {
            chosen.append(candidate.photoId);
        }
        return chosen;
    }

    // Slice the memory's time range into kMaxPhotos equal buckets, then take
    // one photo from each in turn, round after round, until the clip is
    // full. Taking the first forty, or simply the forty with the most faces,
    // would hand back one afternoon of a two-week trip.
    //
    // Round-robin rather than proportional sampling is the point: a day
    // holding a hundred photos out of a hundred and forty would otherwise
    // fill three quarters of the clip on its own. It has more to show than
    // a quiet day, not thirty times more.
    const qint64 from = deduped.first().dateTaken.toMSecsSinceEpoch();
    const qint64 to = deduped.last().dateTaken.toMSecsSinceEpoch();
    const qint64 span = qMax<qint64>(1, to - from);

    QMap<int, QVector<MemoryCandidate>> buckets;
    for (const MemoryCandidate &candidate : deduped) {
        const qint64 offset = candidate.dateTaken.toMSecsSinceEpoch() - from;
        const int bucket = qMin(int(kMaxPhotos - 1), int((offset * kMaxPhotos) / span));
        buckets[bucket].append(candidate);
    }

    // Within a bucket, photos of people come first: if only some of a
    // moment makes the cut, it should be the part with someone in it
    for (auto it = buckets.begin(); it != buckets.end(); ++it) {
        std::stable_sort(it->begin(), it->end(),
                         [](const MemoryCandidate &a, const MemoryCandidate &b) {
                             return a.faceCount > b.faceCount;
                         });
    }

    QVector<MemoryCandidate> picked;
    for (int round = 0; picked.size() < kMaxPhotos; round++) {
        bool tookAny = false;
        for (auto it = buckets.constBegin();
             it != buckets.constEnd() && picked.size() < kMaxPhotos; ++it) {
            if (round < it->size()) {
                picked.append(it->at(round));
                tookAny = true;
            }
        }
        if (!tookAny) {
            break;  // every bucket is exhausted
        }
    }

    std::sort(picked.begin(), picked.end(),
              [](const MemoryCandidate &a, const MemoryCandidate &b) {
                  return a.dateTaken < b.dateTaken;
              });

    for (const MemoryCandidate &candidate : picked) {
        chosen.append(candidate.photoId);
    }
    return chosen;
}

bool MemoryGenerator::materialise(const QString &kind, const QString &sourceKey,
                                  const QString &title, const QString &style,
                                  double score, const QDateTime &sortDate,
                                  QVector<MemoryCandidate> candidates)
{
    if (candidates.size() < kMinPhotos || title.trimmed().isEmpty()) {
        return false;
    }

    const QVector<int> photoIds = selectPhotos(candidates);
    if (photoIds.size() < kMinPhotos) {
        return false;
    }

    Memory memory;
    memory.kind = kind;
    memory.sourceKey = sourceKey;
    memory.title = title;
    memory.style = style;
    memory.sortDate = sortDate;
    memory.score = qBound(0.0, score + volumeBonus(photoIds.size()), 1.0);

    if (m_database->upsertMemory(memory, photoIds) > 0) {
        m_created++;
        return true;
    }
    return false;
}

int MemoryGenerator::generateAnniversaries(const QDate &today)
{
    // The window is circular, so it is built as a list of "MM-dd" keys
    // rather than as a date range: 30 December is three days from 2 January
    QStringList monthDays;
    for (int offset = -kAnniversaryWindowDays; offset <= kAnniversaryWindowDays; offset++) {
        monthDays << today.addDays(offset).toString(QStringLiteral("MM-dd"));
    }

    const QVector<MemoryCandidate> candidates =
        m_database->photosOnMonthDays(monthDays, today.year());

    QHash<int, QVector<MemoryCandidate>> byYear;
    for (const MemoryCandidate &candidate : candidates) {
        byYear[candidate.dateTaken.date().year()].append(candidate);
    }

    int made = 0;
    for (auto it = byYear.constBegin(); it != byYear.constEnd(); ++it) {
        const int year = it.key();
        const QVector<MemoryCandidate> &photos = it.value();

        // How close the closest photo falls to today, ignoring the year:
        // an actual anniversary leads the home, a near miss does not
        int closest = kAnniversaryWindowDays;
        for (const MemoryCandidate &candidate : photos) {
            const QDate date = candidate.dateTaken.date();
            const QDate sameYear(today.year(), date.month(), date.day());
            if (sameYear.isValid()) {
                closest = qMin(closest, int(qAbs(sameYear.daysTo(today))));
            }
        }

        const double score = 0.70 + (closest <= 2 ? 0.10 : 0.0);

        if (materialise(QStringLiteral("anniversary"), QString::number(year),
                        QString::number(year), defaultStyleFor("anniversary"),
                        score, photos.first().dateTaken, photos)) {
            made++;
        }
    }
    return made;
}

int MemoryGenerator::generateTrips()
{
    int made = 0;
    for (const Trip &trip : m_database->getAllTrips()) {
        const QVector<MemoryCandidate> photos = m_database->photosOnDates(trip.dateKeys);
        if (photos.isEmpty()) {
            continue;
        }

        // The trip name is the user's own words, so it is the one title that
        // needs no translating at display time
        if (materialise(QStringLiteral("trip"), QString::number(trip.id),
                        trip.name, defaultStyleFor("trip"),
                        0.65, photos.first().dateTaken, photos)) {
            made++;
        }
    }
    return made;
}

int MemoryGenerator::generateEvents()
{
    // Days already grouped into a trip belong to that trip's memory, and
    // days the user dismissed from the Events list stay dismissed here too
    QSet<QString> claimed;
    for (const Trip &trip : m_database->getAllTrips()) {
        for (const QString &dateKey : trip.dateKeys) {
            claimed.insert(dateKey);
        }
    }
    for (const QString &eventKey : m_database->getHiddenEvents()) {
        if (eventKey.startsWith(QLatin1String("day:"))) {
            claimed.insert(eventKey.mid(4));
        }
    }

    int made = 0;
    const auto days = m_database->busiestDays(kEventMinPhotos, kMaxPerKind * 4);

    for (const auto &day : days) {
        if (made >= kMaxPerKind) {
            break;
        }
        if (claimed.contains(day.first)) {
            continue;
        }

        const QVector<MemoryCandidate> photos = m_database->photosOnDates({ day.first });
        if (photos.isEmpty()) {
            continue;
        }

        if (materialise(QStringLiteral("event"), day.first, day.first,
                        defaultStyleFor("event"), 0.50,
                        photos.first().dateTaken, photos)) {
            made++;
        }
    }
    return made;
}

int MemoryGenerator::generatePeople(const QDate &today)
{
    // A year back: someone's memory should be who they have been lately,
    // not a greatest-hits reaching into a decade of photos
    const QDateTime since(today.addYears(-1), QTime(0, 0));

    QVector<QPair<Person, QVector<MemoryCandidate>>> ranked;
    for (const Person &person : m_database->getAllPeople()) {
        const QVector<MemoryCandidate> photos = m_database->photosOfPerson(person.id, since);
        if (photos.size() >= kPersonMinPhotos) {
            ranked.append(qMakePair(person, photos));
        }
    }

    std::sort(ranked.begin(), ranked.end(),
              [](const QPair<Person, QVector<MemoryCandidate>> &a,
                 const QPair<Person, QVector<MemoryCandidate>> &b) {
                  return a.second.size() > b.second.size();
              });

    int made = 0;
    for (const auto &entry : ranked) {
        if (made >= kMaxPerKind) {
            break;
        }
        if (materialise(QStringLiteral("person"), QString::number(entry.first.id),
                        entry.first.name, defaultStyleFor("person"),
                        0.40, entry.second.last().dateTaken, entry.second)) {
            made++;
        }
    }
    return made;
}

int MemoryGenerator::generateDuos()
{
    int made = 0;
    for (const PeoplePair &pair : m_database->peopleSeenTogether(kDuoMinPhotos, kMaxPerKind * 3)) {
        if (made >= kMaxPerKind) {
            break;
        }

        const Person a = m_database->getPerson(pair.personA);
        const Person b = m_database->getPerson(pair.personB);
        if (a.name.trimmed().isEmpty() || b.name.trimmed().isEmpty()) {
            continue;
        }

        const QVector<MemoryCandidate> photos =
            m_database->photosOfPeoplePair(pair.personA, pair.personB);
        if (photos.isEmpty()) {
            continue;
        }

        // Two names joined by an ampersand reads the same in every locale
        // this app ships, so the title stays user data
        const QString title = QStringLiteral("%1 & %2").arg(a.name, b.name);
        const QString sourceKey = QStringLiteral("%1-%2").arg(pair.personA).arg(pair.personB);

        if (materialise(QStringLiteral("duo"), sourceKey, title, defaultStyleFor("duo"),
                        0.45, photos.last().dateTaken, photos)) {
            made++;
        }
    }
    return made;
}

int MemoryGenerator::generateLastMonth(const QDate &today)
{
    // The month that has just ended, never the current one: a month still
    // running would be regenerated every day on a moving photo set
    const QDate lastMonth = today.addMonths(-1);

    const QVector<MemoryCandidate> photos =
        m_database->photosInMonth(lastMonth.year(), lastMonth.month());
    if (photos.isEmpty()) {
        return 0;
    }

    const QString sourceKey = QStringLiteral("%1-%2")
        .arg(lastMonth.year(), 4, 10, QChar('0'))
        .arg(lastMonth.month(), 2, 10, QChar('0'));

    return materialise(QStringLiteral("month"), sourceKey, sourceKey,
                       defaultStyleFor("month"), 0.35,
                       photos.first().dateTaken, photos) ? 1 : 0;
}
