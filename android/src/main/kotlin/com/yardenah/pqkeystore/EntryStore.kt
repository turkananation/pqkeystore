// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// File-per-entry store for Android. Pure JVM (no Android APIs) so it is
// unit-testable; the AndroidKeyStore cipher is injected as a [Sealer].
//
// Location : <noBackupFilesDir>/pqkeystore/v1/
// File name: lowercase hex SHA-256 of the UTF-8 ID + ".pqke". IDs are never
//            interpreted as paths and case variants never collide.
// File body: header || iv || ciphertext+tag
//            header = "PQKE" | u8 version(1) | u8 profile | u16be idLen | id
//                     | u8 ivLen
//            The full header is the AES-GCM AAD, binding ciphertext to the
//            ID and key profile.
// Writes   : temp file in the same directory, fsync, rename(2) over the old
//            file, fsync directory. The previous entry survives any failure
//            before the rename.
//
// An entry exists iff its file is present and its header names the requested
// ID. A file whose payload fails authentication is reported as CORRUPT.

package com.yardenah.pqkeystore

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets
import java.nio.file.StandardOpenOption
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicLong

/** Key profiles; persisted in each entry header. */
internal enum class KeyProfile(val wire: Int) {
    DEFAULT(0),
    UNLOCKED_DEVICE(1);

    companion object {
        fun fromWire(value: Int): KeyProfile? = entries.firstOrNull { it.wire == value }
    }
}

/** Authenticated encryption under a non-exportable OS key. */
internal interface Sealer {
    class Sealed(val iv: ByteArray, val ciphertext: ByteArray)

    /** Throws [Contract.Violation] with a contract error code on failure. */
    fun seal(profile: KeyProfile, aad: ByteArray, plaintext: ByteArray): Sealed

    /** Throws [Contract.Violation] with a contract error code on failure. */
    fun open(profile: KeyProfile, aad: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray
}

internal class EntryStore(private val dir: File, private val sealer: Sealer) {
    private val tempCounter = AtomicLong()

    internal class Entry(val id: String, val profile: KeyProfile, val header: ByteArray, val iv: ByteArray, val ciphertext: ByteArray)

    fun put(id: String, data: ByteArray, profile: KeyProfile) {
        ensureDir()
        val idBytes = id.toByteArray(StandardCharsets.UTF_8)
        val ivLength = 12
        val header = header(profile, idBytes, ivLength)
        val sealed = sealer.seal(profile, header, data)
        if (sealed.iv.size != ivLength) {
            throw Contract.Violation(Contract.ERR_STORAGE, "unexpected IV length")
        }
        val target = fileFor(id)
        val temp = File(dir, "${target.name}$TEMP_MARKER${tempCounter.incrementAndGet()}")
        try {
            FileOutputStream(temp).use { out ->
                out.write(header)
                out.write(sealed.iv)
                out.write(sealed.ciphertext)
                out.flush()
                out.fd.sync()
            }
            if (!temp.renameTo(target)) {
                throw IOException("rename failed")
            }
            syncDir()
        } catch (e: IOException) {
            temp.delete()
            throw Contract.Violation(Contract.ERR_STORAGE, "cannot write entry")
        }
    }

    fun get(id: String): ByteArray? {
        val entry = read(id) ?: return null
        val plain = sealer.open(entry.profile, entry.header, entry.iv, entry.ciphertext)
        if (plain.isEmpty() || plain.size > Contract.MAX_RECORD_BYTES) {
            plain.fill(0)
            throw Contract.Violation(Contract.ERR_CORRUPT, "stored entry has an invalid size")
        }
        return plain
    }

    fun delete(id: String): Boolean {
        val file = fileFor(id)
        if (!file.exists()) return false
        val valid = read(id) != null
        if (!file.delete() && file.exists()) {
            throw Contract.Violation(Contract.ERR_STORAGE, "cannot delete entry")
        }
        syncDir()
        return valid
    }

    fun contains(id: String): Boolean = read(id) != null

    fun listIds(): List<String> {
        val files = dir.listFiles() ?: return emptyList()
        val ids = LinkedHashSet<String>()
        for (file in files) {
            val name = file.name
            if (!file.isFile || name.length != 64 + EXTENSION.length || !name.endsWith(EXTENSION)) continue
            val entry = parse(readBounded(file) ?: continue) ?: continue
            if (name == hashName(entry.id)) ids.add(entry.id)
        }
        return ids.toList()
    }

    /** Removes temp files left by a crash. Only call when no write is in flight. */
    fun removeStaleTempFiles(olderThanMillis: Long, now: Long = System.currentTimeMillis()) {
        dir.listFiles()?.forEach { file ->
            if (file.isFile && file.name.contains(TEMP_MARKER) && now - file.lastModified() > olderThanMillis) {
                file.delete()
            }
        }
    }

    fun fileFor(id: String): File = File(dir, hashName(id))

    private fun read(id: String): Entry? {
        val bytes = readBounded(fileFor(id)) ?: return null
        val entry = parse(bytes) ?: return null
        return if (entry.id == id) entry else null
    }

    private fun readBounded(file: File): ByteArray? {
        if (!file.isFile) return null
        val length = file.length()
        if (length <= 0 || length > MAX_FILE_BYTES) return null
        return try {
            file.readBytes()
        } catch (e: IOException) {
            if (!file.exists()) return null
            throw Contract.Violation(Contract.ERR_STORAGE, "cannot read entry")
        }
    }

    private fun ensureDir() {
        if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) {
            throw Contract.Violation(Contract.ERR_STORAGE, "cannot create storage directory")
        }
    }

    private fun syncDir() {
        // Best effort: persist the rename/unlink itself.
        try {
            FileChannel.open(dir.toPath(), StandardOpenOption.READ).use { it.force(true) }
        } catch (_: Exception) {
        }
    }

    companion object {
        const val EXTENSION = ".pqke"
        const val TEMP_MARKER = ".tmp-"
        private val MAGIC = byteArrayOf('P'.code.toByte(), 'Q'.code.toByte(), 'K'.code.toByte(), 'E'.code.toByte())
        private const val FORMAT_VERSION = 1
        private const val GCM_TAG_BYTES = 16
        private const val MAX_FILE_BYTES = Contract.MAX_RECORD_BYTES + 64 * 1024L

        fun hashName(id: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(id.toByteArray(StandardCharsets.UTF_8))
            return digest.joinToString("") { "%02x".format(it) } + EXTENSION
        }

        fun header(profile: KeyProfile, idBytes: ByteArray, ivLength: Int): ByteArray =
            ByteBuffer.allocate(4 + 1 + 1 + 2 + idBytes.size + 1).apply {
                put(MAGIC)
                put(FORMAT_VERSION.toByte())
                put(profile.wire.toByte())
                putShort(idBytes.size.toShort())
                put(idBytes)
                put(ivLength.toByte())
            }.array()

        /** Strict parse; returns null for anything that is not a v1 entry. */
        fun parse(bytes: ByteArray): Entry? {
            val buf = ByteBuffer.wrap(bytes)
            if (buf.remaining() < 4 + 1 + 1 + 2) return null
            val magic = ByteArray(4).also { buf.get(it) }
            if (!magic.contentEquals(MAGIC) || buf.get().toInt() != FORMAT_VERSION) return null
            val profile = KeyProfile.fromWire(buf.get().toInt()) ?: return null
            val idLength = buf.short.toInt() and 0xffff
            if (idLength == 0 || idLength > Contract.MAX_ID_UTF8_BYTES || buf.remaining() < idLength + 1) return null
            val idBytes = ByteArray(idLength).also { buf.get(it) }
            val ivLength = buf.get().toInt() and 0xff
            if (ivLength != 12 || buf.remaining() < ivLength + GCM_TAG_BYTES + 1) return null
            val headerLength = buf.position()
            val iv = ByteArray(ivLength).also { buf.get(it) }
            val ciphertext = ByteArray(buf.remaining()).also { buf.get(it) }
            val decoder = StandardCharsets.UTF_8.newDecoder()
            val id = try {
                decoder.decode(ByteBuffer.wrap(idBytes)).toString()
            } catch (_: Exception) {
                return null
            }
            if (!Contract.isValidId(id)) return null
            return Entry(id, profile, bytes.copyOfRange(0, headerLength), iv, ciphertext)
        }
    }
}
