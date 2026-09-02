#include "cliprenderer.h"

#include <QColor>
#include <QImageReader>
#include <QLinearGradient>
#include <QPainter>
#include <QtMath>

namespace {

// The ground a polaroid lands on, and what a wipe uncovers. Same two values
// the player paints, so a frame of the export and a frame of the preview are
// the same picture.
const QColor kPaperGround(0xf2, 0xef, 0xe9);
const QColor kDarkGround(0, 0, 0);

// The flat that sweeps a bauhaus wipe. The player uses the device's own
// highlight colour, which is the right answer on screen and the wrong one in
// a file somebody else will watch: an exported clip cannot depend on the
// theme of the phone it was made on.
const QColor kWipeFlat(0xd0, 0x34, 0x2c);

double lerp(double from, double to, double progress)
{
    return from + (to - from) * progress;
}

QRectF lerpRect(const QRectF &from, const QRectF &to, double progress)
{
    return QRectF(lerp(from.x(), to.x(), progress),
                  lerp(from.y(), to.y(), progress),
                  lerp(from.width(), to.width(), progress),
                  lerp(from.height(), to.height(), progress));
}

QString transitionName(Transition transition)
{
    switch (transition) {
    case Transition::Dissolve: return QStringLiteral("dissolve");
    case Transition::Wipe:     return QStringLiteral("wipe");
    case Transition::Drop:     return QStringLiteral("drop");
    case Transition::Cut:      break;
    }
    return QStringLiteral("cut");
}

}  // namespace

ClipRenderer::ClipRenderer(const Clip &clip, const QSize &size)
    : m_clip(clip)
    , m_size(size)
{
}

qint64 ClipRenderer::leadInMs() const
{
    return qMax(qint64(0), m_clip.trackStartMs);
}

qint64 ClipRenderer::durationMs() const
{
    return leadInMs() + m_clip.durationMs;
}

int ClipRenderer::frameCount(int fps) const
{
    if (fps <= 0) {
        return 0;
    }
    return int((durationMs() * fps + 999) / 1000);
}

int ClipRenderer::shotIndexAt(qint64 clipTimeMs) const
{
    for (int i = m_clip.shots.size() - 1; i >= 0; i--) {
        if (m_clip.shots.at(i).startMs <= clipTimeMs) {
            return i;
        }
    }
    return m_clip.shots.isEmpty() ? -1 : 0;
}

QImage ClipRenderer::photo(const QString &path, double tightestWidth)
{
    if (path == m_pathA) {
        return m_imageA;
    }
    if (path == m_pathB) {
        // Promote it, so the shot on screen is never the one evicted next
        qSwap(m_pathA, m_pathB);
        qSwap(m_imageA, m_imageB);
        return m_imageA;
    }

    QImageReader reader(path);
    // The composer's rectangles are normalized coordinates in the photo as
    // it is meant to be seen, so the orientation tag has to be applied
    // before anything is measured against it
    reader.setAutoTransform(true);

    // Decoded at the size it will be drawn rather than at twelve megapixels.
    // The tightest the camera gets on this photo decides it: a crop covering
    // 94% of the width is drawn at 1.06 output widths, not at 1.67.
    //
    // The scale is uniform and is worked out against the shorter side, so it
    // holds whichever way round the orientation tag turns out to put the
    // photo. Guessing that from QImageReader::size(), which reports what is
    // stored rather than what will be shown, is how a portrait photograph
    // ends up decoded 25% too small and soft for the whole shot.
    const QSize stored = reader.size();
    const double needed = m_size.width() / qMax(0.05, tightestWidth);
    if (stored.isValid() && stored.width() > 0 && stored.height() > 0) {
        const double shorter = qMin(stored.width(), stored.height());
        const double scale = qMin(1.0, needed / shorter);
        if (scale < 1.0) {
            reader.setScaledSize(QSize(qMax(1, qRound(stored.width() * scale)),
                                       qMax(1, qRound(stored.height() * scale))));
        }
    }

    QImage image = reader.read();
    if (!image.isNull() && image.format() != QImage::Format_RGB32) {
        image = image.convertToFormat(QImage::Format_RGB32);
    }

    m_pathB = m_pathA;
    m_imageB = m_imageA;
    m_pathA = path;
    m_imageA = image;
    return m_imageA;
}

void ClipRenderer::drawShot(QPainter &painter, const Shot &shot, double progress)
{
    const double tightest = qMin(shot.rectFrom.width(), shot.rectTo.width());
    const QImage image = photo(shot.filePath, tightest);
    if (image.isNull()) {
        return;
    }

    const QRectF rect = lerpRect(shot.rectFrom, shot.rectTo, progress);
    const QRectF source(rect.x() * image.width(), rect.y() * image.height(),
                        rect.width() * image.width(), rect.height() * image.height());

    painter.drawImage(QRectF(QPointF(0, 0), QSizeF(m_size)), image, source);
}

void ClipRenderer::applyGrade(QPainter &painter)
{
    const QRectF whole(QPointF(0, 0), QSizeF(m_size));

    // Warmth and vignette, and nothing else, because those are the two the
    // player draws. Doing contrast, saturation and grain properly here would
    // make the exported clip a better picture than the one somebody chose
    // the style by, and "what you preview is what you export" is worth more
    // than a slightly richer file.
    if (!qFuzzyIsNull(m_clip.grade.warmth)) {
        QColor tint = m_clip.grade.warmth > 0 ? QColor(0xff, 0xb0, 0x66)
                                              : QColor(0x66, 0xa0, 0xff);
        tint.setAlphaF(qMin(1.0, qAbs(m_clip.grade.warmth) * 0.18));
        painter.fillRect(whole, tint);
    }

    if (m_clip.grade.vignette > 0) {
        QLinearGradient gradient(0, 0, 0, m_size.height());
        QColor top(0, 0, 0);
        top.setAlphaF(qMin(1.0, m_clip.grade.vignette * 0.5));
        QColor bottom(0, 0, 0);
        bottom.setAlphaF(qMin(1.0, m_clip.grade.vignette * 0.6));

        gradient.setColorAt(0.0, top);
        gradient.setColorAt(0.35, Qt::transparent);
        gradient.setColorAt(0.65, Qt::transparent);
        gradient.setColorAt(1.0, bottom);

        painter.fillRect(whole, gradient);
    }
}

QImage ClipRenderer::frameAt(qint64 timeMs)
{
    QImage frame(m_size, QImage::Format_RGB32);

    if (m_clip.shots.isEmpty()) {
        frame.fill(kDarkGround);
        return frame;
    }

    // Before the first cut the clip is not running yet: the opening shot is
    // held still while the track plays its way to the first beat
    const qint64 clipTime = qMax(qint64(0), timeMs - leadInMs());

    const int index = qBound(0, shotIndexAt(clipTime), m_clip.shots.size() - 1);
    const Shot &shot = m_clip.shots.at(index);
    const QString transition = transitionName(shot.transitionIn);

    frame.fill(transition == QLatin1String("drop") ? kPaperGround : kDarkGround);

    QPainter painter(&frame);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    painter.setRenderHint(QPainter::Antialiasing, true);

    const double progress = shot.durationMs > 0
        ? qBound(0.0, double(clipTime - shot.startMs) / double(shot.durationMs), 1.0)
        : 0.0;

    // How far into the transition, 1 once it is over. Same expression the
    // player evaluates, and the first shot has nothing to come from.
    const double transitionProgress = shot.transitionMs > 0
        ? qBound(0.0, double(clipTime - shot.startMs) / double(shot.transitionMs), 1.0)
        : 1.0;
    const bool inTransition = index > 0 && transitionProgress < 1.0;

    if (inTransition) {
        // The shot being left, frozen where its own move ended rather than
        // still drifting
        drawShot(painter, m_clip.shots.at(index - 1), 1.0);
    }

    painter.save();

    if (inTransition) {
        if (transition == QLatin1String("dissolve")) {
            painter.setOpacity(transitionProgress);
        } else if (transition == QLatin1String("drop")) {
            // Lands on the pile rather than fading in
            painter.setOpacity(transitionProgress);
            const double scale = 1.0 + 0.35 * (1.0 - transitionProgress);
            painter.translate(m_size.width() / 2.0, m_size.height() / 2.0);
            painter.rotate(4.0 * (1.0 - transitionProgress));
            painter.scale(scale, scale);
            painter.translate(-m_size.width() / 2.0, -m_size.height() / 2.0);
        } else if (transition == QLatin1String("wipe")) {
            painter.setClipRect(QRectF(0, 0, m_size.width() * transitionProgress,
                                       m_size.height()));
        }
    }

    drawShot(painter, shot, progress);
    painter.restore();

    if (inTransition && transition == QLatin1String("wipe")) {
        // The flat's leading edge is the reveal, so the sweep and what it
        // uncovers cannot come apart
        painter.fillRect(QRectF(m_size.width() * transitionProgress, 0,
                                m_size.width() * 0.06, m_size.height()),
                         kWipeFlat);
    }

    applyGrade(painter);
    painter.end();

    return frame;
}
