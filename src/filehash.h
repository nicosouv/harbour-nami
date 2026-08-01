#ifndef FILEHASH_H
#define FILEHASH_H

#include <QString>

/**
 * @brief SHA-256 of a file's raw bytes, hex-encoded
 *
 * Content-based identity for a photo, independent of its path: lets a
 * restored backup find a photo that was moved or renamed (e.g. a
 * different SD card layout after a device migration).
 *
 * @return Empty string if the file can't be read
 */
QString computeFileSha256(const QString &filePath);

#endif // FILEHASH_H
