#ifndef BACKUPCRYPTO_H
#define BACKUPCRYPTO_H

#include <QByteArray>
#include <QString>

/**
 * @brief Passphrase-based encryption for the device-migration backup
 *
 * AES-256-GCM (authenticated: tampering or a wrong passphrase both fail
 * decryption instead of silently returning garbage) with a key derived from
 * the passphrase via PBKDF2-HMAC-SHA256. Everything needed to decrypt other
 * than the passphrase itself (salt, IV, tag, iteration count) travels in
 * the payload, so there is no other secret to lose track of - except the
 * passphrase, which is never stored anywhere and can't be recovered if
 * forgotten.
 */
namespace BackupCrypto {

struct EncryptedPayload {
    int iterations = 0;
    QByteArray salt;
    QByteArray iv;
    QByteArray tag;
    QByteArray ciphertext;
};

/**
 * @brief Encrypt plaintext with a passphrase
 * @return false on failure (e.g. the platform's RNG or cipher init failed)
 */
bool encrypt(const QByteArray &plaintext, const QString &passphrase, EncryptedPayload &out);

/**
 * @brief Decrypt a payload previously produced by encrypt()
 * @return The plaintext, or a null QByteArray if the passphrase is wrong
 *         or the payload was tampered with/corrupted
 */
QByteArray decrypt(const EncryptedPayload &payload, const QString &passphrase);

}

#endif // BACKUPCRYPTO_H
