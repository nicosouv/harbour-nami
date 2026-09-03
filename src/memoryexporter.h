#ifndef MEMORYEXPORTER_H
#define MEMORYEXPORTER_H

#include <QSize>
#include <QString>

#include <functional>

#include "memorycomposer.h"

/**
 * @brief Writes a composed clip to a file
 *
 * The last link in the chain: the recipes chose the photographs, the
 * composer decided the edit, the renderer draws it and the encoder
 * compresses it. Nothing here decides anything about the clip itself, which
 * is why the exported file cannot disagree with the preview.
 *
 * Static and free of QObject on purpose: it runs on a worker thread and the
 * only thing it touches from there is the filesystem.
 */
namespace MemoryExporter {

struct Request {
    Clip clip;
    QString trackPath;    // may be empty, and then the clip is silent
    QString directory;
    QString baseName;     // without extension: the encoder picks that
};

struct Result {
    bool ok = false;
    QString path;
    QString error;
    bool cancelled = false;
    // The encoder refused the frames rather than the export going wrong:
    // worth trying the next combination down, and nothing to tell the user
    bool rejectedEarly = false;
};

/**
 * @brief Called as frames are written, with 0 to 1
 *
 * Returning false abandons the export and takes the half-written file with
 * it. This is also how the UI cancels.
 */
typedef std::function<bool(double)> Progress;

/**
 * @brief Whether this device can write a video at all
 */
bool isAvailable();

/**
 * @brief Why it cannot, in words a person can act on
 */
QString unavailableReason();

/**
 * @brief 720 lines, and as many columns as the style's aspect asks for
 *
 * Both even: every H.264 profile worth writing requires it, and a clip is
 * not the place to discover that.
 */
QSize frameSize(double aspect);

/**
 * @brief A memory's title, reduced to something a filesystem accepts
 */
QString fileName(const QString &title);

Result run(const Request &request, const Progress &progress);

}  // namespace MemoryExporter

#endif // MEMORYEXPORTER_H
