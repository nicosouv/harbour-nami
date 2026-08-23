#include "beatgrid.h"

#include <QJsonArray>
#include <algorithm>

bool BeatGrid::isValid() const
{
    // Two beats is the least that defines an interval to cut on
    return beats.size() >= 2 && safeOutMs > beats.first();
}

double BeatGrid::energyAt(qint64 ms) const
{
    double energy = 0.0;
    for (const BeatSection &section : sections) {
        if (section.tMs > ms) {
            break;
        }
        energy = section.energy;
    }
    return energy;
}

int BeatGrid::lastUsableBeat() const
{
    // upper_bound gives the first beat past the cut-off, so the one before
    // it is the last that may still start or end a shot
    const auto past = std::upper_bound(beats.constBegin(), beats.constEnd(), safeOutMs);
    return int(past - beats.constBegin()) - 1;
}

BeatGrid BeatGrid::fromJson(const QJsonObject &object)
{
    BeatGrid grid;
    grid.trackId = object.value("track_id").toString();
    grid.bpm = object.value("bpm").toDouble();
    grid.safeOutMs = qint64(object.value("safe_out_ms").toDouble());

    const QJsonArray beats = object.value("beats").toArray();
    grid.beats.reserve(beats.size());
    for (const QJsonValue &beat : beats) {
        grid.beats.append(qint64(beat.toDouble()));
    }
    // The analysis is trusted to be ordered, but a grid out of order would
    // produce shots of negative length rather than fail
    std::sort(grid.beats.begin(), grid.beats.end());

    const QJsonArray sections = object.value("sections").toArray();
    for (const QJsonValue &value : sections) {
        const QJsonObject section = value.toObject();
        BeatSection parsed;
        parsed.tMs = qint64(section.value("t").toDouble());
        parsed.energy = section.value("energy").toDouble();
        grid.sections.append(parsed);
    }
    std::sort(grid.sections.begin(), grid.sections.end(),
              [](const BeatSection &a, const BeatSection &b) { return a.tMs < b.tMs; });

    // A grid with no stated cut-off ends with its last beat
    if (grid.safeOutMs <= 0 && !grid.beats.isEmpty()) {
        grid.safeOutMs = grid.beats.last();
    }

    return grid;
}

BeatGrid BeatGrid::even(const QString &trackId, double bpm, qint64 durationMs)
{
    BeatGrid grid;
    grid.trackId = trackId;
    grid.bpm = bpm;
    grid.safeOutMs = durationMs;

    if (bpm <= 0.0 || durationMs <= 0) {
        return grid;
    }

    // Accumulated from the index rather than by adding the interval each
    // time, so a fractional interval does not drift over a few hundred beats
    const double intervalMs = 60000.0 / bpm;
    for (int i = 0; ; i++) {
        const qint64 t = qint64(i * intervalMs);
        if (t > durationMs) {
            break;
        }
        grid.beats.append(t);
    }

    return grid;
}
