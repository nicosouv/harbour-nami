// Unit tests for the content hash. It is what lets a restored backup find a
// photo again after a device migration moved or renamed it, so the digest
// has to be a plain SHA-256 of the bytes and nothing else: salt it, encode
// it differently or hash the path along with it, and every relink on the
// next restore silently misses.

#include <QtTest>
#include <QTemporaryDir>
#include <QFile>
#include <QCryptographicHash>

#include "filehash.h"

class TstFileHash : public QObject
{
    Q_OBJECT

private slots:
    void init();
    void cleanup();

    void matchesTheKnownSha256OfItsContent();
    void hashesAnEmptyFileToTheEmptyDigest();
    void sameContentUnderDifferentNamesMatches();
    void oneFlippedByteChangesTheDigest();
    void spansContentLargerThanOneReadBuffer();
    void missingFileReturnsEmpty();

private:
    QString write(const QByteArray &bytes, const QString &name);

    QTemporaryDir *m_dir = nullptr;
};

void TstFileHash::init()
{
    m_dir = new QTemporaryDir;
    QVERIFY(m_dir->isValid());
}

void TstFileHash::cleanup()
{
    delete m_dir;
    m_dir = nullptr;
}

QString TstFileHash::write(const QByteArray &bytes, const QString &name)
{
    const QString path = m_dir->filePath(name);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(bytes);
        file.close();
    }
    return path;
}

void TstFileHash::matchesTheKnownSha256OfItsContent()
{
    // The published SHA-256 of "abc": pins the algorithm and the lowercase
    // hex encoding, not just self-consistency
    QCOMPARE(computeFileSha256(write("abc", "abc.bin")),
             QStringLiteral("ba7816bf8f01cfea414140de5dae2223"
                            "b00361a396177a9cb410ff61f20015ad"));
}

void TstFileHash::hashesAnEmptyFileToTheEmptyDigest()
{
    QCOMPARE(computeFileSha256(write(QByteArray(), "empty.bin")),
             QStringLiteral("e3b0c44298fc1c149afbf4c8996fb924"
                            "27ae41e4649b934ca495991b7852b855"));
}

void TstFileHash::sameContentUnderDifferentNamesMatches()
{
    // The whole point: a photo that moved from one card layout to another
    const QByteArray content = "the same photo, a different path";
    QCOMPARE(computeFileSha256(write(content, "DCIM_0001.jpg")),
             computeFileSha256(write(content, "holiday-2019.jpg")));
}

void TstFileHash::oneFlippedByteChangesTheDigest()
{
    QVERIFY(computeFileSha256(write("photo bytes", "a.bin"))
            != computeFileSha256(write("photo bytesX", "b.bin")));
}

void TstFileHash::spansContentLargerThanOneReadBuffer()
{
    // Real photos are megabytes; a chunked digest that mishandles a boundary
    // still looks right on the small inputs above
    QByteArray big;
    big.reserve(5 * 1024 * 1024);
    for (int i = 0; i < 5 * 1024; i++) {
        big += QByteArray(1024, static_cast<char>(i & 0xFF));
    }

    const QString hash = computeFileSha256(write(big, "big.bin"));

    QCOMPARE(hash.size(), 64);
    QCOMPARE(hash, QString::fromLatin1(
                 QCryptographicHash::hash(big, QCryptographicHash::Sha256).toHex()));
}

void TstFileHash::missingFileReturnsEmpty()
{
    QVERIFY(computeFileSha256(m_dir->filePath("no-such-file.bin")).isEmpty());
}

QTEST_MAIN(TstFileHash)
#include "tst_filehash.moc"
