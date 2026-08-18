// Tests for the passphrase encryption wrapped around device-migration
// backups. A bug here is not a crash, it is a backup that cannot be read
// back - so this checks both that a good passphrase round-trips and that
// every way of getting it wrong fails loudly rather than returning garbage.

#include <QtTest>
#include "backupcrypto.h"

class TstBackupCrypto : public QObject
{
    Q_OBJECT

private slots:
    void roundTripsThePlaintext();
    void roundTripsALargeBackup();
    void refusesTheWrongPassphrase();
    void refusesTamperedCiphertext();
    void refusesATamperedTag();
    void refusesATruncatedPayload();
    void usesFreshSaltAndIvEveryTime();
    void handlesEmptyPlaintext();
};

void TstBackupCrypto::roundTripsThePlaintext()
{
    const QByteArray plaintext = "{\"app\":\"harbour-nami\",\"people\":[]}";
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt(plaintext, "correct horse", payload));

    QVERIFY(!payload.salt.isEmpty());
    QVERIFY(!payload.iv.isEmpty());
    QVERIFY(!payload.tag.isEmpty());
    QVERIFY(payload.iterations > 0);
    QVERIFY2(!payload.ciphertext.contains("harbour-nami"),
             "the plaintext is readable in the ciphertext");

    QCOMPARE(BackupCrypto::decrypt(payload, "correct horse"), plaintext);
}

void TstBackupCrypto::roundTripsALargeBackup()
{
    // A real backup carries every face embedding, so it is megabytes, not bytes
    QByteArray plaintext;
    plaintext.reserve(4 * 1024 * 1024);
    for (int i = 0; i < 100000; i++) {
        plaintext.append("0.1234,0.5678,-0.9012,");
    }

    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt(plaintext, "passphrase", payload));
    QCOMPARE(BackupCrypto::decrypt(payload, "passphrase"), plaintext);
}

void TstBackupCrypto::refusesTheWrongPassphrase()
{
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt("secret", "right", payload));

    QVERIFY2(BackupCrypto::decrypt(payload, "wrong").isNull(),
             "a wrong passphrase produced output instead of failing");
    QVERIFY(BackupCrypto::decrypt(payload, "").isNull());
    // Off by one character, and by case
    QVERIFY(BackupCrypto::decrypt(payload, "righ").isNull());
    QVERIFY(BackupCrypto::decrypt(payload, "Right").isNull());
}

void TstBackupCrypto::refusesTamperedCiphertext()
{
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt("the quick brown fox", "passphrase", payload));

    // Flip a single bit: AES-GCM is authenticated, this must not decrypt
    payload.ciphertext[0] = payload.ciphertext.at(0) ^ 0x01;
    QVERIFY2(BackupCrypto::decrypt(payload, "passphrase").isNull(),
             "tampered ciphertext decrypted anyway");
}

void TstBackupCrypto::refusesATamperedTag()
{
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt("the quick brown fox", "passphrase", payload));

    payload.tag[0] = payload.tag.at(0) ^ 0x01;
    QVERIFY(BackupCrypto::decrypt(payload, "passphrase").isNull());
}

void TstBackupCrypto::refusesATruncatedPayload()
{
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt("the quick brown fox", "passphrase", payload));

    BackupCrypto::EncryptedPayload truncated = payload;
    truncated.ciphertext.chop(1);
    QVERIFY(BackupCrypto::decrypt(truncated, "passphrase").isNull());

    BackupCrypto::EncryptedPayload noSalt = payload;
    noSalt.salt.clear();
    QVERIFY(BackupCrypto::decrypt(noSalt, "passphrase").isNull());
}

void TstBackupCrypto::usesFreshSaltAndIvEveryTime()
{
    BackupCrypto::EncryptedPayload first;
    BackupCrypto::EncryptedPayload second;
    QVERIFY(BackupCrypto::encrypt("same input", "same passphrase", first));
    QVERIFY(BackupCrypto::encrypt("same input", "same passphrase", second));

    // Reusing a salt would make two backups share a key, reusing an IV with
    // the same key would break GCM outright
    QVERIFY2(first.salt != second.salt, "the salt is not random");
    QVERIFY2(first.iv != second.iv, "the IV is not random");
    QVERIFY2(first.ciphertext != second.ciphertext, "identical ciphertext for identical input");
}

void TstBackupCrypto::handlesEmptyPlaintext()
{
    BackupCrypto::EncryptedPayload payload;
    QVERIFY(BackupCrypto::encrypt(QByteArray(), "passphrase", payload));
    QCOMPARE(BackupCrypto::decrypt(payload, "passphrase"), QByteArray());
}

QTEST_MAIN(TstBackupCrypto)
#include "tst_backupcrypto.moc"
