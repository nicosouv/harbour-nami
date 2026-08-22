// Unit tests for the image provider that serves every face thumbnail in the
// app. Its crop geometry is what decides whether an avatar shows a face or
// an ear: the stored bbox is tight around the features, and the margin the
// provider adds around it is the difference between a portrait and a
// close-up of a chin.
//
// QImage in, QImage out, and a disk cache in a temp dir: nothing here needs
// a window, a scene graph or the database.

#include <QtTest>
#include <QTemporaryDir>
#include <QImage>
#include <QPainter>
#include <QDir>
#include <QUrl>
#include <QFile>

#include "faceimageprovider.h"

class TstFaceImageProvider : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void cropIsSquareAndCentredOnTheFace();
    void cropKeepsMarginAroundTheBoundingBox();
    void cropNearAnEdgeStaysInsideThePhoto();
    void theRoundVariantPunchesOutTheCorners();
    void requestedSizeScalesTheResult();
    void identicalRequestsShareOneCacheFile();
    void adifferentBoundingBoxGetsItsOwnCacheFile();
    void anEditedPhotoDoesNotServeTheStaleCrop();
    void thumbnailsAreCappedAtTheMasterSize();
    void aMalformedIdYieldsNothing();
    void aMissingPhotoYieldsNothing();

private:
    // White photo with a red rectangle standing in for the face
    QString makePhoto(const QString &name, int width, int height, const QRect &face);
    QString cropId(const QString &path, qreal x, qreal y, qreal w, qreal h,
                   bool round = false) const;
    QString thumbId(const QString &path) const;
    int cachedFileCount(const QString &subdir) const;
    static bool isRedish(QRgb pixel);

    QTemporaryDir *m_dir = nullptr;
    QTemporaryDir *m_cache = nullptr;
    FaceImageProvider *m_provider = nullptr;
};

void TstFaceImageProvider::init()
{
    m_dir = new QTemporaryDir;
    m_cache = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
    QVERIFY(m_cache->isValid());
    m_provider = new FaceImageProvider(m_cache->path());
}

void TstFaceImageProvider::cleanup()
{
    delete m_provider;
    m_provider = nullptr;
    delete m_cache;
    m_cache = nullptr;
    delete m_dir;
    m_dir = nullptr;
}

QString TstFaceImageProvider::makePhoto(const QString &name, int width, int height,
                                        const QRect &face)
{
    QImage image(width, height, QImage::Format_RGB32);
    image.fill(Qt::white);

    QPainter painter(&image);
    painter.fillRect(face, Qt::red);
    painter.end();

    const QString path = m_dir->filePath(name);
    // PNG, so what the provider reads back is exactly what was drawn and a
    // colour assertion is testing the crop rather than JPEG ringing
    image.save(path, "PNG");
    return path;
}

QString TstFaceImageProvider::cropId(const QString &path, qreal x, qreal y,
                                     qreal w, qreal h, bool round) const
{
    // encodeURIComponent(), which is what qml/js/faceutils.js uses, leaves
    // the path separators alone
    QString id = QStringLiteral("crop?path=%1&x=%2&y=%3&w=%4&h=%5")
        .arg(QString::fromLatin1(QUrl::toPercentEncoding(path, "/")))
        .arg(x).arg(y).arg(w).arg(h);
    if (round) {
        id += QStringLiteral("&round=1");
    }
    return id;
}

QString TstFaceImageProvider::thumbId(const QString &path) const
{
    return QStringLiteral("thumb?path=%1")
        .arg(QString::fromLatin1(QUrl::toPercentEncoding(path, "/")));
}

int TstFaceImageProvider::cachedFileCount(const QString &subdir) const
{
    return QDir(m_cache->path() + "/" + subdir)
        .entryList(QStringList() << "*.jpg", QDir::Files).size();
}

bool TstFaceImageProvider::isRedish(QRgb pixel)
{
    return qRed(pixel) > 180 && qGreen(pixel) < 80 && qBlue(pixel) < 80;
}

void TstFaceImageProvider::cropIsSquareAndCentredOnTheFace()
{
    // Face at normalized (0.4, 0.3) sized 0.1 x 0.1 of a 400x300 photo, so
    // 40x30 pixels centred on (180, 105)
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));

    QSize size;
    const QImage crop = m_provider->requestImage(cropId(path, 0.4, 0.3, 0.1, 0.1),
                                                 &size, QSize());

    QVERIFY(!crop.isNull());
    QCOMPARE(crop.width(), crop.height());
    QCOMPARE(size, crop.size());
    QVERIFY2(isRedish(crop.pixel(crop.width() / 2, crop.height() / 2)),
             "the face should sit at the centre of the crop");
}

void TstFaceImageProvider::cropKeepsMarginAroundTheBoundingBox()
{
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));

    const QImage crop = m_provider->requestImage(cropId(path, 0.4, 0.3, 0.1, 0.1),
                                                 nullptr, QSize());

    // A tight bbox crop would be 40 wide. The provider adds kMargin (0.45)
    // on each side, so the square is the longer bbox edge times 1.9: 76.
    // Without it, YuNet's tight boxes cut hair and chin off every avatar.
    QCOMPARE(crop.width(), 76);

    // The corners fall outside the 40x30 face, so they must still be page
    // white: proof the margin is real and not just a bigger crop of skin
    QVERIFY2(!isRedish(crop.pixel(1, 1)), "the margin should show background");
    QVERIFY2(!isRedish(crop.pixel(crop.width() - 2, crop.height() - 2)),
             "the margin should show background");
}

void TstFaceImageProvider::cropNearAnEdgeStaysInsideThePhoto()
{
    // A face in the bottom right corner: the centred square would run off
    // the photo, and copy() past the edge yields black padding
    const QString path = makePhoto("corner.png", 400, 300, QRect(360, 265, 32, 24));

    const QImage crop = m_provider->requestImage(cropId(path, 0.9, 0.9, 0.08, 0.08),
                                                 nullptr, QSize());

    QVERIFY(!crop.isNull());
    QCOMPARE(crop.width(), crop.height());
    QVERIFY(crop.width() <= 300);

    // Every pixel is either the white photo or the red face, never the black
    // that copying outside the source would leave behind
    for (int y = 0; y < crop.height(); y += 8) {
        for (int x = 0; x < crop.width(); x += 8) {
            const QRgb pixel = crop.pixel(x, y);
            QVERIFY2(qRed(pixel) > 100, "the crop ran past the edge of the photo");
        }
    }
}

void TstFaceImageProvider::theRoundVariantPunchesOutTheCorners()
{
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));

    const QImage avatar = m_provider->requestImage(
        cropId(path, 0.4, 0.3, 0.1, 0.1, true), nullptr, QSize(96, 96));

    QVERIFY(!avatar.isNull());
    QVERIFY(avatar.hasAlphaChannel());
    QCOMPARE(qAlpha(avatar.pixel(0, 0)), 0);
    QCOMPARE(qAlpha(avatar.pixel(avatar.width() - 1, 0)), 0);
    QCOMPARE(qAlpha(avatar.pixel(avatar.width() / 2, avatar.height() / 2)), 255);
}

void TstFaceImageProvider::requestedSizeScalesTheResult()
{
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));

    QSize size;
    const QImage crop = m_provider->requestImage(cropId(path, 0.4, 0.3, 0.1, 0.1),
                                                 &size, QSize(64, 64));

    QCOMPARE(crop.size(), QSize(64, 64));
    QCOMPARE(size, QSize(64, 64));
}

void TstFaceImageProvider::identicalRequestsShareOneCacheFile()
{
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));
    const QString id = cropId(path, 0.4, 0.3, 0.1, 0.1);

    m_provider->requestImage(id, nullptr, QSize());
    QCOMPARE(cachedFileCount("faces"), 1);

    // The second call must come off the disk cache rather than decoding the
    // photo again: this is what stops a people grid re-decoding everything
    const QImage again = m_provider->requestImage(id, nullptr, QSize());
    QVERIFY(!again.isNull());
    QCOMPARE(cachedFileCount("faces"), 1);
}

void TstFaceImageProvider::adifferentBoundingBoxGetsItsOwnCacheFile()
{
    const QString path = makePhoto("two.png", 400, 300, QRect(160, 90, 40, 30));

    m_provider->requestImage(cropId(path, 0.4, 0.3, 0.1, 0.1), nullptr, QSize());
    m_provider->requestImage(cropId(path, 0.1, 0.1, 0.1, 0.1), nullptr, QSize());

    // Two faces in one photo must not collide on the same cached crop
    QCOMPARE(cachedFileCount("faces"), 2);
}

void TstFaceImageProvider::anEditedPhotoDoesNotServeTheStaleCrop()
{
#if QT_VERSION < QT_VERSION_CHECK(5, 10, 0)
    QSKIP("QFile::setFileTime needs Qt 5.10");
#else
    const QString path = makePhoto("edited.png", 400, 300, QRect(160, 90, 40, 30));
    const QString id = cropId(path, 0.4, 0.3, 0.1, 0.1);

    m_provider->requestImage(id, nullptr, QSize());
    QCOMPARE(cachedFileCount("faces"), 1);

    // Same path, same bbox, different content: the cache key carries the
    // modification time precisely so a rotated or retouched photo does not
    // keep showing the crop taken before the edit
    makePhoto("edited.png", 400, 300, QRect(0, 0, 40, 30));
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadWrite));
    QVERIFY(file.setFileTime(QDateTime::currentDateTime().addSecs(60),
                             QFileDevice::FileModificationTime));
    file.close();

    m_provider->requestImage(id, nullptr, QSize());
    QCOMPARE(cachedFileCount("faces"), 2);
#endif
}

void TstFaceImageProvider::thumbnailsAreCappedAtTheMasterSize()
{
    const QString path = makePhoto("big.png", 2000, 1500, QRect(900, 700, 200, 150));

    QSize size;
    const QImage thumb = m_provider->requestImage(thumbId(path), &size, QSize());

    QVERIFY(!thumb.isNull());
    // Scaled to cover a 512 square, so the shorter edge lands on 512 and the
    // original's 3 megapixels never reach the grid
    QCOMPARE(qMin(thumb.width(), thumb.height()), 512);
    QCOMPARE(size, thumb.size());
    QCOMPARE(cachedFileCount("thumbs"), 1);
}

void TstFaceImageProvider::aMalformedIdYieldsNothing()
{
    const QString path = makePhoto("face.png", 400, 300, QRect(160, 90, 40, 30));

    // No query at all
    QVERIFY(m_provider->requestImage("crop", nullptr, QSize()).isNull());
    // A zero-sized bounding box, which would ask for a zero-pixel crop
    QVERIFY(m_provider->requestImage(cropId(path, 0.4, 0.3, 0.0, 0.0),
                                     nullptr, QSize()).isNull());
}

void TstFaceImageProvider::aMissingPhotoYieldsNothing()
{
    const QString path = m_dir->filePath("never-existed.png");

    QVERIFY(m_provider->requestImage(cropId(path, 0.4, 0.3, 0.1, 0.1),
                                     nullptr, QSize()).isNull());
    QVERIFY(m_provider->requestImage(thumbId(path), nullptr, QSize()).isNull());
}

QTEST_MAIN(TstFaceImageProvider)
#include "tst_faceimageprovider.moc"
