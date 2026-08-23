#include "memorystyle.h"

namespace {

// Sentimental: four beats a photo, long cross-fades, a slow move in. Warm
// and slightly softened, the register of looking back at something.
MemoryStyle sentimental()
{
    MemoryStyle style;
    style.id = QStringLiteral("sentimental");
    style.beatsPerShot = 4;
    style.transition = Transition::Dissolve;
    style.transitionMs = 600;
    style.zoomFrom = 1.00;
    style.zoomTo = 1.06;
    style.grade.warmth = 0.25;
    style.grade.contrast = -0.05;
    style.grade.vignette = 0.20;
    style.defaultTrackId = QStringLiteral("sentimental");
    return style;
}

// Energetic: one beat a photo, hard cuts, a punch in. Halves again on the
// loud parts, so the clip lifts where the track does.
MemoryStyle energetic()
{
    MemoryStyle style;
    style.id = QStringLiteral("energetic");
    style.beatsPerShot = 2;
    style.halveOnHighEnergy = true;
    style.transition = Transition::Cut;
    style.transitionMs = 0;
    style.zoomFrom = 1.00;
    style.zoomTo = 1.12;
    style.grade.contrast = 0.20;
    style.grade.saturation = 0.15;
    style.defaultTrackId = QStringLiteral("energetic");
    return style;
}

// Polaroid: 4:3 in a white frame, each photo dropped onto the pile. The one
// style that steps outside the rest of the app's language, on purpose:
// nostalgia is the effect, and nostalgia has a texture.
MemoryStyle polaroid()
{
    MemoryStyle style;
    style.id = QStringLiteral("polaroid");
    style.beatsPerShot = 2;
    style.transition = Transition::Drop;
    style.transitionMs = 320;
    style.zoomFrom = 1.00;
    style.zoomTo = 1.04;
    style.aspect = 4.0 / 3.0;
    style.grade.warmth = 0.35;
    style.grade.saturation = -0.15;
    style.grade.vignette = 0.15;
    style.grade.grain = 0.35;
    style.defaultTrackId = QStringLiteral("polaroid");
    return style;
}

// Bauhaus: the photo on a strict grid, cuts on the beat, a primary flat
// sweeping the transition. No colour treatment at all, because the whole
// idea is that the composition carries it and the photograph stays itself.
MemoryStyle bauhaus()
{
    MemoryStyle style;
    style.id = QStringLiteral("bauhaus");
    style.beatsPerShot = 2;
    style.transition = Transition::Wipe;
    style.transitionMs = 220;
    // The grid does not move. A Ken Burns drift would undo the one thing
    // this style is about.
    style.zoomFrom = 1.0;
    style.zoomTo = 1.0;
    style.defaultTrackId = QStringLiteral("bauhaus");
    return style;
}

}  // namespace

QVector<MemoryStyle> MemoryStyles::all()
{
    return { sentimental(), energetic(), polaroid(), bauhaus() };
}

MemoryStyle MemoryStyles::byId(const QString &id)
{
    for (const MemoryStyle &style : all()) {
        if (style.id == id) {
            return style;
        }
    }
    return MemoryStyle{ QString(), 0, false, Transition::Cut, 0, 1.0, 1.0, 1.0,
                        Grade(), QString() };
}

QString MemoryStyles::fallbackId()
{
    return QStringLiteral("sentimental");
}
