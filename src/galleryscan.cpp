#include "galleryscan.h"
#include <QDir>
#include <QFileInfo>
#include <QHash>

namespace {

struct Walk
{
    QHash<QString, QString> knownByResolved;
    QSet<QString> visitedDirs;
    QSet<QString> seenFiles;
    QStringList images;
    bool recursive = true;

    void enter(const QString &resolvedDir)
    {
        static const QStringList nameFilters = {
            QStringLiteral("*.jpg"), QStringLiteral("*.jpeg"), QStringLiteral("*.png"),
            QStringLiteral("*.bmp"), QStringLiteral("*.gif")
        };

        QDir::Filters filters = QDir::Files | QDir::Readable;
        if (recursive) {
            filters |= QDir::AllDirs | QDir::NoDotAndDotDot;
        }

        const QFileInfoList entries = QDir(resolvedDir).entryInfoList(nameFilters, filters);
        for (const QFileInfo &entry : entries) {
            // Empty for a dangling link
            const QString resolved = entry.canonicalFilePath();
            if (resolved.isEmpty()) {
                continue;
            }

            if (entry.isDir()) {
                if (!visitedDirs.contains(resolved)) {
                    visitedDirs.insert(resolved);
                    enter(resolved);
                }
            } else if (!seenFiles.contains(resolved)) {
                seenFiles.insert(resolved);
                images.append(knownByResolved.value(resolved, resolved));
            }
        }
    }
};

}  // namespace

QStringList collectGalleryImages(const QStringList &folders, bool recursive,
                                 const QSet<QString> &knownPaths)
{
    Walk walk;
    walk.recursive = recursive;

    // Should two known paths already be the same file, from before files
    // were told apart this way, the first one keeps it and the other is
    // left as it is: neither rescanned nor removed
    for (const QString &known : knownPaths) {
        const QString resolved = QFileInfo(known).canonicalFilePath();
        if (!resolved.isEmpty() && !walk.knownByResolved.contains(resolved)) {
            walk.knownByResolved.insert(resolved, known);
        }
    }

    for (const QString &folder : folders) {
        if (folder.isEmpty()) {
            continue;
        }
        const QString resolved = QFileInfo(folder).canonicalFilePath();
        if (resolved.isEmpty() || walk.visitedDirs.contains(resolved)) {
            continue;
        }
        walk.visitedDirs.insert(resolved);
        walk.enter(resolved);
    }

    return walk.images;
}
