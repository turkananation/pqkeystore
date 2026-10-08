package com.yardenah.pqkeystore

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OnDeviceRoundTripTest {
    @Test
    fun e2eManySizedRoundtrips() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = ctx.noBackupFilesDir!!.resolve("pqkeystore/ondevice/v1").apply { mkdirs() }
        val store = EntryStore(dir, AndroidKeystoreSealer())
        for (size in listOf(1024, AndroidKeystoreSealer.CHUNK_PLAINTEXT - 1, AndroidKeystoreSealer.CHUNK_PLAINTEXT, AndroidKeystoreSealer.CHUNK_PLAINTEXT + 5, Contract.MAX_RECORD_BYTES)) {
            val raw = ByteArray(size) { ((it * 17) % 251).toByte() }
            store.put("probe/$size", raw, KeyProfile.DEFAULT)
            val got = store.get("probe/$size")
            Assert.assertArrayEquals("size=$size", raw, got)
        }
    }
}
