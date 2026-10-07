// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// AES-256-GCM under non-exportable AndroidKeyStore keys, one key per
// [KeyProfile]. Hardware backing (TEE/StrongBox) depends on the device and is
// NOT claimed; see doc/CLAIM_BOUNDARY.md.

package com.yardenah.pqkeystore

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import java.security.KeyStore
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class AndroidKeystoreSealer : Sealer {
    private val keyStore: KeyStore by lazy {
        try {
            KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        } catch (e: Exception) {
            throw Contract.Violation(Contract.ERR_UNAVAILABLE, "AndroidKeyStore unavailable")
        }
    }

    override fun seal(profile: KeyProfile, aad: ByteArray, plaintext: ByteArray): Sealer.Sealed {
        val key = key(profile, create = true)
        val n = chunksFor(plaintext.size)
        return mapErrors {
            val ivs = ByteArray(n * IV_BYTES)
            val out = java.io.ByteArrayOutputStream()
            for (i in 0 until n) {
                val chunkLen = kotlin.math.min(CHUNK_PLAINTEXT, plaintext.size - i * CHUNK_PLAINTEXT)
                val cipher = Cipher.getInstance(TRANSFORMATION)
                // The keystore generates the IV (randomized encryption required).
                cipher.init(Cipher.ENCRYPT_MODE, key)
                cipher.updateAAD(aad)
                cipher.updateAAD(byteArrayOf(i.toByte()))
                cipher.iv.copyInto(ivs, destinationOffset = i * IV_BYTES)
                out.write(cipher.doFinal(plaintext, i * CHUNK_PLAINTEXT, chunkLen))
            }
            val ivBlob = ByteArray(1 + n * IV_BYTES)
            ivBlob[0] = n.toByte()
            ivs.copyInto(ivBlob, destinationOffset = 1)
            Sealer.Sealed(ivBlob, out.toByteArray())
        }
    }

    override fun open(profile: KeyProfile, aad: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray {
        // A missing key means every entry under it is unrecoverable (e.g. the
        // keystore was cleared). Never create a key on the read path.
        val key = key(profile, create = false)
            ?: throw Contract.Violation(Contract.ERR_KEY_INVALIDATED, "protecting key no longer exists")
        return mapErrors {
            val n = iv.firstOrNull()?.toInt()?.and(0xFF) ?: 0
            if (n < 1 || iv.size != 1 + n * IV_BYTES) {
                throw Contract.Violation(Contract.ERR_CORRUPT, "Malformed sealed IV blob")
            }
            val out = java.io.ByteArrayOutputStream()
            var offset = 0
            for (i in 0 until n) {
                val chunkCipherLen = if (i + 1 < n) CHUNK_PLAINTEXT + GCM_TAG_BYTES else ciphertext.size - offset
                if (chunkCipherLen <= GCM_TAG_BYTES || offset > ciphertext.size) {
                    throw Contract.Violation(Contract.ERR_CORRUPT, "Recorded length inconsistency")
                }
                val cipher = Cipher.getInstance(TRANSFORMATION)
                val ivBytes = iv.copyOfRange(1 + i * IV_BYTES, 1 + (i + 1) * IV_BYTES)
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, ivBytes))
                cipher.updateAAD(aad)
                cipher.updateAAD(byteArrayOf(i.toByte()))
                out.write(cipher.doFinal(ciphertext, offset, chunkCipherLen))
                offset += chunkCipherLen
            }
            out.toByteArray()
        }
    }

    private fun key(profile: KeyProfile, create: Boolean): SecretKey? {
        val alias = alias(profile)
        synchronized(this) {
            val existing = try {
                keyStore.getKey(alias, null) as? SecretKey
            } catch (e: Exception) {
                throw Contract.Violation(Contract.ERR_STORAGE, "cannot load protecting key")
            }
            if (existing != null || !create) return existing
            return generate(profile, alias)
        }
    }

    private fun generate(profile: KeyProfile, alias: String): SecretKey {
        try {
            val spec = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
            if (profile == KeyProfile.UNLOCKED_DEVICE) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    throw Contract.Violation(Contract.ERR_UNSUPPORTED_OPTION, "requires API 28")
                }
                spec.setUnlockedDeviceRequired(true)
            }
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            generator.init(spec.build())
            return generator.generateKey()
        } catch (e: Contract.Violation) {
            throw e
        } catch (e: Exception) {
            throw Contract.Violation(Contract.ERR_UNAVAILABLE, "cannot create protecting key")
        }
    }

    private inline fun <T> mapErrors(block: () -> T): T = try {
        block()
    } catch (e: KeyPermanentlyInvalidatedException) {
        throw Contract.Violation(Contract.ERR_KEY_INVALIDATED, "protecting key was invalidated")
    } catch (e: UserNotAuthenticatedException) {
        // setUnlockedDeviceRequired keys are unusable while the device is locked.
        throw Contract.Violation(Contract.ERR_LOCKED, "device is locked")
    } catch (e: AEADBadTagException) {
        throw Contract.Violation(Contract.ERR_CORRUPT, "stored entry failed authentication")
    } catch (e: Contract.Violation) {
        throw e
    } catch (e: Exception) {
        // Message intentionally generic: no exception text, no stack trace.
        throw Contract.Violation(Contract.ERR_STORAGE, "keystore operation failed (${e.javaClass.simpleName})")
    }

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_TAG_BITS = 128
        private const val GCM_TAG_BYTES = 16
        private const val IV_BYTES = 12
        // AndroidKeyStore AES-GCM on API ≤28 fails tag verification for
        // payloads over ~64–256 KiB. Chunking keeps each AEAD call small and
        // deterministic; many single-chunk records (existing PQNA files)
        // still decrypt identically.
        internal const val CHUNK_PLAINTEXT = 48 * 1024
        internal fun chunksFor(length: Int): Int =
            if (length <= 0) 1 else (length + CHUNK_PLAINTEXT - 1) / CHUNK_PLAINTEXT

        private const val ALIAS_PREFIX = "com.yardenah.pqkeystore.v1."

        fun alias(profile: KeyProfile) = when (profile) {
            KeyProfile.DEFAULT -> "${ALIAS_PREFIX}default"
            KeyProfile.UNLOCKED_DEVICE -> "${ALIAS_PREFIX}unlocked"
        }
    }
}
