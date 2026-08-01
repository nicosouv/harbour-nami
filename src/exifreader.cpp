#include "exifreader.h"

#include <QFile>
#include <QtEndian>

namespace {

quint16 readU16(const QByteArray &data, int offset, bool littleEndian)
{
    if (offset < 0 || offset + 2 > data.size()) {
        return 0;
    }
    const uchar *p = reinterpret_cast<const uchar *>(data.constData() + offset);
    return littleEndian ? qFromLittleEndian<quint16>(p) : qFromBigEndian<quint16>(p);
}

quint32 readU32(const QByteArray &data, int offset, bool littleEndian)
{
    if (offset < 0 || offset + 4 > data.size()) {
        return 0;
    }
    const uchar *p = reinterpret_cast<const uchar *>(data.constData() + offset);
    return littleEndian ? qFromLittleEndian<quint32>(p) : qFromBigEndian<quint32>(p);
}

// Scan one IFD; returns the ASCII value of wantedTag ("" if absent) and
// fills exifIfdOffset/gpsIfdOffset when the respective pointer tags
// (0x8769 ExifIFD, 0x8825 GPS IFD) are present
QString scanIfd(const QByteArray &tiff, quint32 ifdOffset, bool le,
                quint16 wantedTag, quint32 *exifIfdOffset, quint32 *gpsIfdOffset)
{
    quint16 entryCount = readU16(tiff, ifdOffset, le);
    if (entryCount == 0 || entryCount > 512) {
        return QString();
    }

    QString value;
    for (int i = 0; i < entryCount; i++) {
        int entry = ifdOffset + 2 + i * 12;
        quint16 tag = readU16(tiff, entry, le);
        quint16 type = readU16(tiff, entry + 2, le);
        quint32 count = readU32(tiff, entry + 4, le);

        if (exifIfdOffset && tag == 0x8769) {
            *exifIfdOffset = readU32(tiff, entry + 8, le);
        }
        if (gpsIfdOffset && tag == 0x8825) {
            *gpsIfdOffset = readU32(tiff, entry + 8, le);
        }

        // type 2 = ASCII; EXIF datetimes are 20 bytes "YYYY:MM:DD HH:MM:SS\0"
        if (tag == wantedTag && type == 2 && count > 0 && count <= 32) {
            quint32 valueOffset = (count <= 4)
                ? static_cast<quint32>(entry + 8)
                : readU32(tiff, entry + 8, le);
            if (valueOffset + count <= static_cast<quint32>(tiff.size())) {
                value = QString::fromLatin1(tiff.constData() + valueOffset, count - 1).trimmed();
            }
        }
    }

    return value;
}

QDateTime parseExifDate(const QString &value)
{
    // "YYYY:MM:DD HH:MM:SS"; some cameras write empty/space-filled fields
    QDateTime dt = QDateTime::fromString(value, "yyyy:MM:dd HH:mm:ss");
    if (dt.isValid() && dt.date().year() > 1970) {
        return dt;
    }
    return QDateTime();
}

// Three consecutive RATIONAL values (degrees, minutes, seconds), 8 bytes each
bool readRationalTriplet(const QByteArray &tiff, quint32 offset, bool le, double out[3])
{
    if (offset + 24 > static_cast<quint32>(tiff.size())) {
        return false;
    }
    for (int i = 0; i < 3; i++) {
        quint32 num = readU32(tiff, offset + i * 8, le);
        quint32 den = readU32(tiff, offset + i * 8 + 4, le);
        out[i] = den != 0 ? static_cast<double>(num) / den : 0.0;
    }
    return true;
}

// GPS IFD: GPSLatitudeRef/GPSLatitude (0x0001/0x0002) and
// GPSLongitudeRef/GPSLongitude (0x0003/0x0004) as degrees/minutes/seconds
bool scanGpsIfd(const QByteArray &tiff, quint32 ifdOffset, bool le,
                double *outLatitude, double *outLongitude)
{
    quint16 entryCount = readU16(tiff, ifdOffset, le);
    if (entryCount == 0 || entryCount > 512) {
        return false;
    }

    QString latRef, lonRef;
    double latDms[3] = {0.0, 0.0, 0.0};
    double lonDms[3] = {0.0, 0.0, 0.0};
    bool haveLat = false;
    bool haveLon = false;

    for (int i = 0; i < entryCount; i++) {
        int entry = ifdOffset + 2 + i * 12;
        quint16 tag = readU16(tiff, entry, le);
        quint16 type = readU16(tiff, entry + 2, le);
        quint32 count = readU32(tiff, entry + 4, le);
        quint32 valueOffset = readU32(tiff, entry + 8, le);

        if ((tag == 0x0001 || tag == 0x0003) && type == 2 && count > 0 && count <= 8) {
            quint32 vo = (count <= 4) ? static_cast<quint32>(entry + 8) : valueOffset;
            if (vo + count <= static_cast<quint32>(tiff.size())) {
                QString ref = QString::fromLatin1(tiff.constData() + vo, count - 1).trimmed().toUpper();
                if (tag == 0x0001) {
                    latRef = ref;
                } else {
                    lonRef = ref;
                }
            }
        } else if (tag == 0x0002 && type == 5 && count == 3) {
            haveLat = readRationalTriplet(tiff, valueOffset, le, latDms);
        } else if (tag == 0x0004 && type == 5 && count == 3) {
            haveLon = readRationalTriplet(tiff, valueOffset, le, lonDms);
        }
    }

    if (!haveLat || !haveLon || latRef.isEmpty() || lonRef.isEmpty()) {
        return false;
    }

    double lat = latDms[0] + latDms[1] / 60.0 + latDms[2] / 3600.0;
    double lon = lonDms[0] + lonDms[1] / 60.0 + lonDms[2] / 3600.0;
    if (latRef == "S") {
        lat = -lat;
    }
    if (lonRef == "W") {
        lon = -lon;
    }

    *outLatitude = lat;
    *outLongitude = lon;
    return true;
}

} // namespace

ExifReader::Metadata ExifReader::readMetadata(const QString &filePath)
{
    Metadata result;

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return result;
    }

    // EXIF APP1 sits near the start of the file
    QByteArray head = file.read(256 * 1024);
    file.close();

    if (head.size() < 4 || static_cast<uchar>(head[0]) != 0xFF
        || static_cast<uchar>(head[1]) != 0xD8) {
        return result;  // not a JPEG
    }

    // Walk JPEG segments looking for APP1 "Exif\0\0"
    int pos = 2;
    int tiffStart = -1;
    int tiffSize = 0;
    while (pos + 4 <= head.size()) {
        if (static_cast<uchar>(head[pos]) != 0xFF) {
            break;
        }
        uchar marker = static_cast<uchar>(head[pos + 1]);
        if (marker == 0xDA || marker == 0xD9) {
            break;  // image data reached, no EXIF
        }

        int segmentLength = (static_cast<uchar>(head[pos + 2]) << 8)
                          | static_cast<uchar>(head[pos + 3]);
        if (segmentLength < 2) {
            break;
        }

        if (marker == 0xE1 && pos + 10 <= head.size()
            && head.mid(pos + 4, 6) == QByteArray("Exif\0\0", 6)) {
            tiffStart = pos + 10;
            tiffSize = segmentLength - 8;
            break;
        }

        pos += 2 + segmentLength;
    }

    if (tiffStart < 0 || tiffStart + tiffSize > head.size() || tiffSize < 8) {
        return result;
    }

    QByteArray tiff = head.mid(tiffStart, tiffSize);

    // TIFF header: byte order, magic 42, IFD0 offset
    bool le;
    if (tiff.startsWith("II")) {
        le = true;
    } else if (tiff.startsWith("MM")) {
        le = false;
    } else {
        return result;
    }
    if (readU16(tiff, 2, le) != 42) {
        return result;
    }

    quint32 ifd0Offset = readU32(tiff, 4, le);
    quint32 exifIfdOffset = 0;
    quint32 gpsIfdOffset = 0;

    // IFD0: DateTime (0x0132) as fallback, plus the ExifIFD/GPS IFD pointers
    QString dateTime = scanIfd(tiff, ifd0Offset, le, 0x0132, &exifIfdOffset, &gpsIfdOffset);

    // ExifIFD: DateTimeOriginal (0x9003) is the actual capture time
    if (exifIfdOffset > 0) {
        QString original = scanIfd(tiff, exifIfdOffset, le, 0x9003, nullptr, nullptr);
        if (!original.isEmpty()) {
            dateTime = original;
        }
    }

    result.dateTaken = parseExifDate(dateTime);

    if (gpsIfdOffset > 0) {
        double lat = 0.0, lon = 0.0;
        if (scanGpsIfd(tiff, gpsIfdOffset, le, &lat, &lon)) {
            result.hasLocation = true;
            result.latitude = lat;
            result.longitude = lon;
        }
    }

    return result;
}
