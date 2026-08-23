#ifndef MEMORYCOMPOSER_H
#define MEMORYCOMPOSER_H

#include <QString>
#include <QVector>
#include <QRectF>
#include <QSize>

#include "memorystyle.h"
#include "beatgrid.h"

/**
 * @brief One photo as the composer needs to see it
 */
struct ComposerPhoto {
    QString filePath;
    QSize size;             // pixels, EXIF-oriented
    QVector<QRectF> faces;  // normalized boxes, empty when nobody is in it
};

/**
 * @brief One photo's turn on screen
 *
 * Times are milliseconds from the start of the clip. rectFrom and rectTo are
 * normalized crop rectangles in the source photo: the renderer moves from
 * one to the other over the shot, which is the whole Ken Burns move.
 */
struct Shot {
    int photoIndex = -1;
    QString filePath;
    qint64 startMs = 0;
    qint64 durationMs = 0;
    Transition transitionIn = Transition::Cut;
    int transitionMs = 0;
    QRectF rectFrom;
    QRectF rectTo;
};

/**
 * @brief A complete edit, as data
 *
 * This is the thing both halves of the feature read: the QML player animates
 * it in real time, and the offline renderer draws the same shots frame by
 * frame. What you preview is what you export because it is literally the
 * same list.
 */
struct Clip {
    QVector<Shot> shots;
    qint64 durationMs = 0;
    // Where in the track the music should start, so the first cut lands on
    // the first beat rather than on the silence before it
    qint64 trackStartMs = 0;
    QString styleId;
    QString trackId;
    Grade grade;
    double aspect = 16.0 / 9.0;

    bool isEmpty() const { return shots.isEmpty(); }
};

/**
 * @brief Turns a memory's photos into an edit
 *
 * Pure: it reads no files, decodes no pixels and touches no database. That
 * is what makes the interesting decisions here testable at all, and it is
 * why the renderer and the player can share them.
 */
namespace MemoryComposer {

/**
 * @brief Compose a clip
 *
 * Deterministic: the same photos, style and grid always give the same edit,
 * so a preview and an export taken minutes apart cannot disagree.
 */
Clip compose(const QVector<ComposerPhoto> &photos,
             const MemoryStyle &style,
             const BeatGrid &grid);

/**
 * @brief The crop rectangle of the given aspect, at the given zoom,
 *        centred as close to `centre` as staying inside the photo allows
 *
 * Exposed because it is the part worth testing on its own: everything the
 * viewer sees passes through it.
 */
QRectF frameAround(const QSize &photo, double aspect, double zoom,
                   const QPointF &centre);

/**
 * @brief Where a photo's interest lies, in normalized coordinates
 *
 * The centre of the faces when there are any, the middle of the frame when
 * there are not. The face boxes are already in the database, so a clip that
 * never crops a head off costs nothing extra.
 */
QPointF subjectCentre(const ComposerPhoto &photo);

}  // namespace MemoryComposer

#endif // MEMORYCOMPOSER_H
