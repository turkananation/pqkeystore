// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// JVM unit tests for Android contract validation. Run from example/android:
//   ./gradlew :pqkeystore:testDebugUnitTest

package com.yardenah.pqkeystore

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class ContractTest {
    private fun options(
        presence: Boolean = false,
        access: Any? = "platformDefault",
        sync: Boolean = false,
    ): Map<String, Any?> = mapOf(
        "requireUserPresence" to presence,
        "requireBiometric" to false,
        "accessibility" to access,
        "synchronizable" to sync,
    )

    private fun code(block: () -> Unit): String =
        assertFailsWith<Contract.Violation> { block() }.code

    @Test
    fun idRules() {
        assertTrue(Contract.isValidId("a"))
        assertTrue(Contract.isValidId("🔑"))
        assertTrue(Contract.isValidId("a".repeat(256)))
        assertFalse(Contract.isValidId(""))
        assertFalse(Contract.isValidId("a".repeat(257)))
        assertFalse(Contract.isValidId("é".repeat(129)))
        assertFalse(Contract.isValidId("a\u0000b"))
        assertFalse(Contract.isValidId("\uD800"))
        assertFalse(Contract.isValidId("x\uDC00"))
    }

    @Test
    fun argumentShape() {
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.args("x", setOf("id")) })
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.args(null, setOf("id")) })
        assertEquals(
            Contract.ERR_INVALID_ARGS,
            code { Contract.args(mapOf("id" to "a", "key" to "a"), setOf("id")) },
        )
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.id(mapOf("id" to 1)) })
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.requireNoArgs(mapOf<String, Any>()) })
    }

    @Test
    fun dataBounds() {
        assertEquals(1, Contract.data(mapOf("data" to ByteArray(1))).size)
        assertEquals(
            Contract.MAX_RECORD_BYTES,
            Contract.data(mapOf("data" to ByteArray(Contract.MAX_RECORD_BYTES))).size,
        )
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.data(mapOf("data" to ByteArray(0))) })
        assertEquals(
            Contract.ERR_INVALID_ARGS,
            code { Contract.data(mapOf("data" to ByteArray(Contract.MAX_RECORD_BYTES + 1))) },
        )
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.data(mapOf("data" to "s")) })
    }

    @Test
    fun optionShape() {
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.options(null, emptySet()) })
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.options(emptyMap<String, Any>(), emptySet()) })
        assertEquals(
            Contract.ERR_INVALID_ARGS,
            code { Contract.options(options() + ("unknown" to true), emptySet()) },
        )
        assertEquals(
            Contract.ERR_INVALID_ARGS,
            code { Contract.options(options() + ("requireBiometric" to "yes"), emptySet()) },
        )
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.options(options(access = "always"), emptySet()) })
        assertEquals(Contract.ERR_INVALID_ARGS, code { Contract.options(options(access = 1), emptySet()) })
    }

    @Test
    fun capabilitiesAreEnforcedOrRejected() {
        assertEquals(
            Contract.ERR_UNSUPPORTED_OPTION,
            code { Contract.options(options(access = "whenUnlocked"), emptySet()) },
        )
        assertEquals(
            Contract.Accessibility.WHEN_UNLOCKED,
            Contract.options(options(access = "whenUnlocked"), setOf(Contract.CAP_WHEN_UNLOCKED)).accessibility,
        )
        assertEquals(Contract.ERR_UNSUPPORTED_OPTION, code { Contract.options(options(presence = true), emptySet()) })
        val all = setOf(
            Contract.CAP_USER_PRESENCE, Contract.CAP_BIOMETRIC, Contract.CAP_SYNCHRONIZABLE,
            Contract.CAP_WHEN_UNLOCKED, Contract.CAP_AFTER_FIRST_UNLOCK,
        )
        assertEquals(
            Contract.ERR_UNSUPPORTED_OPTION,
            code { Contract.options(options(presence = true, sync = true), all) },
        )
    }
}
