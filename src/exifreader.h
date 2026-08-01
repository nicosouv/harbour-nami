#ifndef EXIFREADER_H
#define EXIFREADER_H

#include <QString>
#include <QDateTime>

/**
 * @brief Minimal EXIF reader for JPEG capture dates and GPS location
 *
 * Qt has no public API for EXIF metadata, and file mtime resets whenever a
 * photo is copied or synced, which breaks date-based grouping (Events,
 * Memories). This parses just enough of the APP1/TIFF structure to read
 * DateTimeOriginal (0x9003), falling back to DateTime (0x0132), plus the
 * GPS IFD (tag 0x8825) for latitude/longitude when the camera recorded it.
 */
namespace ExifReader
{
    struct Metadata {
        QDateTime dateTaken;      // invalid when no usable EXIF date
        bool hasLocation = false;
        double latitude = 0.0;    // decimal degrees, +north/-south
        double longitude = 0.0;   // decimal degrees, +east/-west
    };

    /**
     * @brief Capture date and GPS location of a JPEG file
     */
    Metadata readMetadata(const QString &filePath);
}

#endif // EXIFREADER_H
