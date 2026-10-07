#ifndef GALLERYSCAN_H
#define GALLERYSCAN_H

#include <QSet>
#include <QString>
#include <QStringList>

/**
 * @brief Every image under the scanned folders, each file exactly once
 *
 * A file can be reached by more than one path: a symlink in the home folder
 * pointing at the SD card, scanned along with the card itself, makes every
 * photo on the card show up twice. Files are told apart by their resolved
 * path, so those are one photo.
 *
 * The path returned for a file is the one the database already knows it by,
 * when it does, so photos scanned through a link before keep their faces
 * and names instead of coming back as new ones. Otherwise it is the
 * resolved path.
 *
 * A directory is entered once, by its resolved path, so a link pointing back
 * at one of its own parents cannot send the walk round forever.
 *
 * Folders that do not exist, such as an SD card that is not mounted, are
 * skipped.
 */
QStringList collectGalleryImages(const QStringList &folders, bool recursive,
                                 const QSet<QString> &knownPaths);

#endif // GALLERYSCAN_H
