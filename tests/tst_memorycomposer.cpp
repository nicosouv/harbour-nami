// Unit tests for the edit decision list.
//
// The composer is the one piece of the clip feature with no pixels, no
// files and no database in it, which is why the decisions that actually
// shape a clip live there: where the cuts fall, which photos make it in,
// and where the camera looks. All of that is checkable here, on a machine
// with no audio and no gallery.
//
// The invariant that matters most is the last one in this file: the same
// input always composes the same edit. The preview and the export read this
// list separately, and a composer that drifted between two calls would make
// them disagree in a way neither could detect.

#include <QtTest>
#include <QRectF>
#include <QSize>
#include <QSet>
#include <QJsonDocument>
#include <QJsonObject>

#include "memorycomposer.h"
#include "memorystyle.h"
#include "beatgrid.h"

class TstMemoryComposer : public QObject
{
    Q_OBJECT

private slots:
    void anEvenGridLandsOnTheTempo();
    void aGridNeedsTwoBeatsToBeUsable();
    void theLastUsableBeatStopsAtTheSafeOut();
    void energyIsWhicheverSectionIsRunning();
    void aGridReadsBackFromItsJson();
    void aGridOutOfOrderIsSortedRatherThanTrusted();

    void everyStyleIsWellFormed();

    void shotsRunBackToBackWithNoGaps();
    void everyCutLandsOnABeat();
    void theClipStopsBeforeTheTrackDoes();
    void anEnergeticStyleCutsFasterThanASentimentalOne();
    void theEnergeticStyleHalvesItsShotsOnTheLoudParts();

    void allPhotosAreUsedWhenTheyFit();
    void tooManyPhotosAreSampledAcrossTheWholeMemory();
    void theFirstShotHasNothingToDissolveFrom();

    void theMoveEndsOnTheFace();
    void twoFacesAreBothKeptInFrame();
    void aFaceAtTheEdgeIsStillFramedInsideThePhoto();
    void cropsCarryTheOutputAspectRatio();
    void theMoveTightensExceptWhereAStyleSaysNot();

    void nothingComposesFromNoPhotos();
    void nothingComposesFromAnUnusableTrack();
    void composingTwiceGivesTheSameEdit();

private:
    static QVector<ComposerPhoto> photos(int count, const QVector<QRectF> &faces = {},
                                        const QSize &size = QSize(4000, 3000));
    static BeatGrid grid(qint64 durationMs = 60000, double bpm = 120.0);
};

QVector<ComposerPhoto> TstMemoryComposer::photos(int count, const QVector<QRectF> &faces,
                                                 const QSize &size)
{
    QVector<ComposerPhoto> result;
    for (int i = 0; i < count; i++) {
        ComposerPhoto photo;
        photo.filePath = QString("/photos/%1.jpg").arg(i);
        photo.size = size;
        photo.faces = faces;
        result.append(photo);
    }
    return result;
}

BeatGrid TstMemoryComposer::grid(qint64 durationMs, double bpm)
{
    return BeatGrid::even(QStringLiteral("test-track"), bpm, durationMs);
}

void TstMemoryComposer::anEvenGridLandsOnTheTempo()
{
    // 120 bpm is a beat every 500ms
    const BeatGrid beats = BeatGrid::even("track", 120.0, 10000);

    QVERIFY(beats.isValid());
    QCOMPARE(beats.beats.first(), qint64(0));
    QCOMPARE(beats.beats.at(1), qint64(500));
    QCOMPARE(beats.beats.last(), qint64(10000));
    QCOMPARE(beats.safeOutMs, qint64(10000));

    // Accumulated from the index, so a fractional interval does not drift.
    // 91 bpm is 659.34ms, which adding up would put the hundredth beat a
    // third of a second out.
    const BeatGrid odd = BeatGrid::even("track", 91.0, 120000);
    QVERIFY(odd.beats.size() > 100);
    QCOMPARE(odd.beats.at(100), qint64(100 * 60000.0 / 91.0));
}

void TstMemoryComposer::aGridNeedsTwoBeatsToBeUsable()
{
    QVERIFY(!BeatGrid().isValid());
    QVERIFY(!BeatGrid::even("track", 0.0, 10000).isValid());
    QVERIFY(!BeatGrid::even("track", 120.0, 0).isValid());
    // One beat defines no interval to cut on
    QVERIFY(!BeatGrid::even("track", 120.0, 100).isValid());
}

void TstMemoryComposer::theLastUsableBeatStopsAtTheSafeOut()
{
    BeatGrid beats = BeatGrid::even("track", 120.0, 10000);
    QCOMPARE(beats.lastUsableBeat(), beats.beats.size() - 1);

    // A track that fades out early: the beats past the fade are still beats,
    // but a shot must not still be running over them
    beats.safeOutMs = 2200;
    QCOMPARE(beats.beats.at(beats.lastUsableBeat()), qint64(2000));
}

void TstMemoryComposer::energyIsWhicheverSectionIsRunning()
{
    BeatGrid beats = BeatGrid::even("track", 120.0, 60000);
    beats.sections.append(BeatSection{ 1000, 0.2 });
    beats.sections.append(BeatSection{ 20000, 0.9 });
    beats.sections.append(BeatSection{ 40000, 0.4 });

    // Before anything is stated there is nothing to go on
    QCOMPARE(beats.energyAt(0), 0.0);
    QCOMPARE(beats.energyAt(1000), 0.2);
    QCOMPARE(beats.energyAt(19999), 0.2);
    QCOMPARE(beats.energyAt(20000), 0.9);
    QCOMPARE(beats.energyAt(50000), 0.4);
}

void TstMemoryComposer::aGridReadsBackFromItsJson()
{
    const QByteArray json = R"({
        "track_id": "sentimental",
        "bpm": 92.0,
        "beats": [340, 992, 1644, 2296],
        "sections": [{"t": 340, "energy": 0.2}, {"t": 1644, "energy": 0.8}],
        "safe_out_ms": 2296
    })";

    const BeatGrid beats = BeatGrid::fromJson(
        QJsonDocument::fromJson(json).object());

    QVERIFY(beats.isValid());
    QCOMPARE(beats.trackId, QStringLiteral("sentimental"));
    QCOMPARE(beats.bpm, 92.0);
    QCOMPARE(beats.beats.size(), 4);
    QCOMPARE(beats.beats.first(), qint64(340));
    QCOMPARE(beats.sections.size(), 2);
    QCOMPARE(beats.energyAt(2000), 0.8);
    QCOMPARE(beats.safeOutMs, qint64(2296));

    // The grid is written by a script nobody runs by hand, so a malformed
    // one has to be unusable rather than half-read
    QVERIFY(!BeatGrid::fromJson(QJsonObject()).isValid());
}

void TstMemoryComposer::aGridOutOfOrderIsSortedRatherThanTrusted()
{
    const QByteArray json = R"({
        "track_id": "t", "bpm": 120,
        "beats": [1500, 0, 1000, 500],
        "sections": [{"t": 1000, "energy": 0.9}, {"t": 0, "energy": 0.1}],
        "safe_out_ms": 1500
    })";

    const BeatGrid beats = BeatGrid::fromJson(QJsonDocument::fromJson(json).object());

    // Out of order, the composer would produce shots of negative length
    QCOMPARE(beats.beats, QVector<qint64>({ 0, 500, 1000, 1500 }));
    QCOMPARE(beats.energyAt(0), 0.1);
    QCOMPARE(beats.energyAt(1200), 0.9);
}

void TstMemoryComposer::everyStyleIsWellFormed()
{
    const QVector<MemoryStyle> styles = MemoryStyles::all();
    QCOMPARE(styles.size(), 4);

    QSet<QString> ids;
    for (const MemoryStyle &style : styles) {
        QVERIFY2(style.isValid(), qPrintable(style.id));
        QVERIFY2(!ids.contains(style.id), qPrintable("duplicate id " + style.id));
        ids.insert(style.id);

        QVERIFY2(style.beatsPerShot > 0, qPrintable(style.id));
        QVERIFY2(style.aspect > 0.0, qPrintable(style.id));
        QVERIFY2(style.zoomFrom >= 1.0 && style.zoomTo >= 1.0, qPrintable(style.id));
        // A style must compose something from a plain gallery and a plain
        // track, or it is a row nobody can pick
        QVERIFY2(!MemoryComposer::compose(photos(12), style, grid()).isEmpty(),
                 qPrintable(style.id));
    }

    // An unknown id must not silently behave like a real style
    QVERIFY(!MemoryStyles::byId("no-such-style").isValid());
    QVERIFY(MemoryStyles::byId(MemoryStyles::fallbackId()).isValid());
}

void TstMemoryComposer::shotsRunBackToBackWithNoGaps()
{
    const Clip clip = MemoryComposer::compose(photos(20),
                                              MemoryStyles::byId("sentimental"), grid());
    QVERIFY(clip.shots.size() > 1);
    QCOMPARE(clip.shots.first().startMs, qint64(0));

    for (int i = 1; i < clip.shots.size(); i++) {
        const Shot &previous = clip.shots.at(i - 1);
        // A gap would be a black frame in the middle of the clip; an overlap
        // would be two photos claiming the same moment
        QCOMPARE(clip.shots.at(i).startMs, previous.startMs + previous.durationMs);
        QVERIFY(previous.durationMs > 0);
    }

    const Shot &last = clip.shots.last();
    QCOMPARE(clip.durationMs, last.startMs + last.durationMs);
}

void TstMemoryComposer::everyCutLandsOnABeat()
{
    const BeatGrid beats = grid();
    const Clip clip = MemoryComposer::compose(photos(20),
                                              MemoryStyles::byId("energetic"), beats);
    QVERIFY(!clip.isEmpty());

    QSet<qint64> beatTimes;
    for (qint64 beat : beats.beats) {
        beatTimes.insert(beat - clip.trackStartMs);
    }

    // This is the whole reason the beat grid exists: a slideshow whose
    // changes land off the music reads as broken even to someone who could
    // not say why
    for (const Shot &shot : clip.shots) {
        QVERIFY2(beatTimes.contains(shot.startMs),
                 qPrintable(QString("shot starts at %1, which is not a beat")
                            .arg(shot.startMs)));
        QVERIFY2(beatTimes.contains(shot.startMs + shot.durationMs),
                 qPrintable(QString("shot ends at %1, which is not a beat")
                            .arg(shot.startMs + shot.durationMs)));
    }
}

void TstMemoryComposer::theClipStopsBeforeTheTrackDoes()
{
    const qint64 duration = 30000;
    const BeatGrid beats = grid(duration);
    // Far more photos than the track can hold
    const Clip clip = MemoryComposer::compose(photos(200),
                                              MemoryStyles::byId("energetic"), beats);

    QVERIFY(!clip.isEmpty());
    // A shot still running when the track has faded out looks like a mistake
    QVERIFY2(clip.trackStartMs + clip.durationMs <= beats.safeOutMs,
             qPrintable(QString("clip runs to %1, track is safe to %2")
                        .arg(clip.trackStartMs + clip.durationMs).arg(beats.safeOutMs)));
}

void TstMemoryComposer::anEnergeticStyleCutsFasterThanASentimentalOne()
{
    const Clip slow = MemoryComposer::compose(photos(40),
                                              MemoryStyles::byId("sentimental"), grid());
    const Clip fast = MemoryComposer::compose(photos(40),
                                              MemoryStyles::byId("energetic"), grid());

    // Same track, same photos: the style is the only difference, and it has
    // to be visible in the edit rather than only in the colour
    QVERIFY2(fast.shots.size() > slow.shots.size(),
             qPrintable(QString("energetic %1 shots, sentimental %2")
                        .arg(fast.shots.size()).arg(slow.shots.size())));
    QVERIFY(fast.shots.first().durationMs < slow.shots.first().durationMs);
}

void TstMemoryComposer::theEnergeticStyleHalvesItsShotsOnTheLoudParts()
{
    BeatGrid beats = grid();
    // Quiet until halfway, loud after
    beats.sections.append(BeatSection{ 0, 0.2 });
    beats.sections.append(BeatSection{ 30000, 0.9 });

    const Clip clip = MemoryComposer::compose(photos(120),
                                              MemoryStyles::byId("energetic"), beats);
    QVERIFY(clip.shots.size() > 4);

    qint64 quietTotal = 0;
    int quietCount = 0;
    qint64 loudTotal = 0;
    int loudCount = 0;
    for (const Shot &shot : clip.shots) {
        if (shot.startMs + clip.trackStartMs < 30000) {
            quietTotal += shot.durationMs;
            quietCount++;
        } else {
            loudTotal += shot.durationMs;
            loudCount++;
        }
    }
    QVERIFY(quietCount > 0 && loudCount > 0);

    // The clip should lift where the track does
    QVERIFY2(loudTotal / loudCount < quietTotal / quietCount,
             qPrintable(QString("loud shots average %1ms, quiet ones %2ms")
                        .arg(loudTotal / loudCount).arg(quietTotal / quietCount)));
}

void TstMemoryComposer::allPhotosAreUsedWhenTheyFit()
{
    // Eight photos into a minute at four beats each: room to spare
    const Clip clip = MemoryComposer::compose(photos(8),
                                              MemoryStyles::byId("sentimental"), grid());

    QCOMPARE(clip.shots.size(), 8);
    for (int i = 0; i < clip.shots.size(); i++) {
        QCOMPARE(clip.shots.at(i).photoIndex, i);
    }
}

void TstMemoryComposer::tooManyPhotosAreSampledAcrossTheWholeMemory()
{
    const Clip clip = MemoryComposer::compose(photos(200),
                                              MemoryStyles::byId("sentimental"), grid());
    QVERIFY(!clip.isEmpty());
    QVERIFY(clip.shots.size() < 200);

    // Taking the first N would give the opening of the memory and nothing
    // else, which for a fortnight's trip is one morning
    QCOMPARE(clip.shots.first().photoIndex, 0);
    QVERIFY2(clip.shots.last().photoIndex > 150,
             qPrintable(QString("the clip stops at photo %1 of 200")
                        .arg(clip.shots.last().photoIndex)));

    // And it never shows the same photo twice
    QSet<int> seen;
    for (const Shot &shot : clip.shots) {
        QVERIFY(!seen.contains(shot.photoIndex));
        seen.insert(shot.photoIndex);
    }
}

void TstMemoryComposer::theFirstShotHasNothingToDissolveFrom()
{
    const Clip clip = MemoryComposer::compose(photos(10),
                                              MemoryStyles::byId("sentimental"), grid());
    QVERIFY(clip.shots.size() > 1);

    // Dissolving in from nothing is a fade from black nobody asked for
    QCOMPARE(clip.shots.first().transitionIn, Transition::Cut);
    QCOMPARE(clip.shots.first().transitionMs, 0);
    QCOMPARE(clip.shots.at(1).transitionIn, Transition::Dissolve);
    QVERIFY(clip.shots.at(1).transitionMs > 0);
}

void TstMemoryComposer::theMoveEndsOnTheFace()
{
    // Someone high in a 4:3 frame, which a 16:9 crop has to trim somewhere.
    // Centred on the photo instead of on them, the crop would start at 0.146
    // and take the top of their head with it.
    const QRectF face(0.65, 0.12, 0.14, 0.18);
    const Clip clip = MemoryComposer::compose(photos(6, { face }),
                                              MemoryStyles::byId("sentimental"), grid());
    QVERIFY(!clip.isEmpty());

    // The whole box, not merely its centre: a crop 94% as wide as the photo
    // contains almost any centre, so containing one proves nothing
    for (const Shot &shot : clip.shots) {
        QVERIFY2(shot.rectTo.contains(face),
                 qPrintable(QString("rectTo %1,%2 %3x%4 cuts into the face")
                            .arg(shot.rectTo.x()).arg(shot.rectTo.y())
                            .arg(shot.rectTo.width()).arg(shot.rectTo.height())));
        QVERIFY2(shot.rectFrom.contains(face),
                 qPrintable(QString("rectFrom %1,%2 %3x%4 cuts into the face")
                            .arg(shot.rectFrom.x()).arg(shot.rectFrom.y())
                            .arg(shot.rectFrom.width()).arg(shot.rectFrom.height())));
    }
}

void TstMemoryComposer::twoFacesAreBothKeptInFrame()
{
    // A portrait photo, where a 16:9 crop keeps only 42% of the height and
    // the choice of which 42% is the entire framing decision
    const QRectF upper(0.30, 0.20, 0.16, 0.12);
    const QRectF lower(0.30, 0.55, 0.16, 0.12);
    const Clip clip = MemoryComposer::compose(
        photos(6, { upper, lower }, QSize(3000, 4000)),
        MemoryStyles::byId("sentimental"), grid());
    QVERIFY(!clip.isEmpty());

    // Framing one of two people and leaving the other out of frame entirely
    // is worse than framing neither tightly
    for (const Shot &shot : clip.shots) {
        QVERIFY2(shot.rectTo.contains(upper.center()),
                 qPrintable(QString("rectTo %1..%2 loses the upper face")
                            .arg(shot.rectTo.top()).arg(shot.rectTo.bottom())));
        QVERIFY2(shot.rectTo.contains(lower.center()),
                 qPrintable(QString("rectTo %1..%2 loses the lower face")
                            .arg(shot.rectTo.top()).arg(shot.rectTo.bottom())));
    }
}

void TstMemoryComposer::aFaceAtTheEdgeIsStillFramedInsideThePhoto()
{
    const QRectF corner(0.0, 0.0, 0.10, 0.13);
    const Clip clip = MemoryComposer::compose(photos(6, { corner }),
                                              MemoryStyles::byId("energetic"), grid());
    QVERIFY(!clip.isEmpty());

    for (const Shot &shot : clip.shots) {
        // A crop hanging off the edge renders as black bars down one side
        for (const QRectF &rect : { shot.rectFrom, shot.rectTo }) {
            QVERIFY2(rect.left() >= -1e-9 && rect.top() >= -1e-9
                     && rect.right() <= 1.0 + 1e-9 && rect.bottom() <= 1.0 + 1e-9,
                     qPrintable(QString("crop %1,%2 %3x%4 leaves the photo")
                                .arg(rect.x()).arg(rect.y())
                                .arg(rect.width()).arg(rect.height())));
        }
    }
}

void TstMemoryComposer::cropsCarryTheOutputAspectRatio()
{
    for (const MemoryStyle &style : MemoryStyles::all()) {
        const Clip clip = MemoryComposer::compose(photos(6), style, grid());
        QVERIFY(!clip.isEmpty());

        for (const Shot &shot : clip.shots) {
            // The photos are 4:3; a crop that is not the output shape would
            // be stretched or letterboxed by the renderer
            const double ratio = (shot.rectTo.width() * 4000.0)
                               / (shot.rectTo.height() * 3000.0);
            QVERIFY2(qAbs(ratio - style.aspect) < 1e-6,
                     qPrintable(QString("%1: crop ratio %2, expected %3")
                                .arg(style.id).arg(ratio).arg(style.aspect)));
        }
    }
}

void TstMemoryComposer::theMoveTightensExceptWhereAStyleSaysNot()
{
    const Clip moving = MemoryComposer::compose(photos(6),
                                                MemoryStyles::byId("sentimental"), grid());
    for (const Shot &shot : moving.shots) {
        // zoomTo above zoomFrom means the crop gets smaller: the camera
        // moves in over the shot
        QVERIFY(shot.rectTo.width() < shot.rectFrom.width());
    }

    // Bauhaus puts the photo on a fixed grid, and a drift would undo the one
    // thing the style is about
    const Clip still = MemoryComposer::compose(photos(6),
                                               MemoryStyles::byId("bauhaus"), grid());
    for (const Shot &shot : still.shots) {
        QCOMPARE(shot.rectFrom, shot.rectTo);
    }
}

void TstMemoryComposer::nothingComposesFromNoPhotos()
{
    QVERIFY(MemoryComposer::compose({}, MemoryStyles::byId("sentimental"), grid()).isEmpty());
}

void TstMemoryComposer::nothingComposesFromAnUnusableTrack()
{
    // No grid at all, and a track too short to hold one shot
    QVERIFY(MemoryComposer::compose(photos(10),
                                    MemoryStyles::byId("sentimental"),
                                    BeatGrid()).isEmpty());
    QVERIFY(MemoryComposer::compose(photos(10),
                                    MemoryStyles::byId("sentimental"),
                                    grid(900)).isEmpty());
    // And an unknown style composes nothing rather than something arbitrary
    QVERIFY(MemoryComposer::compose(photos(10),
                                    MemoryStyles::byId("no-such-style"),
                                    grid()).isEmpty());
}

void TstMemoryComposer::composingTwiceGivesTheSameEdit()
{
    const QVector<ComposerPhoto> input = photos(40, { QRectF(0.3, 0.2, 0.2, 0.25) });
    const MemoryStyle style = MemoryStyles::byId("polaroid");

    const Clip first = MemoryComposer::compose(input, style, grid());
    const Clip second = MemoryComposer::compose(input, style, grid());

    // The player and the renderer each compose their own copy. If these
    // could differ, the preview would be a promise the export does not keep,
    // and nothing in either would notice.
    QCOMPARE(first.shots.size(), second.shots.size());
    QCOMPARE(first.durationMs, second.durationMs);
    for (int i = 0; i < first.shots.size(); i++) {
        QCOMPARE(first.shots.at(i).photoIndex, second.shots.at(i).photoIndex);
        QCOMPARE(first.shots.at(i).startMs, second.shots.at(i).startMs);
        QCOMPARE(first.shots.at(i).durationMs, second.shots.at(i).durationMs);
        QCOMPARE(first.shots.at(i).rectFrom, second.shots.at(i).rectFrom);
        QCOMPARE(first.shots.at(i).rectTo, second.shots.at(i).rectTo);
    }
}

QTEST_MAIN(TstMemoryComposer)
#include "tst_memorycomposer.moc"
