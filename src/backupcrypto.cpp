#include "backupcrypto.h"

#include <openssl/evp.h>
#include <openssl/rand.h>

namespace {

constexpr int kSaltLength = 16;
constexpr int kIvLength = 12;    // standard GCM nonce size
constexpr int kTagLength = 16;
constexpr int kKeyLength = 32;   // AES-256
constexpr int kIterations = 200000;

QByteArray randomBytes(int length)
{
    QByteArray bytes(length, '\0');
    if (RAND_bytes(reinterpret_cast<unsigned char *>(bytes.data()), length) != 1) {
        return QByteArray();
    }
    return bytes;
}

QByteArray deriveKey(const QString &passphrase, const QByteArray &salt, int iterations)
{
    QByteArray passphraseBytes = passphrase.toUtf8();
    QByteArray key(kKeyLength, '\0');

    int ok = PKCS5_PBKDF2_HMAC(passphraseBytes.constData(), passphraseBytes.size(),
                                reinterpret_cast<const unsigned char *>(salt.constData()), salt.size(),
                                iterations, EVP_sha256(), kKeyLength,
                                reinterpret_cast<unsigned char *>(key.data()));
    return ok == 1 ? key : QByteArray();
}

}

namespace BackupCrypto {

bool encrypt(const QByteArray &plaintext, const QString &passphrase, EncryptedPayload &out)
{
    QByteArray salt = randomBytes(kSaltLength);
    QByteArray iv = randomBytes(kIvLength);
    if (salt.isEmpty() || iv.isEmpty()) {
        return false;
    }

    QByteArray key = deriveKey(passphrase, salt, kIterations);
    if (key.isEmpty()) {
        return false;
    }

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return false;
    }

    bool ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, iv.size(), nullptr) == 1
        && EVP_EncryptInit_ex(ctx, nullptr, nullptr,
                               reinterpret_cast<const unsigned char *>(key.constData()),
                               reinterpret_cast<const unsigned char *>(iv.constData())) == 1;

    QByteArray ciphertext(plaintext.size() + kIvLength, '\0');
    int updateLen = 0;
    int totalLen = 0;

    if (ok) {
        ok = EVP_EncryptUpdate(ctx, reinterpret_cast<unsigned char *>(ciphertext.data()), &updateLen,
                                reinterpret_cast<const unsigned char *>(plaintext.constData()),
                                plaintext.size()) == 1;
        totalLen = updateLen;
    }

    int finalLen = 0;
    if (ok) {
        ok = EVP_EncryptFinal_ex(ctx, reinterpret_cast<unsigned char *>(ciphertext.data()) + totalLen,
                                  &finalLen) == 1;
        totalLen += finalLen;
    }

    QByteArray tag(kTagLength, '\0');
    if (ok) {
        ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, kTagLength, tag.data()) == 1;
    }

    EVP_CIPHER_CTX_free(ctx);

    if (!ok) {
        return false;
    }

    ciphertext.resize(totalLen);

    out.iterations = kIterations;
    out.salt = salt;
    out.iv = iv;
    out.tag = tag;
    out.ciphertext = ciphertext;
    return true;
}

QByteArray decrypt(const EncryptedPayload &payload, const QString &passphrase)
{
    if (payload.salt.isEmpty() || payload.iv.isEmpty() || payload.tag.size() != kTagLength
        || payload.iterations <= 0) {
        return QByteArray();
    }

    QByteArray key = deriveKey(passphrase, payload.salt, payload.iterations);
    if (key.isEmpty()) {
        return QByteArray();
    }

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return QByteArray();
    }

    bool ok = EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) == 1
        && EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, payload.iv.size(), nullptr) == 1
        && EVP_DecryptInit_ex(ctx, nullptr, nullptr,
                               reinterpret_cast<const unsigned char *>(key.constData()),
                               reinterpret_cast<const unsigned char *>(payload.iv.constData())) == 1;

    QByteArray plaintext(payload.ciphertext.size(), '\0');
    int updateLen = 0;
    int totalLen = 0;

    if (ok) {
        ok = EVP_DecryptUpdate(ctx, reinterpret_cast<unsigned char *>(plaintext.data()), &updateLen,
                                reinterpret_cast<const unsigned char *>(payload.ciphertext.constData()),
                                payload.ciphertext.size()) == 1;
        totalLen = updateLen;
    }

    if (ok) {
        // Cast away constness is required by this OpenSSL API, which
        // doesn't distinguish get/set direction in its signature
        ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, payload.tag.size(),
                                  const_cast<char *>(payload.tag.constData())) == 1;
    }

    int finalLen = 0;
    // A non-positive return means the tag didn't match: wrong passphrase or
    // tampered/corrupted data. Either way, nothing here can be trusted.
    int verified = ok
        ? EVP_DecryptFinal_ex(ctx, reinterpret_cast<unsigned char *>(plaintext.data()) + totalLen, &finalLen)
        : 0;

    EVP_CIPHER_CTX_free(ctx);

    if (verified <= 0) {
        return QByteArray();
    }

    totalLen += finalLen;
    plaintext.resize(totalLen);
    return plaintext;
}

}
