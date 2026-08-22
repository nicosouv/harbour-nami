// Unit tests for the minimal EXIF reader. It decides the capture date of
// every photo, so it decides every Event and every Memory: a photo whose
// date falls back to file mtime lands in the wrong day after any copy or
// sync, and no amount of correct grouping code can recover from that.
//
// The fixtures are built here byte by byte rather than committed as JPEGs,
// so a case is readable and diffable instead of being an opaque blob, and
// so hostile input (truncated segment, absurd entry count) can be shaped
// exactly.

#include <QtTest>
#include <QTemporaryDir>
#include <QDateTime>
#include <QFile>
#include <QtEndian>

#include "exifreader.h"

namespace {

QByteArray u16(quint16 value, bool littleEndian)
{
    QByteArray out(2, '\0');
    uchar *p = reinterpret_cast<uchar *>(out.data());
    if (littleEndian) {
        qToLittleEndian(value, p);
    } else {
        qToBigEndian(value, p);
    }
    return out;
}

QByteArray u32(quint32 value, bool littleEndian)
{
    QByteArray out(4, '\0');
    uchar *p = reinterpret_cast<uchar *>(out.data());
    if (littleEndian) {
        qToLittleEndian(value, p);
    } else {
        qToBigEndian(value, p);
    }
    return out;
}

// One 12-byte IFD entry. Four bytes or less of value sit in the entry
// itself; anything longer lives in the data area and the entry carries its
// offset instead.
QByteArray ifdEntry(quint16 tag, quint16 type, quint32 count,
                    const QByteArray &valueField, bool le)
{
    QByteArray entry;
    entry += u16(tag, le);
    entry += u16(type, le);
    entry += u32(count, le);
    entry += valueField.leftJustified(4, '\0', true);
    return entry;
}

struct ExifSpec {
    bool littleEndian = true;
    QByteArray dateTime = "2023:08:14 18:32:10";           // IFD0, 0x0132
    QByteArray dateTimeOriginal = "2019:03:02 07:05:00";   // ExifIFD, 0x9003
    bool withExifIfd = true;
    bool withGps = true;
    QByteArray latRef = "N";
    QByteArray lonRef = "E";
    // Degrees, minutes, seconds as RATIONAL pairs: 48°51'24" N, 2°21'03" E
    quint32 lat[6] = { 48, 1, 51, 1, 24, 1 };
    quint32 lon[6] = { 2, 1, 21, 1, 3, 1 };
};

// SOI, one APP1 segment carrying the TIFF block, EOI. The segment length is
// always big endian: that is JPEG structure, not TIFF byte order.
QByteArray wrapInJpeg(const QByteArray &tiff)
{
    const int segmentLength = 2 + 6 + tiff.size();

    QByteArray jpeg;
    jpeg += QByteArray::fromHex("FFD8");
    jpeg += QByteArray::fromHex("FFE1");
    jpeg += static_cast<char>((segmentLength >> 8) & 0xFF);
    jpeg += static_cast<char>(segmentLength & 0xFF);
    jpeg += QByteArray("Exif\0\0", 6);
    jpeg += tiff;
    jpeg += QByteArray::fromHex("FFD9");
    return jpeg;
}

QByteArray makeExifJpeg(const ExifSpec &spec)
{
    const bool le = spec.littleEndian;
    const bool hasDateTime = !spec.dateTime.isEmpty();

    const int n0 = (hasDateTime ? 1 : 0) + (spec.withExifIfd ? 1 : 0)
                 + (spec.withGps ? 1 : 0);
    const int n1 = spec.withExifIfd ? 1 : 0;
    const int n2 = spec.withGps ? 4 : 0;

    // Every IFD's size is known from its entry count, so the offsets can be
    // worked out before a single byte is written
    const int ifd0Offset = 8;
    const int ifd0Size = 2 + 12 * n0 + 4;
    const int exifIfdOffset = ifd0Offset + ifd0Size;
    const int exifIfdSize = spec.withExifIfd ? 2 + 12 * n1 + 4 : 0;
    const int gpsIfdOffset = exifIfdOffset + exifIfdSize;
    const int gpsIfdSize = spec.withGps ? 2 + 12 * n2 + 4 : 0;
    const int dataOffset = gpsIfdOffset + gpsIfdSize;

    QByteArray data;

    const int dateTimeAt = dataOffset + data.size();
    if (hasDateTime) {
        data += spec.dateTime;
        data += '\0';
    }

    const int originalAt = dataOffset + data.size();
    if (spec.withExifIfd) {
        data += spec.dateTimeOriginal;
        data += '\0';
    }

    const int latAt = dataOffset + data.size();
    if (spec.withGps) {
        for (int i = 0; i < 6; i++) {
            data += u32(spec.lat[i], le);
        }
    }

    const int lonAt = dataOffset + data.size();
    if (spec.withGps) {
        for (int i = 0; i < 6; i++) {
            data += u32(spec.lon[i], le);
        }
    }

    QByteArray ifd0 = u16(n0, le);
    if (hasDateTime) {
        ifd0 += ifdEntry(0x0132, 2, spec.dateTime.size() + 1, u32(dateTimeAt, le), le);
    }
    if (spec.withExifIfd) {
        ifd0 += ifdEntry(0x8769, 4, 1, u32(exifIfdOffset, le), le);
    }
    if (spec.withGps) {
        ifd0 += ifdEntry(0x8825, 4, 1, u32(gpsIfdOffset, le), le);
    }
    ifd0 += u32(0, le);  // no IFD1

    QByteArray exifIfd;
    if (spec.withExifIfd) {
        exifIfd = u16(n1, le);
        exifIfd += ifdEntry(0x9003, 2, spec.dateTimeOriginal.size() + 1,
                            u32(originalAt, le), le);
        exifIfd += u32(0, le);
    }

    QByteArray gpsIfd;
    if (spec.withGps) {
        gpsIfd = u16(n2, le);
        gpsIfd += ifdEntry(0x0001, 2, 2, spec.latRef, le);
        gpsIfd += ifdEntry(0x0002, 5, 3, u32(latAt, le), le);
        gpsIfd += ifdEntry(0x0003, 2, 2, spec.lonRef, le);
        gpsIfd += ifdEntry(0x0004, 5, 3, u32(lonAt, le), le);
        gpsIfd += u32(0, le);
    }

    QByteArray tiff = le ? QByteArray("II") : QByteArray("MM");
    tiff += u16(42, le);
    tiff += u32(ifd0Offset, le);
    tiff += ifd0;
    tiff += exifIfd;
    tiff += gpsIfd;
    tiff += data;

    return wrapInJpeg(tiff);
}

}  // namespace

class TstExifReader : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void prefersDateTimeOriginalOverDateTime();
    void fallsBackToDateTimeWithoutAnExifIfd();
    void readsBigEndianFilesTheSameWay();
    void readsGpsAsDecimalDegrees();
    void southAndWestComeOutNegative();
    void readsFractionalGpsSeconds();
    void reportsNoLocationWithoutAGpsIfd();
    void rejectsPlaceholderDates();
    void rejectsAFileThatIsNotAJpeg();
    void rejectsAJpegCarryingNoExif();
    void survivesATruncatedExifSegment();
    void survivesAnAbsurdEntryCount();
    void missingFileYieldsNothing();

private:
    QString write(const QByteArray &bytes, const QString &name = "photo.jpg");

    QTemporaryDir *m_dir = nullptr;
};

void TstExifReader::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
}

void TstExifReader::cleanup()
{
    delete m_dir;
    m_dir = nullptr;
}

QString TstExifReader::write(const QByteArray &bytes, const QString &name)
{
    const QString path = m_dir->filePath(name);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(bytes);
        file.close();
    }
    return path;
}

void TstExifReader::prefersDateTimeOriginalOverDateTime()
{
    ExifSpec spec;
    // IFD0 carries the file's last-modified date, which an editor rewrites;
    // only the ExifIFD holds when the shutter actually fired
    spec.dateTime = "2023:08:14 18:32:10";
    spec.dateTimeOriginal = "2019:03:02 07:05:00";

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QVERIFY(meta.dateTaken.isValid());
    QCOMPARE(meta.dateTaken, QDateTime(QDate(2019, 3, 2), QTime(7, 5, 0)));
}

void TstExifReader::fallsBackToDateTimeWithoutAnExifIfd()
{
    ExifSpec spec;
    spec.withExifIfd = false;

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QVERIFY(meta.dateTaken.isValid());
    QCOMPARE(meta.dateTaken, QDateTime(QDate(2023, 8, 14), QTime(18, 32, 10)));
}

void TstExifReader::readsBigEndianFilesTheSameWay()
{
    ExifSpec spec;
    spec.littleEndian = false;

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QCOMPARE(meta.dateTaken, QDateTime(QDate(2019, 3, 2), QTime(7, 5, 0)));
    QVERIFY(meta.hasLocation);
    QVERIFY(qAbs(meta.latitude - 48.856667) < 1e-5);
}

void TstExifReader::readsGpsAsDecimalDegrees()
{
    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(ExifSpec())));

    QVERIFY(meta.hasLocation);
    // 48°51'24" N -> 48 + 51/60 + 24/3600
    QVERIFY(qAbs(meta.latitude - 48.856667) < 1e-5);
    // 2°21'03" E -> 2 + 21/60 + 3/3600
    QVERIFY(qAbs(meta.longitude - 2.350833) < 1e-5);
}

void TstExifReader::southAndWestComeOutNegative()
{
    ExifSpec spec;
    spec.latRef = "S";
    spec.lonRef = "W";

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QVERIFY(meta.hasLocation);
    QVERIFY(qAbs(meta.latitude + 48.856667) < 1e-5);
    QVERIFY(qAbs(meta.longitude + 2.350833) < 1e-5);
}

void TstExifReader::readsFractionalGpsSeconds()
{
    ExifSpec spec;
    // Phones commonly write seconds as a fraction rather than a whole number
    spec.lat[4] = 2450;
    spec.lat[5] = 100;   // 24.5 seconds

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QVERIFY(meta.hasLocation);
    QVERIFY(qAbs(meta.latitude - (48.0 + 51.0 / 60.0 + 24.5 / 3600.0)) < 1e-6);
}

void TstExifReader::reportsNoLocationWithoutAGpsIfd()
{
    ExifSpec spec;
    spec.withGps = false;

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(makeExifJpeg(spec)));

    QVERIFY(meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
    QCOMPARE(meta.latitude, 0.0);
    QCOMPARE(meta.longitude, 0.0);
}

void TstExifReader::rejectsPlaceholderDates()
{
    // Cameras with a dead clock write these; taking them at face value drops
    // the photo into 1970 and invents an Event nobody lived
    ExifSpec spec;
    spec.withExifIfd = false;

    spec.dateTime = "0000:00:00 00:00:00";
    QVERIFY(!ExifReader::readMetadata(write(makeExifJpeg(spec), "zero.jpg")).dateTaken.isValid());

    spec.dateTime = "1970:01:01 00:00:00";
    QVERIFY(!ExifReader::readMetadata(write(makeExifJpeg(spec), "epoch.jpg")).dateTaken.isValid());
}

void TstExifReader::rejectsAFileThatIsNotAJpeg()
{
    const ExifReader::Metadata meta =
        ExifReader::readMetadata(write("this is a text file, not a photo"));

    QVERIFY(!meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
}

void TstExifReader::rejectsAJpegCarryingNoExif()
{
    // SOI then straight to EOI: a valid JPEG shell with no APP1 at all
    const ExifReader::Metadata meta =
        ExifReader::readMetadata(write(QByteArray::fromHex("FFD8FFD9")));

    QVERIFY(!meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
}

void TstExifReader::survivesATruncatedExifSegment()
{
    // The APP1 header still claims a full segment, but the file stops mid
    // TIFF block. A reader that trusts the declared length walks off the end.
    QByteArray jpeg = makeExifJpeg(ExifSpec());
    jpeg.truncate(30);

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(jpeg));

    QVERIFY(!meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
}

void TstExifReader::survivesAnAbsurdEntryCount()
{
    QByteArray jpeg = makeExifJpeg(ExifSpec());

    // IFD0's entry count sits at TIFF offset 8, and the TIFF block starts 12
    // bytes into the file. Claim 65535 entries over a handful of bytes.
    jpeg[12 + 8] = static_cast<char>(0xFF);
    jpeg[12 + 9] = static_cast<char>(0xFF);

    const ExifReader::Metadata meta = ExifReader::readMetadata(write(jpeg));

    QVERIFY(!meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
}

void TstExifReader::missingFileYieldsNothing()
{
    const ExifReader::Metadata meta =
        ExifReader::readMetadata(m_dir->filePath("no-such-photo.jpg"));

    QVERIFY(!meta.dateTaken.isValid());
    QVERIFY(!meta.hasLocation);
}

QTEST_MAIN(TstExifReader)
#include "tst_exifreader.moc"
