// Unit tests for the gallery walk. Each case is a layout found on a real
// phone: an SD card linked into the home folder and scanned alongside it,
// a link pointing back at its own parent, a card that is not mounted. The
// rule they share is that a photo is one photo, however many paths lead to
// it, and that a photo the database already holds keeps the path it is
// stored under, or its faces and names would come back as a new photo.

#include <QtTest>
#include <QTemporaryDir>
#include <QFile>

#include "galleryscan.h"

class TstGalleryScan : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void listsImagesOnlyWhateverTheCase();
    void overlappingFoldersListEachPhotoOnce();
    void linkAndTargetScannedTogetherListEachPhotoOnce();
    void photoKnownThroughALinkKeepsThatPath();
    void linkBackToAParentDoesNotLoop();
    void missingFolderIsSkipped();
    void danglingLinkIsIgnored();
    void nonRecursiveStaysInTheFolder();

private:
    QString path(const QString &relative) const;
    void touch(const QString &relative);
    void mkdir(const QString &relative);
    void link(const QString &target, const QString &relative);

    QTemporaryDir *m_dir = nullptr;
    // The temporary folder itself may sit behind a link (/tmp on macOS), so
    // expectations are written against its resolved form
    QString m_root;
};

void TstGalleryScan::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
    m_root = QFileInfo(m_dir->path()).canonicalFilePath();
}

void TstGalleryScan::cleanup()
{
    delete m_dir;
    m_dir = nullptr;
}

QString TstGalleryScan::path(const QString &relative) const
{
    return m_root + QLatin1Char('/') + relative;
}

void TstGalleryScan::touch(const QString &relative)
{
    QFile file(path(relative));
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write("x");
}

void TstGalleryScan::mkdir(const QString &relative)
{
    QVERIFY(QDir().mkpath(path(relative)));
}

void TstGalleryScan::link(const QString &target, const QString &relative)
{
    QVERIFY(QFile::link(path(target), path(relative)));
}

void TstGalleryScan::listsImagesOnlyWhateverTheCase()
{
    // A vfat card written by a camera often names its files in capitals
    mkdir("card/DCIM");
    touch("card/DCIM/IMG_0001.JPG");
    touch("card/DCIM/beach.jpeg");
    touch("card/DCIM/notes.txt");

    QStringList found = collectGalleryImages({path("card")}, true, {});
    found.sort();
    QCOMPARE(found, QStringList({path("card/DCIM/IMG_0001.JPG"),
                                 path("card/DCIM/beach.jpeg")}));
}

void TstGalleryScan::overlappingFoldersListEachPhotoOnce()
{
    mkdir("Pictures/Camera");
    touch("Pictures/Camera/a.jpg");

    // Child first, then parent, and the other way round
    QCOMPARE(collectGalleryImages({path("Pictures/Camera"), path("Pictures")}, true, {}).size(), 1);
    QCOMPARE(collectGalleryImages({path("Pictures"), path("Pictures/Camera")}, true, {}).size(), 1);
}

void TstGalleryScan::linkAndTargetScannedTogetherListEachPhotoOnce()
{
    mkdir("card/Pictures");
    touch("card/Pictures/a.jpg");
    mkdir("home/Pictures");
    link("card", "home/Pictures/sd");

    const QStringList found = collectGalleryImages({path("home/Pictures"), path("card")}, true, {});
    QCOMPARE(found, QStringList({path("card/Pictures/a.jpg")}));
}

void TstGalleryScan::photoKnownThroughALinkKeepsThatPath()
{
    mkdir("card/Pictures");
    touch("card/Pictures/a.jpg");
    touch("card/Pictures/b.jpg");
    mkdir("home/Pictures");
    link("card", "home/Pictures/sd");

    // a.jpg was scanned through the link before the card itself was added
    const QSet<QString> known = {path("home/Pictures/sd/Pictures/a.jpg")};

    QStringList found = collectGalleryImages({path("card"), path("home/Pictures")}, true, known);
    found.sort();
    QCOMPARE(found, QStringList({path("card/Pictures/b.jpg"),
                                 path("home/Pictures/sd/Pictures/a.jpg")}));
}

void TstGalleryScan::linkBackToAParentDoesNotLoop()
{
    mkdir("card/DCIM");
    touch("card/DCIM/a.jpg");
    link("card", "card/DCIM/up");

    QCOMPARE(collectGalleryImages({path("card")}, true, {}),
             QStringList({path("card/DCIM/a.jpg")}));
}

void TstGalleryScan::missingFolderIsSkipped()
{
    mkdir("Pictures");
    touch("Pictures/a.jpg");

    // A card that was in the list but is not in the phone right now
    QCOMPARE(collectGalleryImages({path("card-not-mounted"), path("Pictures")}, true, {}),
             QStringList({path("Pictures/a.jpg")}));
}

void TstGalleryScan::danglingLinkIsIgnored()
{
    mkdir("Pictures");
    touch("Pictures/a.jpg");
    link("gone.jpg", "Pictures/b.jpg");
    link("gone", "Pictures/old-card");

    QCOMPARE(collectGalleryImages({path("Pictures")}, true, {}),
             QStringList({path("Pictures/a.jpg")}));
}

void TstGalleryScan::nonRecursiveStaysInTheFolder()
{
    mkdir("Pictures/Camera");
    touch("Pictures/a.jpg");
    touch("Pictures/Camera/b.jpg");

    QCOMPARE(collectGalleryImages({path("Pictures")}, false, {}),
             QStringList({path("Pictures/a.jpg")}));
}

QTEST_GUILESS_MAIN(TstGalleryScan)
#include "tst_galleryscan.moc"
