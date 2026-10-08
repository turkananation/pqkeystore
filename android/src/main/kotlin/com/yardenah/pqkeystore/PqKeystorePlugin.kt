// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Android implementation of platform channel contract v1
// (doc/PLATFORM_CONTRACT.md).
//
// Threading: every call is validated and executed on one dedicated
// background thread (strict FIFO order, never blocks the UI thread); results
// are posted back to the main thread.

package com.yardenah.pqkeystore

import android.app.KeyguardManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PqKeystorePlugin : FlutterPlugin, MethodCallHandler {
    private var channel: MethodChannel? = null
    private var executor: ExecutorService? = null
    private lateinit var context: Context
    private lateinit var store: EntryStore
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        store = EntryStore(
            File(context.noBackupFilesDir, "pqkeystore${File.separator}v1"),
            AndroidKeystoreSealer(),
        )
        val worker = Executors.newSingleThreadExecutor { r -> Thread(r, "pqkeystore") }
        executor = worker
        // Crash leftovers only; any write in flight elsewhere is >10 min old.
        worker.execute { runCatching { store.removeStaleTempFiles(10 * 60 * 1000L) } }
        channel = MethodChannel(binding.binaryMessenger, Contract.CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val worker = executor
        if (worker == null) {
            result.error(Contract.ERR_UNAVAILABLE, "plugin detached", null)
            return
        }
        when (call.method) {
            "platformInfo", "put", "get", "delete", "contains", "listIds" -> Unit
            else -> {
                result.notImplemented()
                return
            }
        }
        worker.execute {
            val outcome: () -> Unit = try {
                val value = dispatch(call)
                ({ result.success(value) })
            } catch (e: Contract.Violation) {
                ({ result.error(e.code, e.message, null) })
            } catch (e: Exception) {
                // Never forward exception text or stack traces over the channel.
                ({ result.error(Contract.ERR_STORAGE, "unexpected failure (${e.javaClass.simpleName})", null) })
            }
            mainHandler.post(outcome)
        }
    }

    private fun dispatch(call: MethodCall): Any? {
        val raw = call.arguments
        return when (call.method) {
            "platformInfo" -> mapOf(
                "contractVersion" to Contract.VERSION,
                "os" to "android",
                "backend" to "androidkeystore-aes-gcm-file",
                "supportedOptions" to supportedOptions().sorted(),
            )
            "listIds" -> {
                Contract.requireNoArgs(raw)
                requireUnlockedStorage()
                store.listIds()
            }
            "put" -> {
                val args = Contract.args(raw, setOf("id", "data", "options"))
                val id = Contract.id(args)
                val data = Contract.data(args)
                val options = Contract.options(args["options"], supportedOptions())
                requireUnlockedStorage()
                val profile = if (options.accessibility == Contract.Accessibility.WHEN_UNLOCKED) {
                    KeyProfile.UNLOCKED_DEVICE
                } else {
                    // platformDefault and afterFirstUnlock: credential-encrypted
                    // storage already enforces after-first-unlock when supported.
                    KeyProfile.DEFAULT
                }
                store.put(id, data, profile)
                null
            }
            "get" -> {
                val id = Contract.id(Contract.args(raw, setOf("id")))
                requireUnlockedStorage()
                store.get(id)
            }
            "delete" -> {
                val id = Contract.id(Contract.args(raw, setOf("id")))
                requireUnlockedStorage()
                store.delete(id)
            }
            "contains" -> {
                val id = Contract.id(Contract.args(raw, setOf("id")))
                requireUnlockedStorage()
                store.contains(id)
            }
            else -> throw Contract.Violation(Contract.ERR_INVALID_ARGS, "unknown method")
        }
    }

    /**
     * Capabilities this device can enforce right now. Recomputed per call
     * because the lock screen can be added or removed at any time.
     *
     * requireUserPresence / requireBiometric need BiometricPrompt from a
     * FragmentActivity and are not offered in contract v1 on Android.
     * synchronizable has no Android equivalent.
     */
    private fun supportedOptions(): Set<String> {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val secure = keyguard?.isDeviceSecure == true
        val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as? DevicePolicyManager
        val fileBasedEncryption =
            dpm?.storageEncryptionStatus == DevicePolicyManager.ENCRYPTION_STATUS_ACTIVE_PER_USER
        return buildSet {
            if (secure && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) add(Contract.CAP_WHEN_UNLOCKED)
            if (secure && fileBasedEncryption) add(Contract.CAP_AFTER_FIRST_UNLOCK)
        }
    }

    /** Credential-encrypted storage is unreadable before the first unlock. */
    private fun requireUnlockedStorage() {
        val users = context.getSystemService(Context.USER_SERVICE) as? UserManager
        if (users != null && !users.isUserUnlocked) {
            throw Contract.Violation(Contract.ERR_LOCKED, "storage unavailable before first unlock")
        }
    }
}
