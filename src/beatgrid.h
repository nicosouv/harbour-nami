#ifndef BEATGRID_H
#define BEATGRID_H

#include <QString>
#include <QVector>
#include <QJsonObject>

/**
 * @brief A point in a track where its energy changes
 */
struct BeatSection {
    qint64 tMs = 0;
    double energy = 0.0;  // 0 quiet, 1 the loudest the track gets
};

/**
 * @brief Where the beats of a bundled track fall
 *
 * Computed off the device. The tracks ship with the app, so their rhythm is
 * known at build time (scripts/analyze_track.py) and the result travels as
 * JSON next to the audio. Nothing here does any signal processing, and the
 * RPM carries no DSP library.
 *
 * The beats are what the composer cuts on. A slideshow whose changes land
 * off the music reads as broken even to someone who could not say why.
 */
struct BeatGrid {
    QString trackId;
    double bpm = 0.0;
    QVector<qint64> beats;        // milliseconds, ascending
    QVector<BeatSection> sections;
    // Where a clip must have ended. Past this the track is fading out, or
    // over, and a shot still running looks like a mistake.
    qint64 safeOutMs = 0;

    bool isValid() const;

    /**
     * @brief The energy of the section covering this moment
     *
     * Zero before the first section, and zero when the track has none.
     */
    double energyAt(qint64 ms) const;

    /**
     * @brief The last beat index at or before safeOutMs
     */
    int lastUsableBeat() const;

    /**
     * @brief Read a grid produced by scripts/analyze_track.py
     */
    static BeatGrid fromJson(const QJsonObject &object);

    /**
     * @brief An even grid at a given tempo, with no sections
     *
     * For a track whose analysis is missing, and for tests, which should not
     * need an audio file to describe what cutting on the beat means.
     */
    static BeatGrid even(const QString &trackId, double bpm, qint64 durationMs);
};

#endif // BEATGRID_H
