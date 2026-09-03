#include <QtTest>
#include <QColor>
#include <QImage>
#include <QTemporaryDir>

#include "cliprenderer.h"
#include "encoder.h"
#include "memoryexporter.h"

// Drawing the frames and choosing what to compress them with.
//
// Both halves are testable without a device precisely because neither knows
// anything about one: the renderer is a QPainter walking the same edit the
// player animates, and the choice of encoder is a decision about a set of
// names. What is left over, the GStreamer glue, is the part that can only
// be proved on the phone, and it is deliberately the smallest piece.
class TstClipExport : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();

    void framesAreTheShapeTheStyleAsks();
    void theLeadInHoldsTheOpeningFrame();
    void everyShotGetsItsTurn();
    void aTimeAlwaysGivesTheSameFrame();
    void aMissingPhotoDoesNotTakeTheClipDown();
    void titlesBecomeFilenames();

    void theBestPlayableCombinationWins();
    void musicBeatsCompatibility();
    void anUnparseableStreamIsNotWritten();
    void nothingAvailableIsSaidPlainly();
    void everyFallbackIsOfferedInOrder();

private:
    Clip twoShotClip() const;
    QColor centreOf(const QImage &frame) const;

    QTemporaryDir m_dir;
    QString m_red;
    QString m_blue;
};

void TstClipExport::initTestCase()
{
    QVERIFY(m_dir.isValid());

    m_red = m_dir.filePath(QStringLiteral("red.png"));
    m_blue = m_dir.filePath(QStringLiteral("blue.png"));

    QImage red(640, 360, QImage::Format_RGB32);
    red.fill(QColor(220, 30, 30));
    QVERIFY(red.save(m_red));

    QImage blue(640, 360, QImage::Format_RGB32);
    blue.fill(QColor(30, 40, 220));
    QVERIFY(blue.save(m_blue));
}

Clip TstClipExport::twoShotClip() const
{
    Clip clip;
    clip.aspect = 16.0 / 9.0;
    clip.durationMs = 4000;
    // The music starts half a second before the first cut
    clip.trackStartMs = 500;

    Shot first;
    first.filePath = m_red;
    first.startMs = 0;
    first.durationMs = 2000;
    first.transitionIn = Transition::Cut;
    first.transitionMs = 0;
    first.rectFrom = QRectF(0, 0, 1, 1);
    first.rectTo = QRectF(0, 0, 1, 1);

    Shot second = first;
    second.filePath = m_blue;
    second.startMs = 2000;

    clip.shots << first << second;
    return clip;
}

QColor TstClipExport::centreOf(const QImage &frame) const
{
    return QColor(frame.pixel(frame.width() / 2, frame.height() / 2));
}

void TstClipExport::framesAreTheShapeTheStyleAsks()
{
    QCOMPARE(MemoryExporter::frameSize(16.0 / 9.0), QSize(1280, 720));
    QCOMPARE(MemoryExporter::frameSize(4.0 / 3.0), QSize(960, 720));

    // Odd dimensions are what an H.264 encoder refuses, and it refuses them
    // at the point where a clip has already been drawn
    for (double aspect : { 16.0 / 9.0, 4.0 / 3.0, 1.0, 1.777, 0.5625 }) {
        const QSize size = MemoryExporter::frameSize(aspect);
        QCOMPARE(size.width() % 2, 0);
        QCOMPARE(size.height() % 2, 0);
    }

    // Nonsense falls back rather than producing a frame nothing can encode
    QCOMPARE(MemoryExporter::frameSize(0.0), QSize(1280, 720));
}

void TstClipExport::theLeadInHoldsTheOpeningFrame()
{
    ClipRenderer renderer(twoShotClip(), QSize(320, 180));

    // The file plays its track from the beginning; the opening frame is held
    // for as long as the preview would have skipped, so the cuts still land
    // on the beats without seeking the audio
    QCOMPARE(renderer.leadInMs(), qint64(500));
    QCOMPARE(renderer.durationMs(), qint64(4500));

    QCOMPARE(centreOf(renderer.frameAt(0)), QColor(220, 30, 30));
    QCOMPARE(centreOf(renderer.frameAt(499)), QColor(220, 30, 30));

    // 4500 ms at 25 fps, and the last partial frame still gets drawn
    QCOMPARE(renderer.frameCount(25), 113);
    QCOMPARE(renderer.frameCount(0), 0);
}

void TstClipExport::everyShotGetsItsTurn()
{
    ClipRenderer renderer(twoShotClip(), QSize(320, 180));

    QCOMPARE(centreOf(renderer.frameAt(500 + 1000)), QColor(220, 30, 30));
    QCOMPARE(centreOf(renderer.frameAt(500 + 3000)), QColor(30, 40, 220));

    // Past the end there is still a frame rather than nothing: a renderer
    // that returns a null image at the last moment is a file that ends in
    // a black flash
    const QImage last = renderer.frameAt(500 + 4000);
    QCOMPARE(last.size(), QSize(320, 180));
    QCOMPARE(centreOf(last), QColor(30, 40, 220));
}

void TstClipExport::aTimeAlwaysGivesTheSameFrame()
{
    ClipRenderer renderer(twoShotClip(), QSize(320, 180));

    const QImage first = renderer.frameAt(1200);
    // Two other shots in between, so anything the renderer caches has had
    // every chance to change the answer
    renderer.frameAt(3400);
    renderer.frameAt(0);
    const QImage again = renderer.frameAt(1200);

    QCOMPARE(first, again);
}

void TstClipExport::aMissingPhotoDoesNotTakeTheClipDown()
{
    Clip clip = twoShotClip();
    clip.shots[1].filePath = m_dir.filePath(QStringLiteral("deleted.png"));

    ClipRenderer renderer(clip, QSize(320, 180));

    const QImage frame = renderer.frameAt(500 + 3000);
    QCOMPARE(frame.size(), QSize(320, 180));
    // The ground it would have been drawn on, not a crash and not a frame
    // of whatever was there before
    QCOMPARE(centreOf(frame), QColor(0, 0, 0));
}

void TstClipExport::titlesBecomeFilenames()
{
    QCOMPARE(MemoryExporter::fileName(QStringLiteral("Rome")),
             QStringLiteral("Rome"));
    // A slash in a title is a title, not a directory
    QCOMPARE(MemoryExporter::fileName(QStringLiteral("Lea / Paul")),
             QStringLiteral("Lea Paul"));
    QCOMPARE(MemoryExporter::fileName(QStringLiteral("  ")),
             QStringLiteral("Nami"));
    // Accents survive: half the app's languages need them
    QCOMPARE(MemoryExporter::fileName(QString::fromUtf8("Été à Rome")),
             QString::fromUtf8("Été à Rome"));

    QVERIFY(MemoryExporter::fileName(QString(400, QLatin1Char('a'))).size() <= 60);
}

void TstClipExport::theBestPlayableCombinationWins()
{
    const QSet<QString> desktop = {
        QStringLiteral("x264enc"), QStringLiteral("h264parse"),
        QStringLiteral("mp4mux"), QStringLiteral("avenc_aac"),
        QStringLiteral("vp8enc"), QStringLiteral("webmmux"),
        QStringLiteral("vorbisenc"), QStringLiteral("theoraenc"),
        QStringLiteral("oggmux")
    };

    const EncoderChoice choice = Encoders::choose(desktop);
    QVERIFY(choice.isValid());
    QCOMPARE(choice.videoEncoder, QStringLiteral("x264enc"));
    QCOMPARE(choice.videoParser, QStringLiteral("h264parse"));
    QCOMPARE(choice.muxer, QStringLiteral("mp4mux"));
    QCOMPARE(choice.audioEncoder, QStringLiteral("avenc_aac"));
    QCOMPARE(choice.extension, QStringLiteral("mp4"));

    // The floor: what a device has if it has GStreamer at all, since the
    // encoder, the muxer and the audio all ship in gst-plugins-base
    const QSet<QString> bare = {
        QStringLiteral("theoraenc"), QStringLiteral("oggmux"),
        QStringLiteral("vorbisenc")
    };
    const EncoderChoice fallback = Encoders::choose(bare);
    QVERIFY(fallback.isValid());
    QCOMPARE(fallback.extension, QStringLiteral("ogv"));
    QVERIFY(fallback.hasAudio());
}

void TstClipExport::musicBeatsCompatibility()
{
    // H.264 is there and would give the more widely playable file, but
    // nothing on this device can encode the AAC that mp4 needs. A webm with
    // the music beats a silent mp4: the clip is photographs cut to a track.
    const QSet<QString> phone = {
        QStringLiteral("x264enc"), QStringLiteral("h264parse"),
        QStringLiteral("mp4mux"), QStringLiteral("vp8enc"),
        QStringLiteral("webmmux"), QStringLiteral("vorbisenc")
    };

    const EncoderChoice choice = Encoders::choose(phone);
    QVERIFY(choice.isValid());
    QCOMPARE(choice.videoEncoder, QStringLiteral("vp8enc"));
    QCOMPARE(choice.extension, QStringLiteral("webm"));
    QCOMPARE(choice.audioEncoder, QStringLiteral("vorbisenc"));

    // With no way at all to carry sound, a silent file still beats nothing
    const QSet<QString> mute = {
        QStringLiteral("x264enc"), QStringLiteral("h264parse"),
        QStringLiteral("mp4mux")
    };
    const EncoderChoice silent = Encoders::choose(mute);
    QVERIFY(silent.isValid());
    QVERIFY(!silent.hasAudio());
    QCOMPARE(silent.extension, QStringLiteral("mp4"));
}

void TstClipExport::anUnparseableStreamIsNotWritten()
{
    // mp4 and matroska both store H.264 with its codec_data out of band,
    // and h264parse is what produces that. Writing the file anyway would
    // produce something that plays nowhere.
    const QSet<QString> noParser = {
        QStringLiteral("x264enc"), QStringLiteral("mp4mux"),
        QStringLiteral("matroskamux"), QStringLiteral("vorbisenc")
    };

    QVERIFY(!Encoders::choose(noParser).isValid());
}

void TstClipExport::nothingAvailableIsSaidPlainly()
{
    QVERIFY(!Encoders::choose(QSet<QString>()).isValid());

    // A muxer with nothing to put in it, and an encoder with nowhere to put
    // its output, are both no answer at all
    QVERIFY(!Encoders::choose({ QStringLiteral("mp4mux") }).isValid());
    QVERIFY(!Encoders::choose({ QStringLiteral("vp8enc") }).isValid());

    // Every element the chooser can ever ask for is a name a caller can go
    // and look up, with no duplicates to look up twice
    const QStringList candidates = Encoders::candidates();
    QVERIFY(candidates.contains(QStringLiteral("x264enc")));
    QVERIFY(candidates.contains(QStringLiteral("webmmux")));
    QVERIFY(candidates.contains(QStringLiteral("vorbisenc")));
    QSet<QString> unique;
    for (const QString &name : candidates) {
        unique.insert(name);
    }
    QCOMPARE(candidates.size(), unique.size());
}

void TstClipExport::everyFallbackIsOfferedInOrder()
{
    // Being in the registry is not being usable: a hardware encoder that
    // only takes camera buffers is present, findable, and refuses the first
    // frame. So the caller gets the whole list and works down it.
    const QSet<QString> phone = {
        QStringLiteral("droidvenc"), QStringLiteral("h264parse"),
        QStringLiteral("mp4mux"), QStringLiteral("avenc_aac"),
        QStringLiteral("vp8enc"), QStringLiteral("webmmux"),
        QStringLiteral("theoraenc"), QStringLiteral("oggmux"),
        QStringLiteral("vorbisenc")
    };

    const QVector<EncoderChoice> ranked = Encoders::rank(phone);
    QVERIFY(ranked.size() >= 3);

    // The first is what choose() would have committed to on its own
    QCOMPARE(ranked.first().videoEncoder, Encoders::choose(phone).videoEncoder);
    QCOMPARE(ranked.first().videoEncoder, QStringLiteral("droidvenc"));

    QStringList encoders;
    for (const EncoderChoice &choice : ranked) {
        QVERIFY(choice.isValid());
        encoders << choice.videoEncoder;
    }
    // Everything that could work is still on the list behind it
    QVERIFY(encoders.contains(QStringLiteral("vp8enc")));
    QVERIFY(encoders.contains(QStringLiteral("theoraenc")));

    // Silent combinations come after every one that carries the music, so a
    // device falls back to a lesser codec before it falls back to no sound
    int firstSilent = ranked.size();
    for (int i = 0; i < ranked.size(); i++) {
        if (!ranked.at(i).hasAudio()) {
            firstSilent = i;
            break;
        }
    }
    for (int i = firstSilent; i < ranked.size(); i++) {
        QVERIFY(!ranked.at(i).hasAudio());
    }

    QVERIFY(Encoders::rank(QSet<QString>()).isEmpty());
}

QTEST_MAIN(TstClipExport)
#include "tst_clipexport.moc"
