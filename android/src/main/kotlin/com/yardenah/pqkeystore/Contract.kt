// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform channel contract v1 — argument validation for Android.
// Must match lib/src/backend/platform_contract.dart and
// test/contract/reference_native_store.dart exactly.
//
// Pure Kotlin (no Android APIs) so it is unit-testable on the JVM.

package com.yardenah.pqkeystore

import java.nio.charset.StandardCharsets

internal object Contract {
    const val CHANNEL = "com.yardenah.pqkeystore/store"
    const val VERSION = 1
    const val MAX_ID_UTF8_BYTES = 256
    const val MAX_RECORD_BYTES = 1024 * 1024

    const val ERR_INVALID_ARGS = "INVALID_ARGS"
    const val ERR_UNSUPPORTED_OPTION = "UNSUPPORTED_OPTION"
    const val ERR_UNAVAILABLE = "UNAVAILABLE"
    const val ERR_LOCKED = "LOCKED"
    const val ERR_KEY_INVALIDATED = "KEY_INVALIDATED"
    const val ERR_CORRUPT = "CORRUPT"
    const val ERR_STORAGE = "STORAGE_ERROR"

    const val CAP_USER_PRESENCE = "requireUserPresence"
    const val CAP_BIOMETRIC = "requireBiometric"
    const val CAP_WHEN_UNLOCKED = "accessibility.whenUnlocked"
    const val CAP_AFTER_FIRST_UNLOCK = "accessibility.afterFirstUnlock"
    const val CAP_SYNCHRONIZABLE = "synchronizable"

    private val OPTION_KEYS =
        setOf("requireUserPresence", "requireBiometric", "accessibility", "synchronizable")

    enum class Accessibility { PLATFORM_DEFAULT, WHEN_UNLOCKED, AFTER_FIRST_UNLOCK }

    data class Options(
        val userPresence: Boolean,
        val biometric: Boolean,
        val accessibility: Accessibility,
        val synchronizable: Boolean,
    )

    class Violation(val code: String, message: String) : Exception(message)

    private fun invalid(message: String) = Violation(ERR_INVALID_ARGS, message)

    /** Returns the arguments as a map whose keys are all in [allowed]. */
    fun args(raw: Any?, allowed: Set<String>): Map<*, *> {
        if (raw !is Map<*, *>) throw invalid("arguments must be a map")
        for (key in raw.keys) {
            if (key !is String || key !in allowed) throw invalid("unexpected argument")
        }
        return raw
    }

    fun requireNoArgs(raw: Any?) {
        if (raw != null) throw invalid("listIds takes no arguments")
    }

    fun id(args: Map<*, *>): String {
        val id = args["id"] as? String ?: throw invalid("invalid id")
        if (!isValidId(id)) throw invalid("invalid id")
        return id
    }

    fun isValidId(id: String): Boolean {
        if (id.isEmpty() || id.indexOf('\u0000') >= 0) return false
        var i = 0
        while (i < id.length) {
            val c = id[i]
            if (Character.isHighSurrogate(c)) {
                if (i + 1 >= id.length || !Character.isLowSurrogate(id[i + 1])) return false
                i++
            } else if (Character.isLowSurrogate(c)) {
                return false
            }
            i++
        }
        return id.toByteArray(StandardCharsets.UTF_8).size <= MAX_ID_UTF8_BYTES
    }

    fun data(args: Map<*, *>): ByteArray {
        val data = args["data"] as? ByteArray
        if (data == null || data.isEmpty() || data.size > MAX_RECORD_BYTES) {
            throw invalid("data must be 1..$MAX_RECORD_BYTES bytes")
        }
        return data
    }

    /**
     * Parses options and checks them against [supported] capabilities.
     * Normative order: shape, unsupported capability, then combinations.
     */
    fun options(raw: Any?, supported: Set<String>): Options {
        if (raw !is Map<*, *> || raw.size != OPTION_KEYS.size || !raw.keys.all { it in OPTION_KEYS }) {
            throw invalid("options must contain exactly the v1 keys")
        }
        val presence = raw["requireUserPresence"] as? Boolean
        val biometric = raw["requireBiometric"] as? Boolean
        val sync = raw["synchronizable"] as? Boolean
        if (presence == null || biometric == null || sync == null) {
            throw invalid("boolean option has wrong type")
        }
        val accessibility = when (raw["accessibility"]) {
            "platformDefault" -> Accessibility.PLATFORM_DEFAULT
            "whenUnlocked" -> Accessibility.WHEN_UNLOCKED
            "afterFirstUnlock" -> Accessibility.AFTER_FIRST_UNLOCK
            else -> throw invalid("unknown accessibility")
        }
        val requested = buildSet {
            if (presence) add(CAP_USER_PRESENCE)
            if (biometric) add(CAP_BIOMETRIC)
            if (sync) add(CAP_SYNCHRONIZABLE)
            if (accessibility == Accessibility.WHEN_UNLOCKED) add(CAP_WHEN_UNLOCKED)
            if (accessibility == Accessibility.AFTER_FIRST_UNLOCK) add(CAP_AFTER_FIRST_UNLOCK)
        }
        if (!supported.containsAll(requested)) {
            throw Violation(ERR_UNSUPPORTED_OPTION, "option not enforceable on this device")
        }
        if (sync && (presence || biometric)) {
            throw Violation(
                ERR_UNSUPPORTED_OPTION,
                "synchronizable cannot be combined with access control",
            )
        }
        return Options(presence, biometric, accessibility, sync)
    }
}
