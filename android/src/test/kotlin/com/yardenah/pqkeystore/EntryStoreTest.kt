// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// JVM unit tests for the Android entry store. A software AES-GCM sealer
// stands in for AndroidKeyStore; test data only.

package com.yardenah.pqkeystore

import java.io.File
import java.nio.file.Files
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private class SoftwareSealer : Sealer {
    private val key = SecretKeySpec(ByteArray(32) { it.toByte() }, "AES")

    override fun seal(profile: KeyProfile, aad: ByteArray, plaintext: ByteArray): Sealer.Sealed {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad)
        return Sealer.Sealed(cipher.iv, cipher.doFinal(plaintext))
    }

    override fun open(profile: KeyProfile, aad: ByteArray, iv: ByteArray, ciphertext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad)
        return try {
            cipher.doFinal(ciphertext)
        } catch (e: AEADBadTagException) {
            throw Contract.Violation(Contract.ERR_CORRUPT, "auth failed")
        }
    }
}

internal class EntryStoreTest {
    private lateinit var dir: File
    private lateinit var store: EntryStore

    @BeforeTest
    fun setUp() {
        dir = Files.createTempDirectory("pqks").toFile()
        store = EntryStore(File(dir, "v1"), SoftwareSealer())
    }

    @AfterTest
    fun tearDown() {
        dir.deleteRecursively()
    }

    @Test
    fun missingEntries() {
        assertNull(store.get("a"))
        assertFalse(store.contains("a"))
        assertFalse(store.delete("a"))
        assertEquals(emptyList(), store.listIds())
    }

    @Test
    fun roundTripReplaceDelete() {
        store.put("a", byteArrayOf(1, 2, 3), KeyProfile.DEFAULT)
        store.put("a", byteArrayOf(9), KeyProfile.UNLOCKED_DEVICE)
        assertContentEquals(byteArrayOf(9), store.get("a"))
        assertEquals(listOf("a"), store.listIds())
        assertTrue(store.delete("a"))
        assertNull(store.get("a"))
        assertFalse(store.delete("a"))
    }

    @Test
    fun idsAreOpaqueAndInjective() {
        val ids = listOf("Key", "key", "../x", "a/b", "caf\u00e9", "cafe\u0301", "🔑")
        ids.forEachIndexed { i, id -> store.put(id, byteArrayOf(i.toByte()), KeyProfile.DEFAULT) }
        ids.forEachIndexed { i, id -> assertContentEquals(byteArrayOf(i.toByte()), store.get(id)) }
        assertEquals(ids.toSet(), store.listIds().toSet())
        assertEquals(ids.size, File(dir, "v1").listFiles()!!.size)
    }

    @Test
    fun tamperedPayloadIsCorrupt() {
        store.put("a", byteArrayOf(1, 2, 3), KeyProfile.DEFAULT)
        val file = store.fileFor("a")
        val bytes = file.readBytes()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 1).toByte()
        file.writeBytes(bytes)
        assertTrue(store.contains("a"))
        assertEquals(Contract.ERR_CORRUPT, assertFailsWith<Contract.Violation> { store.get("a") }.code)
        assertTrue(store.delete("a"))
    }

    @Test
    fun entryMovedToAnotherIdIsNotVisible() {
        store.put("a", byteArrayOf(1), KeyProfile.DEFAULT)
        store.fileFor("a").copyTo(store.fileFor("b"))
        assertNull(store.get("b"))
        assertFalse(store.contains("b"))
        assertEquals(listOf("a"), store.listIds())
        // Removing the foreign file is not reported as deleting an entry.
        assertFalse(store.delete("b"))
        assertFalse(store.fileFor("b").exists())
    }

    @Test
    fun garbageAndTempFilesAreIgnored() {
        store.put("a", byteArrayOf(1), KeyProfile.DEFAULT)
        File(dir, "v1/${"0".repeat(64)}.pqna").writeBytes(byteArrayOf(1, 2, 3))
        val temp = File(dir, "v1/x.pqna.tmp-1").apply { writeBytes(byteArrayOf(1)) }
        assertEquals(listOf("a"), store.listIds())
        store.removeStaleTempFiles(olderThanMillis = 0, now = System.currentTimeMillis() + 1000)
        assertFalse(temp.exists())
        assertContentEquals(byteArrayOf(1), store.get("a"))
    }

    @Test
    fun headerIsStrict() {
        store.put("a", byteArrayOf(1), KeyProfile.DEFAULT)
        val bytes = store.fileFor("a").readBytes()
        assertTrue(EntryStore.parse(bytes) != null)
        assertNull(EntryStore.parse(bytes.copyOf(10)))
        val badVersion = bytes.copyOf().also { it[4] = 2 }
        assertNull(EntryStore.parse(badVersion))
        val badProfile = bytes.copyOf().also { it[5] = 9 }
        assertNull(EntryStore.parse(badProfile))
    }
}
