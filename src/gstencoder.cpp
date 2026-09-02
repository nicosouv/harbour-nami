#include "gstencoder.h"

#include <QImage>
#include <QLibrary>
#include <QStringList>

#include <cstring>

#include "logging.h"

namespace {

// === What GStreamer's ABI looks like from outside ===
//
// GStreamer 1.x froze its ABI at 1.0 and has kept it since. These two
// structs are public in its headers; they are repeated here only because
// the headers are not a build dependency of this package.
//
// Nothing trusts them on faith: sanityCheck() below allocates one buffer and
// verifies the five timestamp fields read back as the values GStreamer is
// documented to initialise them to. Five 64-bit words in the right places is
// not something a wrong layout produces by accident, and if it fails the
// encoder simply reports itself unavailable.

struct MiniObjectMirror {
    size_t type;            // GType
    int refcount;
    int lockstate;
    unsigned int flags;
    void *copy;
    void *dispose;
    void *freeFunc;
    unsigned int privUint;
    void *privPointer;
};

struct BufferMirror {
    MiniObjectMirror miniObject;
    void *pool;
    quint64 pts;
    quint64 dts;
    quint64 duration;
    quint64 offset;
    quint64 offsetEnd;
};

// Only as far as the field that says what a message is. Everything after it
// is read through gst_message_parse_*, which is where the varying part of a
// message lives anyway.
struct MessageMirror {
    MiniObjectMirror miniObject;
    int type;
};

struct MapInfoMirror {
    void *memory;
    int flags;
    unsigned char *data;
    size_t size;
    size_t maxsize;
    void *userData[4];
    void *reserved[4];
};

// GError, from glib. Read for its message and freed through glib when that
// could be resolved.
struct ErrorMirror {
    unsigned int domain;
    int code;
    char *message;
};

const int kStateNull = 1;
const int kStatePlaying = 4;
const int kStateChangeFailure = 0;

const int kMessageEos = 1 << 0;
const int kMessageError = 1 << 1;

const int kMapWrite = 1 << 1;

const quint64 kClockTimeNone = Q_UINT64_C(0xFFFFFFFFFFFFFFFF);
const quint64 kNsPerSecond = Q_UINT64_C(1000000000);

struct GstApi {
    bool ready = false;

    void (*init)(int *, char ***) = nullptr;
    void *(*parse_launch)(const char *, void **) = nullptr;
    void *(*bin_get_by_name)(void *, const char *) = nullptr;
    int (*element_set_state)(void *, int) = nullptr;
    int (*element_get_state)(void *, int *, int *, quint64) = nullptr;
    void *(*element_get_bus)(void *) = nullptr;
    int (*element_send_event)(void *, void *) = nullptr;
    void *(*event_new_eos)() = nullptr;
    void *(*bus_timed_pop_filtered)(void *, quint64, int) = nullptr;
    void (*message_parse_error)(void *, void **, char **) = nullptr;
    void *(*buffer_new_allocate)(void *, size_t, void *) = nullptr;
    int (*buffer_map)(void *, MapInfoMirror *, int) = nullptr;
    void (*buffer_unmap)(void *, MapInfoMirror *) = nullptr;
    void (*mini_object_unref)(void *) = nullptr;
    void (*object_unref)(void *) = nullptr;
    void (*util_set_object_arg)(void *, const char *, const char *) = nullptr;
    void *(*element_factory_find)(const char *) = nullptr;

    int (*app_src_push_buffer)(void *, void *) = nullptr;
    int (*app_src_end_of_stream)(void *) = nullptr;

    // Optional: only used to give an error message back to glib
    void (*error_free)(void *) = nullptr;
    void (*mem_free)(void *) = nullptr;
};

template <typename T>
bool resolve(QLibrary &library, const char *name, T &slot)
{
    slot = reinterpret_cast<T>(library.resolve(name));
    if (!slot) {
        qCWarning(lcNami) << "GstEncoder: no symbol" << name;
    }
    return slot != nullptr;
}

bool sanityCheck(GstApi &gst)
{
    void *buffer = gst.buffer_new_allocate(nullptr, 16, nullptr);
    if (!buffer) {
        return false;
    }

    const BufferMirror *mirror = static_cast<const BufferMirror *>(buffer);
    const bool sane = mirror->miniObject.refcount == 1
            && mirror->miniObject.type != 0
            && mirror->pts == kClockTimeNone
            && mirror->dts == kClockTimeNone
            && mirror->duration == kClockTimeNone
            && mirror->offset == kClockTimeNone
            && mirror->offsetEnd == kClockTimeNone;

    gst.mini_object_unref(buffer);

    if (!sane) {
        qCWarning(lcNami) << "GstEncoder: GstBuffer is not laid out as"
                                << "expected, refusing to encode";
    }
    return sane;
}

// Loaded once, on whichever thread asks first. A C++11 function-local static
// is initialised exactly once even when two threads race for it.
GstApi &api()
{
    static GstApi loaded = [] {
        GstApi gst;

        // Static, and asked never to unload. The last QLibrary referring to
        // a library unloads it when it goes out of scope, and every function
        // pointer taken from it would then point into an unmapped page: a
        // crash on the first frame, thousands of instructions from here.
        static QLibrary core(QStringLiteral("gstreamer-1.0"), 0);
        static QLibrary app(QStringLiteral("gstapp-1.0"), 0);
        core.setLoadHints(QLibrary::PreventUnloadHint);
        app.setLoadHints(QLibrary::PreventUnloadHint);

        if (!core.load()) {
            qCWarning(lcNami) << "GstEncoder: no GStreamer on this device"
                                    << core.errorString();
            return gst;
        }
        if (!app.load()) {
            qCWarning(lcNami) << "GstEncoder: no gst-app plugin library"
                                    << app.errorString();
            return gst;
        }

        bool ok = true;
        ok &= resolve(core, "gst_init", gst.init);
        ok &= resolve(core, "gst_parse_launch", gst.parse_launch);
        ok &= resolve(core, "gst_bin_get_by_name", gst.bin_get_by_name);
        ok &= resolve(core, "gst_element_set_state", gst.element_set_state);
        ok &= resolve(core, "gst_element_get_state", gst.element_get_state);
        ok &= resolve(core, "gst_element_get_bus", gst.element_get_bus);
        ok &= resolve(core, "gst_element_send_event", gst.element_send_event);
        ok &= resolve(core, "gst_event_new_eos", gst.event_new_eos);
        ok &= resolve(core, "gst_bus_timed_pop_filtered", gst.bus_timed_pop_filtered);
        ok &= resolve(core, "gst_message_parse_error", gst.message_parse_error);
        ok &= resolve(core, "gst_buffer_new_allocate", gst.buffer_new_allocate);
        ok &= resolve(core, "gst_buffer_map", gst.buffer_map);
        ok &= resolve(core, "gst_buffer_unmap", gst.buffer_unmap);
        ok &= resolve(core, "gst_mini_object_unref", gst.mini_object_unref);
        ok &= resolve(core, "gst_object_unref", gst.object_unref);
        ok &= resolve(core, "gst_util_set_object_arg", gst.util_set_object_arg);
        ok &= resolve(core, "gst_element_factory_find", gst.element_factory_find);
        ok &= resolve(app, "gst_app_src_push_buffer", gst.app_src_push_buffer);
        ok &= resolve(app, "gst_app_src_end_of_stream", gst.app_src_end_of_stream);

        if (!ok) {
            return gst;
        }

        static QLibrary glib(QStringLiteral("glib-2.0"), 0);
        glib.setLoadHints(QLibrary::PreventUnloadHint);
        if (glib.load()) {
            gst.error_free = reinterpret_cast<void (*)(void *)>(
                        glib.resolve("g_error_free"));
            gst.mem_free = reinterpret_cast<void (*)(void *)>(
                        glib.resolve("g_free"));
        }

        // Scans the plugin registry the first time, so it is done here
        // rather than on the first frame
        gst.init(nullptr, nullptr);

        gst.ready = sanityCheck(gst);
        return gst;
    }();

    return loaded;
}

QString quoted(const QString &value)
{
    QString escaped = value;
    escaped.replace(QLatin1String("\\"), QLatin1String("\\\\"));
    escaped.replace(QLatin1String("\""), QLatin1String("\\\""));
    return QLatin1Char('"') + escaped + QLatin1Char('"');
}

}  // namespace

GstEncoder::GstEncoder()
    : m_pipeline(nullptr)
    , m_videoSrc(nullptr)
    , m_audioSrc(nullptr)
    , m_volume(nullptr)
    , m_bus(nullptr)
    , m_fps(30)
    , m_frames(0)
{
}

GstEncoder::~GstEncoder()
{
    release();
}

bool GstEncoder::isAvailable()
{
    return api().ready;
}

QSet<QString> GstEncoder::availableElements()
{
    QSet<QString> found;
    GstApi &gst = api();
    if (!gst.ready) {
        return found;
    }

    for (const QString &name : Encoders::candidates()) {
        void *factory = gst.element_factory_find(name.toUtf8().constData());
        if (factory) {
            found.insert(name);
            gst.object_unref(factory);
        }
    }
    return found;
}

bool GstEncoder::takeError()
{
    GstApi &gst = api();
    if (!m_bus) {
        return false;
    }

    void *message = gst.bus_timed_pop_filtered(m_bus, 0, kMessageError);
    if (!message) {
        return false;
    }

    void *error = nullptr;
    char *debug = nullptr;
    gst.message_parse_error(message, &error, &debug);

    if (error) {
        const ErrorMirror *mirror = static_cast<const ErrorMirror *>(error);
        m_error = QString::fromUtf8(mirror->message ? mirror->message : "unknown");
        if (gst.error_free) {
            gst.error_free(error);
        }
    } else {
        m_error = QStringLiteral("unknown encoder error");
    }

    if (debug) {
        qCWarning(lcNami) << "GstEncoder:" << debug;
        if (gst.mem_free) {
            gst.mem_free(debug);
        }
    }

    gst.mini_object_unref(message);
    return true;
}

void GstEncoder::release()
{
    GstApi &gst = api();

    if (m_pipeline) {
        gst.element_set_state(m_pipeline, kStateNull);
    }
    if (m_videoSrc) {
        gst.object_unref(m_videoSrc);
        m_videoSrc = nullptr;
    }
    if (m_audioSrc) {
        gst.object_unref(m_audioSrc);
        m_audioSrc = nullptr;
    }
    if (m_volume) {
        gst.object_unref(m_volume);
        m_volume = nullptr;
    }
    if (m_bus) {
        gst.object_unref(m_bus);
        m_bus = nullptr;
    }
    if (m_pipeline) {
        gst.object_unref(m_pipeline);
        m_pipeline = nullptr;
    }
}

bool GstEncoder::open(const QString &path, const QSize &size, int fps,
                      const QString &audioPath)
{
    GstApi &gst = api();
    if (!gst.ready) {
        m_error = QStringLiteral("GStreamer is not available on this device");
        return false;
    }

    const EncoderChoice choice = Encoders::choose(availableElements());
    if (!choice.isValid()) {
        m_error = QStringLiteral("no usable video encoder on this device");
        return false;
    }

    m_size = size;
    m_fps = qMax(1, fps);
    m_frames = 0;

    // Even dimensions: every H.264 profile worth writing wants them, and a
    // photograph resized by one pixel is a photograph
    m_size.setWidth(m_size.width() - (m_size.width() % 2));
    m_size.setHeight(m_size.height() - (m_size.height() % 2));

    QString description;
    description += QStringLiteral(
        "appsrc name=vsrc is-live=false format=time do-timestamp=false "
        "block=true max-bytes=16000000 "
        "caps=\"video/x-raw,format=BGRx,width=%1,height=%2,framerate=%3/1\" "
        "! videoconvert ! %4")
            .arg(m_size.width()).arg(m_size.height()).arg(m_fps)
            .arg(choice.videoEncoder);

    if (!choice.videoOptions.isEmpty()) {
        description += QLatin1Char(' ') + choice.videoOptions;
    }
    if (!choice.videoParser.isEmpty()) {
        description += QLatin1String(" ! ") + choice.videoParser;
    }
    description += QLatin1String(" ! mux. ");

    description += QStringLiteral("%1 name=mux ! filesink location=%2 ")
            .arg(choice.muxer, quoted(path));

    const bool withAudio = choice.hasAudio() && !audioPath.isEmpty();
    if (withAudio) {
        // decodebin rather than a named demuxer and decoder: whatever the
        // track was transcoded to at build time, this reads it. Its pads
        // appear only once the file has been sniffed, and gst_parse_launch
        // is what waits for them.
        description += QStringLiteral(
            "filesrc name=asrc location=%1 ! decodebin ! audioconvert "
            "! audioresample ! volume name=avol ! %2 ! mux.")
                .arg(quoted(audioPath), choice.audioEncoder);
    }

    qCDebug(lcNami) << "GstEncoder: pipeline" << description;

    void *error = nullptr;
    m_pipeline = gst.parse_launch(description.toUtf8().constData(), &error);
    if (!m_pipeline || error) {
        if (error) {
            const ErrorMirror *mirror = static_cast<const ErrorMirror *>(error);
            m_error = QString::fromUtf8(mirror->message ? mirror->message
                                                        : "bad pipeline");
            if (gst.error_free) {
                gst.error_free(error);
            }
        } else {
            m_error = QStringLiteral("the encoding pipeline could not be built");
        }
        release();
        return false;
    }

    m_videoSrc = gst.bin_get_by_name(m_pipeline, "vsrc");
    if (withAudio) {
        m_audioSrc = gst.bin_get_by_name(m_pipeline, "asrc");
        m_volume = gst.bin_get_by_name(m_pipeline, "avol");
    }

    if (!m_videoSrc) {
        m_error = QStringLiteral("the encoding pipeline has no source");
        release();
        return false;
    }

    // Before the state change, not after: refusing to start is the most
    // likely failure of the lot, and the reason for it is posted on the bus
    m_bus = gst.element_get_bus(m_pipeline);

    if (gst.element_set_state(m_pipeline, kStatePlaying) == kStateChangeFailure) {
        if (!takeError()) {
            m_error = QStringLiteral("the encoder refused to start");
        }
        release();
        return false;
    }

    // Deliberately not waiting for the state change to complete. A pipeline
    // fed by an appsrc cannot reach PLAYING until it has been given a frame,
    // so waiting here would stall for the whole timeout on every successful
    // export and still come back "in progress". What an element thinks of
    // these frames is read off the bus before each push instead.
    int state = 0;
    int pending = 0;
    if (gst.element_get_state(m_pipeline, &state, &pending, 0)
            == kStateChangeFailure) {
        if (!takeError()) {
            m_error = QStringLiteral("the encoder failed to start");
        }
        release();
        return false;
    }

    qCDebug(lcNami) << "GstEncoder: writing with" << choice.videoEncoder
                          << "into" << choice.muxer
                          << (withAudio ? choice.audioEncoder
                                        : QStringLiteral("no audio"));
    return true;
}

bool GstEncoder::writeFrame(const QImage &frame)
{
    GstApi &gst = api();
    if (!m_pipeline || !m_videoSrc) {
        return false;
    }

    // An error that arrived while the last frame was being drawn. Checked
    // before pushing rather than after, because a push into a pipeline that
    // has already given up is a push that never returns.
    if (takeError()) {
        return false;
    }

    QImage image = frame;
    if (image.size() != m_size) {
        image = image.scaled(m_size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    }
    if (image.format() != QImage::Format_RGB32) {
        image = image.convertToFormat(QImage::Format_RGB32);
    }

    const int stride = m_size.width() * 4;
    const size_t bytes = size_t(stride) * size_t(m_size.height());

    void *buffer = gst.buffer_new_allocate(nullptr, bytes, nullptr);
    if (!buffer) {
        m_error = QStringLiteral("out of memory");
        return false;
    }

    MapInfoMirror info;
    std::memset(&info, 0, sizeof(info));
    if (!gst.buffer_map(buffer, &info, kMapWrite)) {
        gst.mini_object_unref(buffer);
        m_error = QStringLiteral("the encoder would not take a frame");
        return false;
    }

    // Row by row: QImage pads its scanlines to four bytes and raw video does
    // not, and for 32-bit pixels they agree, but not by contract
    for (int y = 0; y < m_size.height(); y++) {
        std::memcpy(info.data + size_t(y) * size_t(stride),
                    image.constScanLine(y), size_t(stride));
    }
    gst.buffer_unmap(buffer, &info);

    BufferMirror *mirror = static_cast<BufferMirror *>(buffer);
    mirror->pts = quint64(m_frames) * kNsPerSecond / quint64(m_fps);
    mirror->dts = mirror->pts;
    mirror->duration = kNsPerSecond / quint64(m_fps);
    m_frames++;

    // Takes the buffer either way, so it is not ours to free after this
    if (gst.app_src_push_buffer(m_videoSrc, buffer) != 0) {
        if (!takeError()) {
            m_error = QStringLiteral("the encoder stopped accepting frames");
        }
        return false;
    }

    return true;
}

void GstEncoder::setAudioLevel(double level)
{
    GstApi &gst = api();
    if (!m_volume) {
        return;
    }

    const QString value = QString::number(qBound(0.0, level, 1.0), 'f', 3);
    gst.util_set_object_arg(m_volume, "volume", value.toUtf8().constData());
}

bool GstEncoder::finish()
{
    GstApi &gst = api();
    if (!m_pipeline) {
        return false;
    }

    gst.app_src_end_of_stream(m_videoSrc);

    // The track is minutes long and the clip is not, so the audio branch has
    // to be told to stop as well. A source element handles an EOS event by
    // ending its stream cleanly, which is what lets the muxer close the file
    // instead of being torn down mid-write.
    if (m_audioSrc) {
        gst.element_send_event(m_audioSrc, gst.event_new_eos());
    }

    bool ok = false;
    void *message = gst.bus_timed_pop_filtered(m_bus, 60 * kNsPerSecond,
                                               kMessageEos | kMessageError);
    if (!message) {
        m_error = QStringLiteral("the encoder never finished");
    } else if (static_cast<const MessageMirror *>(message)->type == kMessageEos) {
        // The muxer wrote its last byte and closed the file
        ok = true;
        gst.mini_object_unref(message);
        message = nullptr;
    } else {
        void *error = nullptr;
        char *debug = nullptr;
        gst.message_parse_error(message, &error, &debug);

        if (error) {
            const ErrorMirror *mirror = static_cast<const ErrorMirror *>(error);
            m_error = QString::fromUtf8(mirror->message ? mirror->message
                                                        : "unknown");
            if (gst.error_free) {
                gst.error_free(error);
            }
            if (debug && gst.mem_free) {
                gst.mem_free(debug);
            }
        } else {
            ok = true;
        }

        gst.mini_object_unref(message);
    }

    release();
    return ok;
}

QString GstEncoder::errorString() const
{
    return m_error;
}
