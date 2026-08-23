#include "memorycomposer.h"

#include <QPointF>
#include <algorithm>

namespace {

// The largest crop of the wanted aspect that fits in the photo, normalized
QSizeF fullCrop(const QSize &photo, double aspect)
{
    const double width = photo.width();
    const double height = photo.height();
    if (width <= 0.0 || height <= 0.0 || aspect <= 0.0) {
        return QSizeF(1.0, 1.0);
    }

    if (width / height > aspect) {
        // Wider than the output: the height is what runs out first
        return QSizeF((aspect * height) / width, 1.0);
    }
    return QSizeF(1.0, (width / aspect) / height);
}

// A small, stable offset so consecutive shots do not all drift the same way.
// Derived from the index rather than from a random source, because the
// preview and the export have to agree frame for frame.
QPointF driftFor(int index)
{
    static const QPointF drifts[4] = {
        QPointF(-1.0, -1.0), QPointF(1.0, -1.0),
        QPointF(1.0, 1.0), QPointF(-1.0, 1.0)
    };
    return drifts[index % 4];
}

}  // namespace

QPointF MemoryComposer::subjectCentre(const ComposerPhoto &photo)
{
    if (photo.faces.isEmpty()) {
        return QPointF(0.5, 0.5);
    }

    // The union of the faces, so a clip of two people frames both rather
    // than picking one and cutting the other in half
    QRectF bounds = photo.faces.first();
    for (const QRectF &face : photo.faces) {
        bounds = bounds.united(face);
    }
    return bounds.center();
}

QRectF MemoryComposer::frameAround(const QSize &photo, double aspect, double zoom,
                                   const QPointF &centre)
{
    const QSizeF full = fullCrop(photo, aspect);
    const double safeZoom = zoom > 0.0 ? zoom : 1.0;

    const double width = qMin(1.0, full.width() / safeZoom);
    const double height = qMin(1.0, full.height() / safeZoom);

    // Clamping pulls the rectangle back inside the photo, which is what
    // keeps a face near an edge from being framed against black
    const double x = qBound(0.0, centre.x() - width / 2.0, 1.0 - width);
    const double y = qBound(0.0, centre.y() - height / 2.0, 1.0 - height);

    return QRectF(x, y, width, height);
}

Clip MemoryComposer::compose(const QVector<ComposerPhoto> &photos,
                             const MemoryStyle &style,
                             const BeatGrid &grid)
{
    Clip clip;
    if (photos.isEmpty() || !style.isValid() || !grid.isValid()) {
        return clip;
    }

    clip.styleId = style.id;
    clip.trackId = grid.trackId.isEmpty() ? style.defaultTrackId : grid.trackId;
    clip.grade = style.grade;
    clip.aspect = style.aspect;
    clip.trackStartMs = grid.beats.first();

    const int lastBeat = grid.lastUsableBeat();
    if (lastBeat < style.beatsPerShot) {
        return clip;  // the track cannot hold even one shot
    }

    // First pass: how many shots the track has room for. The beat spacing is
    // not necessarily even, and a style may halve its shots on the loud
    // parts, so this is walked rather than divided.
    //
    // Not called "slots": Qt defines that away to nothing in qobjectdefs.h,
    // and the errors it produces point everywhere except at the name.
    QVector<QPair<qint64, qint64>> beatSlots;  // start, end in track time
    int beat = 0;
    while (true) {
        int length = style.beatsPerShot;
        if (style.halveOnHighEnergy && length > 1
                && grid.energyAt(grid.beats.at(beat)) >= 0.6) {
            length /= 2;
        }
        if (beat + length > lastBeat) {
            break;
        }
        beatSlots.append(qMakePair(grid.beats.at(beat), grid.beats.at(beat + length)));
        beat += length;
    }

    if (beatSlots.isEmpty()) {
        return clip;
    }

    // More photos than beatSlots: sample evenly across the memory rather than
    // taking the first N. The generator already spread these across the
    // whole time range, and truncating here would undo that.
    QVector<int> order;
    if (photos.size() <= beatSlots.size()) {
        for (int i = 0; i < photos.size(); i++) {
            order.append(i);
        }
        beatSlots.resize(order.size());
    } else {
        for (int i = 0; i < beatSlots.size(); i++) {
            order.append(int((qint64(i) * photos.size()) / beatSlots.size()));
        }
    }

    for (int i = 0; i < order.size(); i++) {
        const ComposerPhoto &photo = photos.at(order.at(i));

        Shot shot;
        shot.photoIndex = order.at(i);
        shot.filePath = photo.filePath;
        shot.startMs = beatSlots.at(i).first - clip.trackStartMs;
        shot.durationMs = beatSlots.at(i).second - beatSlots.at(i).first;

        // The first shot has nothing to come out of, so it always cuts in
        shot.transitionIn = i == 0 ? Transition::Cut : style.transition;
        shot.transitionMs = i == 0 ? 0 : style.transitionMs;

        // The move ends on the subject: a wide opening that resolves onto a
        // face is the shape of the shot, and the face boxes to do it with
        // are already in the database
        const QPointF centre = subjectCentre(photo);
        const QPointF drift = driftFor(i);

        // The opening is nudged away from the subject by a fraction of the
        // room the zoom leaves, so the move has somewhere to travel. With no
        // zoom at all it stays put, which is what the bauhaus grid wants.
        const double travel = qMax(0.0, style.zoomTo - style.zoomFrom) * 0.25;
        const QPointF opening(centre.x() + drift.x() * travel,
                              centre.y() + drift.y() * travel);

        shot.rectFrom = frameAround(photo.size, style.aspect, style.zoomFrom, opening);
        shot.rectTo = frameAround(photo.size, style.aspect, style.zoomTo, centre);

        clip.shots.append(shot);
    }

    const Shot &last = clip.shots.last();
    clip.durationMs = last.startMs + last.durationMs;
    return clip;
}
