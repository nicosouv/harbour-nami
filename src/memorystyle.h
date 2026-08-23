#ifndef MEMORYSTYLE_H
#define MEMORYSTYLE_H

#include <QString>
#include <QVector>

/**
 * @brief How one shot gives way to the next
 */
enum class Transition {
    Cut,        // nothing at all, on the beat
    Dissolve,   // cross-fade
    Wipe,       // a flat colour sweeps across, then reveals
    Drop        // the photo lands on the pile, slightly rotated
};

/**
 * @brief The colour treatment of a whole clip
 *
 * Everything is a signed amount around zero, zero meaning "leave it alone",
 * so a style that sets nothing renders the photographs as they are.
 */
struct Grade {
    double warmth = 0.0;      // -1 cool, +1 warm
    double contrast = 0.0;    // -1 flatter, +1 harder
    double saturation = 0.0;  // -1 towards grey, +1 richer
    double vignette = 0.0;    // 0 none, 1 heavy
    double grain = 0.0;       // 0 none, 1 heavy
};

/**
 * @brief A clip style, as parameters rather than as code
 *
 * Adding a style must be a matter of adding a row here. The composer reads
 * these values and knows nothing about "sentimental" or "bauhaus", which is
 * what keeps the four of them from growing four code paths.
 */
struct MemoryStyle {
    QString id;

    // How many beats a shot holds. Cutting on the beat is the whole point:
    // a slideshow whose changes land off the music reads as broken even to
    // someone who could not say why.
    int beatsPerShot = 4;

    // Shots may be halved on the loud parts of the track, which is how a
    // style gets faster without a second set of parameters
    bool halveOnHighEnergy = false;

    Transition transition = Transition::Dissolve;
    int transitionMs = 600;

    // The Ken Burns move, as the zoom at the start and at the end of a shot.
    // Above 1 is tighter, so zoomTo > zoomFrom moves in.
    double zoomFrom = 1.0;
    double zoomTo = 1.06;

    // Output aspect, width over height
    double aspect = 16.0 / 9.0;

    Grade grade;

    // Which bundled track the style opens on, until the user picks another
    QString defaultTrackId;

    bool isValid() const { return !id.isEmpty() && beatsPerShot > 0; }
};

namespace MemoryStyles {

/**
 * @brief The style with this id, or an invalid one when there is no such style
 */
MemoryStyle byId(const QString &id);

/**
 * @brief Every style, in the order a picker should offer them
 */
QVector<MemoryStyle> all();

/**
 * @brief The id used when a memory names a style that no longer exists
 */
QString fallbackId();

}  // namespace MemoryStyles

#endif // MEMORYSTYLE_H
