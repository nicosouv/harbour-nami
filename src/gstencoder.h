#ifndef GSTENCODER_H
#define GSTENCODER_H

#include <QSize>
#include <QString>

#include "encoder.h"

/**
 * @brief Writes a clip with whatever GStreamer the device already has
 *
 * GStreamer is loaded at runtime, by name, and not linked against. That is
 * the whole design decision here and it is worth stating why:
 *
 * - The app ships no encoder of its own. Bundling a minimal ffmpeg plus
 *   openh264 would add some five megabytes to a package that already
 *   carries a cross-compiled OpenCV, and a licence conversation, to
 *   duplicate codecs the phone runs its own video player with.
 * - Linking GStreamer would make it a build dependency of a package that
 *   builds in a container nobody here can try first, and a missing devel
 *   package would break the build rather than one feature.
 * - Loaded by name, a device without it loses exactly one menu item and
 *   says so.
 *
 * The cost is a handful of function pointers and two mirrored structs, and
 * both are checked before anything is written.
 */
class GstEncoder : public Encoder
{
public:
    GstEncoder();
    ~GstEncoder() override;

    /**
     * @brief Whether this device can be asked to encode anything at all
     */
    static bool isAvailable();

    /**
     * @brief Which of Encoders::candidates() the plugin registry holds
     */
    static QSet<QString> availableElements();

    bool open(const QString &path, const QSize &size, int fps,
              const QString &audioPath, const EncoderChoice &choice) override;
    bool writeFrame(const QImage &frame) override;
    void setAudioLevel(double level) override;
    bool finish() override;
    QString errorString() const override;

private:
    bool takeError();
    void release();

    void *m_pipeline;
    void *m_videoSrc;
    void *m_audioSrc;
    void *m_volume;
    void *m_bus;

    QString m_error;
    // Which combination this pipeline was built from, so a failure names the
    // element that refused rather than only the source that noticed
    QString m_choice;
    QSize m_size;
    int m_fps;
    qint64 m_frames;
};

#endif // GSTENCODER_H
