#ifndef ENCODER_H
#define ENCODER_H

#include <QImage>
#include <QSet>
#include <QSize>
#include <QString>
#include <QVector>

/**
 * @brief Which elements a clip will actually be written with
 *
 * Decided from what the device has rather than from what the developer had.
 * A phone is not a workstation: the H.264 encoder everybody assumes is
 * present is patent-encumbered and routinely absent, and an export that
 * fails on the one device it was written for is not an export.
 */
struct EncoderChoice {
    QString videoEncoder;    // the element that compresses the frames
    QString videoOptions;    // properties, as gst-launch would write them
    QString videoParser;     // between encoder and muxer, may be empty
    QString audioEncoder;    // empty when nothing here can encode audio
    QString muxer;
    QString extension;       // what the file should be called

    bool isValid() const { return !videoEncoder.isEmpty() && !muxer.isEmpty(); }
    bool hasAudio() const { return !audioEncoder.isEmpty(); }
};

namespace Encoders {

/**
 * @brief Every element the choice could possibly want, so a caller can ask
 *        the registry about them in one go
 */
QStringList candidates();

/**
 * @brief The best combination that can be built out of `available`
 *
 * Ordered by what the resulting file is worth to somebody who receives it:
 * H.264 in mp4 plays everywhere, VP8 in webm nearly everywhere, and the
 * Theora fallback exists because its encoder and muxer ship in the same
 * GStreamer package as the audio plumbing every Sailfish device already
 * has, so there is always an answer.
 *
 * A combination that can carry the music beats one that cannot, even when
 * the second would produce a more widely playable file: this is a clip of
 * someone's photographs cut to a track, and silent it is a slideshow.
 *
 * Returns an invalid choice when nothing at all can be assembled.
 */
EncoderChoice choose(const QSet<QString> &available);

/**
 * @brief Every combination that could be assembled, best first
 *
 * The registry says an element exists. It does not say the element will
 * accept these frames: a hardware encoder that only takes buffers from the
 * camera is present, findable, and useless here, and it says so by failing
 * to negotiate once data starts flowing.
 *
 * So the caller gets the whole ranked list and works down it until a
 * pipeline actually runs, rather than betting the feature on the first name
 * that turned up.
 */
QVector<EncoderChoice> rank(const QSet<QString> &available);

}  // namespace Encoders

/**
 * @brief Frames in, a file out
 *
 * The interface exists so that the risky half of the export lives behind
 * one door. Everything upstream of it (composing the edit, drawing the
 * frames) is pure Qt and testable; everything device-specific is here.
 */
class Encoder
{
public:
    virtual ~Encoder() {}

    /**
     * @brief Start writing, with the combination the caller settled on
     *
     * `audioPath` may be empty, in which case the clip is silent. It is
     * played from its beginning: the renderer holds the opening frame for
     * the track's lead-in instead, which needs no seeking.
     *
     * Succeeding here only means the pipeline was built and started. An
     * element that will not accept these frames says so on the first push,
     * not before, which is why the caller keeps the ranked list.
     */
    virtual bool open(const QString &path, const QSize &size, int fps,
                      const QString &audioPath, const EncoderChoice &choice) = 0;

    /**
     * @brief Hand over the next frame, in order
     *
     * Blocks while the encoder is behind, which is what paces the render.
     */
    virtual bool writeFrame(const QImage &frame) = 0;

    /**
     * @brief Wind the music down over the last moment, as the player does
     *
     * 1.0 is full, 0.0 silent. Called as the clip approaches its end.
     */
    virtual void setAudioLevel(double level) = 0;

    /**
     * @brief Close the file. Nothing is playable until this returns true.
     */
    virtual bool finish() = 0;

    virtual QString errorString() const = 0;
};

#endif // ENCODER_H
