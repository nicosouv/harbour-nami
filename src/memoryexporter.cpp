#include "memoryexporter.h"

#include <QDir>
#include <QFile>

#include "cliprenderer.h"
#include "encoder.h"
#include "gstencoder.h"
#include "logging.h"

namespace {

// 25 rather than 30. The only motion in a clip is a slow crop drifting
// across a photograph, which 25 frames a second carries perfectly well, and
// a phone that has to draw and compress every one of them notices the sixth
// it does not have to.
const int kFps = 25;

// The music is wound down over the last moment, exactly as the player does
// it: a clip stops where the edit ends, which is never where the track ends,
// and cutting it dead there sounds like a failure rather than an ending.
const int kFadeMs = 1200;

const int kFrameHeight = 720;

}  // namespace

bool MemoryExporter::isAvailable()
{
    return GstEncoder::isAvailable()
            && Encoders::choose(GstEncoder::availableElements()).isValid();
}

QString MemoryExporter::unavailableReason()
{
    if (!GstEncoder::isAvailable()) {
        return QStringLiteral("GStreamer is not available on this device");
    }
    if (!Encoders::choose(GstEncoder::availableElements()).isValid()) {
        return QStringLiteral("no usable video encoder on this device");
    }
    return QString();
}

QSize MemoryExporter::frameSize(double aspect)
{
    const double safe = (aspect > 0.1 && aspect < 10.0) ? aspect : 16.0 / 9.0;
    int width = int(qRound(kFrameHeight * safe));
    width -= width % 2;
    return QSize(qMax(2, width), kFrameHeight);
}

QString MemoryExporter::fileName(const QString &title)
{
    QString name;
    for (const QChar &character : title) {
        if (character.isLetterOrNumber() || character == QLatin1Char(' ')
                || character == QLatin1Char('-') || character == QLatin1Char('_')) {
            name.append(character);
        } else {
            name.append(QLatin1Char(' '));
        }
    }

    name = name.simplified();
    if (name.isEmpty()) {
        name = QStringLiteral("Nami");
    }
    // Long enough for any title worth reading, short enough for every
    // filesystem this could land on
    return name.left(60);
}

MemoryExporter::Result MemoryExporter::run(const Request &request,
                                           const Progress &progress)
{
    Result result;

    if (request.clip.isEmpty()) {
        result.error = QStringLiteral("there is nothing to export");
        return result;
    }

    const EncoderChoice choice = Encoders::choose(GstEncoder::availableElements());
    if (!choice.isValid()) {
        result.error = unavailableReason();
        return result;
    }

    QDir directory(request.directory);
    if (!directory.exists() && !directory.mkpath(QStringLiteral("."))) {
        result.error = QStringLiteral("could not create %1").arg(request.directory);
        return result;
    }

    // Same memory, same name: exporting again replaces the file rather than
    // leaving a numbered pile of nearly identical clips in the gallery
    const QString path = directory.filePath(request.baseName + QLatin1Char('.')
                                            + choice.extension);

    const QSize size = frameSize(request.clip.aspect);
    ClipRenderer renderer(request.clip, size);

    const int frames = renderer.frameCount(kFps);
    if (frames <= 0) {
        result.error = QStringLiteral("there is nothing to export");
        return result;
    }

    GstEncoder encoder;
    if (!encoder.open(path, size, kFps, request.trackPath)) {
        result.error = encoder.errorString();
        return result;
    }

    const qint64 duration = renderer.durationMs();

    for (int index = 0; index < frames; index++) {
        const qint64 time = qint64(index) * 1000 / kFps;

        const qint64 remaining = duration - time;
        encoder.setAudioLevel(remaining >= kFadeMs
                              ? 1.0 : qMax(0.0, double(remaining) / kFadeMs));

        if (!encoder.writeFrame(renderer.frameAt(time))) {
            result.error = encoder.errorString();
            QFile::remove(path);
            return result;
        }

        if (progress && !progress(double(index + 1) / double(frames))) {
            result.cancelled = true;
            // No half a clip left behind: it would be indistinguishable in
            // the gallery from one that worked
            QFile::remove(path);
            return result;
        }
    }

    if (!encoder.finish()) {
        result.error = encoder.errorString();
        QFile::remove(path);
        return result;
    }

    qCDebug(lcNami) << "Exported" << frames << "frames to" << path;

    result.ok = true;
    result.path = path;
    return result;
}
