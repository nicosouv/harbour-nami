#ifndef EXIFREADER_H
#define EXIFREADER_H

#include <QString>
#include <QDateTime>

/**
 * @brief Minimal EXIF reader for JPEG capture dates
 *
 * Qt has no public API for EXIF dates, and file mtime resets whenever a
 * photo is copied or synced, which breaks date-based grouping (Events,
 * Memories). This parses just enough of the APP1/TIFF structure to read
 * DateTimeOriginal (0x9003), falling back to DateTime (0x0132).
 */
namespace ExifReader
{
    /**
     * @brief Capture date of a JPEG file
     * @return Invalid QDateTime when the file has no usable EXIF date
     */
    QDateTime dateTaken(const QString &filePath);
}

#endif // EXIFREADER_H
