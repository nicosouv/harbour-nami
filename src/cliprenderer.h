#ifndef CLIPRENDERER_H
#define CLIPRENDERER_H

#include <QImage>
#include <QSize>
#include <QString>

#include "memorycomposer.h"

/**
 * @brief The same edit the player shows, drawn one frame at a time
 *
 * The player derives everything on screen from one number, `positionMs`.
 * This does exactly the same thing, from the same edit decision list, with
 * a QPainter instead of a scene graph. That is the whole reason the export
 * can promise what the preview showed: there is one edit and one way of
 * reading it, and the only difference is where the pixels end up.
 *
 * Deliberately not a QObject and not threaded: it decodes and draws when
 * asked and nothing else, so it can be tested frame by frame without a
 * device, an encoder or an event loop.
 */
class ClipRenderer
{
public:
    ClipRenderer(const Clip &clip, const QSize &size);

    /**
     * @brief The still held before the first cut
     *
     * The exported file plays its track from the beginning, where the
     * preview starts it at `trackStartMs` so the first cut lands on the
     * first beat. Holding the opening frame for exactly that long puts the
     * cuts back on the beats without seeking the audio at all, and it reads
     * as an opening rather than as a stumble.
     */
    qint64 leadInMs() const;

    qint64 durationMs() const;
    int frameCount(int fps) const;

    /**
     * @brief The frame at this point in the exported file
     *
     * Deterministic: the same time always gives the same pixels, whatever
     * order the frames were asked for. Everything cached here is a cache.
     */
    QImage frameAt(qint64 timeMs);

    /**
     * @brief Which shot covers a point in the edit, -1 before the first
     */
    int shotIndexAt(qint64 clipTimeMs) const;

private:
    QImage photo(const QString &path, double tightestWidth);
    void drawShot(QPainter &painter, const Shot &shot, double progress);
    void applyGrade(QPainter &painter);

    Clip m_clip;
    QSize m_size;

    // Two slots, because a frame in a transition needs the shot arriving and
    // the shot leaving and never a third. Anything larger would hold a
    // gallery's worth of decoded photographs for no gain.
    QString m_pathA;
    QImage m_imageA;
    QString m_pathB;
    QImage m_imageB;
};

#endif // CLIPRENDERER_H
