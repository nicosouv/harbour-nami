#include "encoder.h"

#include <QStringList>

namespace {

struct VideoCandidate {
    const char *element;
    const char *codec;
    const char *options;
};

// Software first, deliberately.
//
// A hardware encoder would be several times faster, and on a phone that is
// not nothing. But it is also the part most likely to refuse the buffers we
// hand it, on a device that cannot be tested from here, and a clip that
// takes two minutes to write beats a clip that cannot be written at all.
// The element that was actually used is logged, so the day a device proves
// its hardware path works, this order is one line to change.
const VideoCandidate kVideo[] = {
    { "x264enc",     "h264",   "speed-preset=veryfast" },
    { "openh264enc", "h264",   "" },
    { "omxh264enc",  "h264",   "" },
    { "droidvenc",   "h264",   "" },
    { "v4l2h264enc", "h264",   "" },
    // MPEG-4 part 2, from gst-libav. Older and less efficient than H.264,
    // but it goes into an mp4 next to AAC and plays on anything that plays
    // video, which is worth more to somebody sending a clip to a friend
    // than a better codec in a container half the world cannot open.
    { "avenc_mpeg4", "mpeg4",  "bitrate=4000000" },
    { "vp8enc",      "vp8",    "deadline=1 cpu-used=8" },
    { "theoraenc",   "theora", "quality=40" },
    { "jpegenc",     "mjpeg",  "quality=88" },
};

struct Container {
    const char *codec;
    const char *muxer;
    const char *extension;
    const char *parser;   // empty when the muxer takes the encoder's output
};

// Per codec, in the order a file is worth receiving in
const Container kContainers[] = {
    // Both of these store H.264 as AVC with its codec_data out of band, and
    // the parser is what produces that from whatever the encoder emitted.
    // Without it the file is written and does not play, which is worse than
    // falling through to VP8.
    { "h264",   "mp4mux",      "mp4",  "h264parse" },
    { "h264",   "matroskamux", "mkv",  "h264parse" },
    // mp4mux takes an MPEG-4 elementary stream as the encoder emits it, so
    // there is no parser to be missing here
    { "mpeg4",  "mp4mux",      "mp4",  "" },
    { "mpeg4",  "matroskamux", "mkv",  "" },
    { "vp8",    "webmmux",     "webm", "" },
    { "vp8",    "matroskamux", "mkv",  "" },
    { "theora", "oggmux",      "ogv",  "" },
    { "theora", "matroskamux", "mkv",  "" },
    { "mjpeg",  "matroskamux", "mkv",  "" },
    { "mjpeg",  "avimux",      "avi",  "" },
};

struct AudioOption {
    const char *muxer;
    const char *element;
};

// Ordered per muxer. mp4 is the odd one: it only really carries AAC, and an
// AAC encoder is exactly the thing a phone distribution leaves out.
const AudioOption kAudio[] = {
    { "mp4mux",      "avenc_aac" },
    { "mp4mux",      "voaacenc" },
    { "mp4mux",      "faac" },
    { "matroskamux", "vorbisenc" },
    { "matroskamux", "opusenc" },
    { "matroskamux", "avenc_aac" },
    { "webmmux",     "vorbisenc" },
    { "webmmux",     "opusenc" },
    { "oggmux",      "vorbisenc" },
    { "oggmux",      "opusenc" },
};

QString audioFor(const QString &muxer, const QSet<QString> &available)
{
    for (const AudioOption &option : kAudio) {
        if (muxer == QLatin1String(option.muxer)
                && available.contains(QLatin1String(option.element))) {
            return QLatin1String(option.element);
        }
    }
    return QString();
}

}  // namespace

QStringList Encoders::candidates()
{
    QStringList names;
    for (const VideoCandidate &candidate : kVideo) {
        names << QLatin1String(candidate.element);
    }
    for (const Container &container : kContainers) {
        names << QLatin1String(container.muxer);
        if (container.parser[0] != '\0') {
            names << QLatin1String(container.parser);
        }
    }
    for (const AudioOption &option : kAudio) {
        names << QLatin1String(option.element);
    }
    names.removeDuplicates();
    return names;
}

EncoderChoice Encoders::choose(const QSet<QString> &available)
{
    const QVector<EncoderChoice> ranked = rank(available);
    return ranked.isEmpty() ? EncoderChoice() : ranked.first();
}

QVector<EncoderChoice> Encoders::rank(const QSet<QString> &available)
{
    QVector<EncoderChoice> withAudio;
    QVector<EncoderChoice> silent;

    for (const VideoCandidate &candidate : kVideo) {
        const QString encoder = QLatin1String(candidate.element);
        if (!available.contains(encoder)) {
            continue;
        }

        for (const Container &container : kContainers) {
            if (qstrcmp(container.codec, candidate.codec) != 0) {
                continue;
            }
            const QString muxer = QLatin1String(container.muxer);
            if (!available.contains(muxer)) {
                continue;
            }

            EncoderChoice choice;
            choice.videoEncoder = encoder;
            choice.videoOptions = QLatin1String(candidate.options);
            choice.muxer = muxer;
            choice.extension = QLatin1String(container.extension);
            choice.audioEncoder = audioFor(muxer, available);

            // A parser is how a muxer is told what it is being handed. When
            // one is called for and absent, the next container along takes
            // the stream as it comes rather than the file being wrong.
            const QString parser = QLatin1String(container.parser);
            if (!parser.isEmpty()) {
                if (!available.contains(parser)) {
                    continue;
                }
                choice.videoParser = parser;
            }

            if (choice.hasAudio()) {
                withAudio.append(choice);
            } else {
                // Kept, but behind every combination that can carry the music
                silent.append(choice);
            }
        }
    }

    return withAudio + silent;
}
