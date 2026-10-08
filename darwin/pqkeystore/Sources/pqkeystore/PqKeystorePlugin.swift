// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// iOS + macOS implementation of platform channel contract v1
// (doc/PLATFORM_CONTRACT.md). Shared source (`sharedDarwinSource: true`).
//
// Storage: one generic-password item per record in the data protection
// keychain (kSecUseDataProtectionKeychain on macOS too — the legacy file
// keychain is never used).
//   service = "com.yardenah.pqkeystore.v1", account = base64url(<storage ID>)
//
// Replacement is crash-safe: the new item is first added under a "pending"
// service, then the old item is deleted and the pending item is renamed.
// Leftover pending items are reconciled at startup (see recoverPending()).
//
// Threading: all keychain calls run on one serial queue (FIFO, never on the
// main thread, where an authentication prompt would deadlock); results are
// delivered on the main thread.

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
  import Cocoa
#endif
import LocalAuthentication
import Security

public class PqKeystorePlugin: NSObject, FlutterPlugin {
  static let channelName = "com.yardenah.pqkeystore/store"
  static let contractVersion = 1
  static let maxIdUtf8Bytes = 256
  static let maxRecordBytes = 1024 * 1024

  static let service = "com.yardenah.pqkeystore.v1"
  static let pendingService = "com.yardenah.pqkeystore.v1.pending"

  private let queue = DispatchQueue(label: "com.yardenah.pqkeystore", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let instance = PqKeystorePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.queue.async { instance.recoverPending() }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let known = ["platformInfo", "put", "get", "delete", "contains", "listIds"]
    guard known.contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    queue.async {
      let outcome: Any?
      do {
        outcome = try self.dispatch(call)
      } catch let violation as Violation {
        outcome = FlutterError(code: violation.code, message: violation.message, details: nil)
      } catch {
        outcome = FlutterError(code: "STORAGE_ERROR", message: "unexpected failure", details: nil)
      }
      DispatchQueue.main.async { result(outcome) }
    }
  }

  // MARK: - Dispatch

  private func dispatch(_ call: FlutterMethodCall) throws -> Any? {
    switch call.method {
    case "platformInfo":
      #if os(iOS)
        let os = "ios"
      #else
        let os = "macos"
      #endif
      return [
        "contractVersion": PqKeystorePlugin.contractVersion,
        "os": os,
        "backend": "keychain-data-protection",
        "supportedOptions": supportedOptions().sorted(),
      ] as [String: Any]
    case "listIds":
      if call.arguments != nil && !(call.arguments is NSNull) {
        throw Violation.invalid("listIds takes no arguments")
      }
      return try listIds(service: PqKeystorePlugin.service)
    case "put":
      let args = try Contract.args(call.arguments, allowed: ["id", "data", "options"])
      let id = try Contract.id(args)
      let data = try Contract.data(args)
      let options = try Contract.options(args["options"], supported: supportedOptions())
      try put(id: id, data: data, options: options)
      return nil
    case "get":
      return try get(id: Contract.id(Contract.args(call.arguments, allowed: ["id"])))
        .map { FlutterStandardTypedData(bytes: $0) }
    case "delete":
      return try delete(id: Contract.id(Contract.args(call.arguments, allowed: ["id"])))
    case "contains":
      return try contains(id: Contract.id(Contract.args(call.arguments, allowed: ["id"])))
    default:
      throw Violation.invalid("unknown method")
    }
  }

  /// Capabilities enforceable on this device right now.
  private func supportedOptions() -> Set<String> {
    var supported: Set<String> = [
      Contract.capWhenUnlocked, Contract.capAfterFirstUnlock, Contract.capSynchronizable,
    ]
    var error: NSError?
    if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
      supported.insert(Contract.capUserPresence)
    }
    if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
      supported.insert(Contract.capBiometric)
    }
    return supported
  }

  // MARK: - Keychain

  private func baseQuery(service: String, account: String? = nil) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      // Match synchronizable and local items alike.
      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
      kSecUseDataProtectionKeychain as String: true,
    ]
    if let account = account {
      // The keychain may treat distinct raw UTF-8 accounts with equivalent
      // canonical forms as one entry. An ASCII-safe, injective, reversible
      // encoding (base64url of the UTF-8 ID bytes) keeps distinct IDs apart.
      query[kSecAttrAccount as String] = Self.encodeAccount(account)
    }
    return query
  }

  /// Maps an arbitrary storage ID to an ASCII-safe keychain account value.
  static func encodeAccount(_ id: String) -> String {
    Data(id.utf8).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Inverse of [encodeAccount]; returns nil for malformed input.
  static func decodeAccount(_ encoded: String) -> String? {
    var s = encoded
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    s += String(repeating: "=", count: (4 - s.count % 4) % 4)
    guard let data = Data(base64Encoded: s) else { return nil }
    return String(bytes: data, encoding: .utf8)
  }

  /// A context that fails instead of prompting (for metadata-only queries).
  private func silentContext() -> LAContext {
    let context = LAContext()
    context.interactionNotAllowed = true
    return context
  }

  private func put(id: String, data: Data, options: Contract.Options) throws {
    var item = baseQuery(service: PqKeystorePlugin.pendingService, account: id)
    item.removeValue(forKey: kSecAttrSynchronizable as String)
    item[kSecValueData as String] = data
    item[kSecAttrSynchronizable as String] = options.synchronizable

    let accessible: CFString
    switch (options.synchronizable, options.accessibility) {
    case (true, .afterFirstUnlock): accessible = kSecAttrAccessibleAfterFirstUnlock
    case (true, _): accessible = kSecAttrAccessibleWhenUnlocked
    case (false, .afterFirstUnlock): accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    case (false, _): accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }
    if options.userPresence || options.biometric {
      let flags: SecAccessControlCreateFlags =
        options.biometric ? .biometryCurrentSet : .userPresence
      var error: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(nil, accessible, flags, &error)
      else {
        throw Violation(code: "UNSUPPORTED_OPTION", message: "access control unavailable")
      }
      item[kSecAttrAccessControl as String] = access
    } else {
      item[kSecAttrAccessible as String] = accessible
    }

    // 1. Clear any stale pending item, 2. stage the new value.
    _ = SecItemDelete(baseQuery(service: PqKeystorePlugin.pendingService, account: id) as CFDictionary)
    try check(SecItemAdd(item as CFDictionary, nil), "add")
    // 3. Remove the old value, 4. promote the staged value. A crash between
    // 3 and 4 is repaired by recoverPending() on next launch.
    let deleted = SecItemDelete(baseQuery(service: PqKeystorePlugin.service, account: id) as CFDictionary)
    if deleted != errSecSuccess && deleted != errSecItemNotFound {
      _ = SecItemDelete(baseQuery(service: PqKeystorePlugin.pendingService, account: id) as CFDictionary)
      try check(deleted, "replace")
    }
    try check(
      SecItemUpdate(
        baseQuery(service: PqKeystorePlugin.pendingService, account: id) as CFDictionary,
        [kSecAttrService as String: PqKeystorePlugin.service] as CFDictionary),
      "commit")
  }

  private func get(id: String) throws -> Data? {
    var query = baseQuery(service: PqKeystorePlugin.service, account: id)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    if status == errSecItemNotFound { return nil }
    try check(status, "read")
    guard let data = out as? Data, !data.isEmpty, data.count <= PqKeystorePlugin.maxRecordBytes
    else {
      throw Violation(code: "CORRUPT", message: "stored item has an invalid size")
    }
    return data
  }

  private func delete(id: String) throws -> Bool {
    _ = SecItemDelete(baseQuery(service: PqKeystorePlugin.pendingService, account: id) as CFDictionary)
    let status = SecItemDelete(baseQuery(service: PqKeystorePlugin.service, account: id) as CFDictionary)
    if status == errSecItemNotFound { return false }
    try check(status, "delete")
    return true
  }

  private func contains(id: String) throws -> Bool {
    var query = baseQuery(service: PqKeystorePlugin.service, account: id)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = silentContext()
    var out: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    switch status {
    case errSecSuccess, errSecInteractionNotAllowed: return true
    case errSecItemNotFound: return false
    default:
      try check(status, "query")
      return false
    }
  }

  private func listIds(service: String) throws -> [String] {
    var query = baseQuery(service: service)
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    query[kSecUseAuthenticationContext as String] = silentContext()
    var out: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    if status == errSecItemNotFound { return [] }
    try check(status, "list")
    var seen = Set<[UInt8]>()
    var ids: [String] = []
    for attributes in (out as? [[String: Any]]) ?? [] {
      if let raw = attributes[kSecAttrAccount as String] as? String,
        let id = Self.decodeAccount(raw),
        Contract.isValidId(id), seen.insert(Array(id.utf8)).inserted
      {
        ids.append(id)
      }
    }
    return ids
  }

  /// Reconciles items left in the pending service by an interrupted put.
  /// If the committed item exists, the put never returned success and the
  /// staged value is discarded; otherwise the staged value is the only copy
  /// and is promoted.
  private func recoverPending() {
    guard let pending = try? listIds(service: PqKeystorePlugin.pendingService) else { return }
    for id in pending {
      let pendingQuery = baseQuery(service: PqKeystorePlugin.pendingService, account: id)
      if (try? contains(id: id)) == true {
        _ = SecItemDelete(pendingQuery as CFDictionary)
      } else {
        _ = SecItemUpdate(
          pendingQuery as CFDictionary,
          [kSecAttrService as String: PqKeystorePlugin.service] as CFDictionary)
      }
    }
  }

  private func check(_ status: OSStatus, _ what: String) throws {
    if status == errSecSuccess { return }
    let message = "keychain \(what) failed (OSStatus \(status))"
    switch status {
    case errSecUserCanceled:
      throw Violation(code: "USER_CANCELLED", message: message)
    case errSecAuthFailed:
      throw Violation(code: "AUTH_FAILED", message: message)
    case errSecInteractionNotAllowed:
      throw Violation(code: "LOCKED", message: message)
    case errSecMissingEntitlement, errSecNotAvailable, errSecNoSuchKeychain:
      // -34018: the app lacks a keychain entitlement (unsigned/ad-hoc builds
      // on macOS). The legacy file keychain is deliberately not used instead.
      throw Violation(code: "UNAVAILABLE", message: message)
    case errSecDecode:
      throw Violation(code: "CORRUPT", message: message)
    default:
      throw Violation(code: "STORAGE_ERROR", message: message)
    }
  }
}

// MARK: - Contract validation

struct Violation: Error {
  let code: String
  let message: String

  static func invalid(_ message: String) -> Violation {
    Violation(code: "INVALID_ARGS", message: message)
  }
}

enum Contract {
  static let capUserPresence = "requireUserPresence"
  static let capBiometric = "requireBiometric"
  static let capWhenUnlocked = "accessibility.whenUnlocked"
  static let capAfterFirstUnlock = "accessibility.afterFirstUnlock"
  static let capSynchronizable = "synchronizable"

  enum Accessibility { case platformDefault, whenUnlocked, afterFirstUnlock }

  struct Options {
    let userPresence: Bool
    let biometric: Bool
    let accessibility: Accessibility
    let synchronizable: Bool
  }

  static func args(_ raw: Any?, allowed: Set<String>) throws -> [String: Any] {
    guard let map = raw as? [String: Any] else {
      throw Violation.invalid("arguments must be a map")
    }
    if !Set(map.keys).isSubset(of: allowed) {
      throw Violation.invalid("unexpected argument")
    }
    return map
  }

  static func isValidId(_ id: String) -> Bool {
    return !id.isEmpty && !id.unicodeScalars.contains("\u{0}")
      && id.utf8.count <= PqKeystorePlugin.maxIdUtf8Bytes
  }

  static func id(_ args: [String: Any]) throws -> String {
    guard let id = args["id"] as? String, isValidId(id) else {
      throw Violation.invalid("invalid id")
    }
    return id
  }

  static func data(_ args: [String: Any]) throws -> Data {
    guard let typed = args["data"] as? FlutterStandardTypedData, typed.type == .uInt8,
      !typed.data.isEmpty, typed.data.count <= PqKeystorePlugin.maxRecordBytes
    else {
      throw Violation.invalid("data must be 1..\(PqKeystorePlugin.maxRecordBytes) bytes")
    }
    return typed.data
  }

  /// Strict bool: NSNumber-backed integers must not pass as booleans.
  private static func bool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) == CFBooleanGetTypeID()
    else { return nil }
    return number.boolValue
  }

  /// Normative order: shape, unsupported capability, then combinations.
  static func options(_ raw: Any?, supported: Set<String>) throws -> Options {
    let keys: Set<String> = [
      "requireUserPresence", "requireBiometric", "accessibility", "synchronizable",
    ]
    guard let map = raw as? [String: Any], Set(map.keys) == keys else {
      throw Violation.invalid("options must contain exactly the v1 keys")
    }
    guard let presence = bool(map["requireUserPresence"]),
      let biometric = bool(map["requireBiometric"]),
      let sync = bool(map["synchronizable"])
    else {
      throw Violation.invalid("boolean option has wrong type")
    }
    let accessibility: Accessibility
    switch map["accessibility"] as? String {
    case "platformDefault": accessibility = .platformDefault
    case "whenUnlocked": accessibility = .whenUnlocked
    case "afterFirstUnlock": accessibility = .afterFirstUnlock
    default: throw Violation.invalid("unknown accessibility")
    }
    var requested = Set<String>()
    if presence { requested.insert(capUserPresence) }
    if biometric { requested.insert(capBiometric) }
    if sync { requested.insert(capSynchronizable) }
    if accessibility == .whenUnlocked { requested.insert(capWhenUnlocked) }
    if accessibility == .afterFirstUnlock { requested.insert(capAfterFirstUnlock) }
    if !requested.isSubset(of: supported) {
      throw Violation(code: "UNSUPPORTED_OPTION", message: "option not enforceable on this device")
    }
    if sync && (presence || biometric) {
      throw Violation(
        code: "UNSUPPORTED_OPTION", message: "synchronizable cannot be combined with access control")
    }
    return Options(
      userPresence: presence, biometric: biometric, accessibility: accessibility,
      synchronizable: sync)
  }
}
