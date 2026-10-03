package com.yardenah.pqkeystore

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class PqKeystorePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var sharedPrefs: SharedPreferences
    private lateinit var keyStore: KeyStore

    companion object {
        private const val PREFS_NAME = "pqkeystore_data"
        private const val KEY_ALIAS = "pqkeystore_master"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val GCM_IV_LENGTH = 12
        private const val GCM_TAG_LENGTH = 128
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.yardenah.pqkeystore/store")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
        sharedPrefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        
        try {
            keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
            keyStore.load(null)
            if (!keyStore.containsAlias(KEY_ALIAS)) {
                generateMasterKey()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun generateMasterKey() {
        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        val keyGenParameterSpec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()

        keyGenerator.init(keyGenParameterSpec)
        keyGenerator.generateKey()
    }

    private fun getSecretKey(): SecretKey {
        return keyStore.getKey(KEY_ALIAS, null) as SecretKey
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val key = call.argument<String>("key")

        try {
            when (call.method) {
                "put" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    val value = call.argument<ByteArray>("value")
                    if (value == null) {
                        result.error("INVALID_ARGS", "Value is required", null)
                        return
                    }
                    put(key, value)
                    result.success(null)
                }
                "get" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    val value = get(key)
                    if (value == null) {
                        result.error("NOT_FOUND", "Key not found", null)
                    } else {
                        result.success(value)
                    }
                }
                "delete" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    delete(key)
                    result.success(null)
                }
                "contains" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    result.success(contains(key))
                }
                "putJson" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    val value = call.argument<String>("value")
                    if (value == null) {
                        result.error("INVALID_ARGS", "Value is required", null)
                        return
                    }
                    put(key, value.toByteArray(StandardCharsets.UTF_8))
                    result.success(null)
                }
                "getJson" -> {
                    if (key == null) {
                        result.error("INVALID_ARGS", "Key is required", null)
                        return
                    }
                    val value = get(key)
                    if (value == null) {
                        result.error("NOT_FOUND", "Key not found", null)
                    } else {
                        result.success(String(value, StandardCharsets.UTF_8))
                    }
                }
                "platformInfo" -> {
                    result.success(mapOf("os" to "android", "backend" to "android-keystore"))
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            result.error("KEYSTORE_ERROR", e.message, e.stackTraceToString())
        }
    }

    private fun put(key: String, value: ByteArray) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getSecretKey())
        val encryptedData = cipher.doFinal(value)
        val iv = cipher.iv

        val combined = ByteArray(iv.size + encryptedData.size)
        System.arraycopy(iv, 0, combined, 0, iv.size)
        System.arraycopy(encryptedData, 0, combined, iv.size, encryptedData.size)

        val base64Str = Base64.encodeToString(combined, Base64.NO_WRAP)
        sharedPrefs.edit().putString(key, base64Str).apply()
    }

    private fun get(key: String): ByteArray? {
        val base64Str = sharedPrefs.getString(key, null) ?: return null
        val combined = Base64.decode(base64Str, Base64.NO_WRAP)

        if (combined.size < GCM_IV_LENGTH) return null

        val iv = ByteArray(GCM_IV_LENGTH)
        System.arraycopy(combined, 0, iv, 0, GCM_IV_LENGTH)
        val encryptedData = ByteArray(combined.size - GCM_IV_LENGTH)
        System.arraycopy(combined, GCM_IV_LENGTH, encryptedData, 0, encryptedData.size)

        val cipher = Cipher.getInstance(TRANSFORMATION)
        val spec = GCMParameterSpec(GCM_TAG_LENGTH, iv)
        cipher.init(Cipher.DECRYPT_MODE, getSecretKey(), spec)

        return cipher.doFinal(encryptedData)
    }

    private fun delete(key: String) {
        sharedPrefs.edit().remove(key).apply()
    }

    private fun contains(key: String): Boolean {
        return sharedPrefs.contains(key)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
