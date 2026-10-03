import Flutter
import UIKit
import Security

public class PqKeystorePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.yardenah.pqkeystore/store", binaryMessenger: registrar.messenger())
    let instance = PqKeystorePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let key = args?["key"] as? String

    switch call.method {
    case "put":
        guard let key = key, let value = (args?["value"] as? FlutterStandardTypedData)?.data else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key and value required", details: nil))
            return
        }
        do {
            try put(key: key, value: value)
            result(nil)
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "get":
        guard let key = key else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key is required", details: nil))
            return
        }
        do {
            if let value = try get(key: key) {
                result(value)
            } else {
                result(FlutterError(code: "NOT_FOUND", message: "Key not found", details: nil))
            }
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "delete":
        guard let key = key else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key is required", details: nil))
            return
        }
        do {
            try delete(key: key)
            result(nil)
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "contains":
        guard let key = key else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key is required", details: nil))
            return
        }
        do {
            let exists = try contains(key: key)
            result(exists)
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "putJson":
        guard let key = key, let value = args?["value"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key and value required", details: nil))
            return
        }
        do {
            try put(key: key, value: value.data(using: .utf8)!)
            result(nil)
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "getJson":
        guard let key = key else {
            result(FlutterError(code: "INVALID_ARGS", message: "Key is required", details: nil))
            return
        }
        do {
            if let value = try get(key: key), let stringValue = String(data: value, encoding: .utf8) {
                result(stringValue)
            } else {
                result(FlutterError(code: "NOT_FOUND", message: "Key not found", details: nil))
            }
        } catch let err as NSError {
            result(FlutterError(code: "KEYSTORE_ERROR", message: err.localizedDescription, details: nil))
        }
    case "platformInfo":
        result(["os": "ios", "backend": "keychain"])
    default:
        result(FlutterMethodNotImplemented)
    }
  }
  
  private func put(key: String, value: Data) throws {
      let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.yardenah.pqkeystore",
          kSecAttrAccount as String: key,
      ]
      
      let attributesToUpdate: [String: Any] = [
          kSecValueData as String: value,
          kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      ]
      
      let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
      if status == errSecItemNotFound {
          var newItem = query
          newItem[kSecValueData as String] = value
          newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
          let addStatus = SecItemAdd(newItem as CFDictionary, nil)
          if addStatus != errSecSuccess {
              throw NSError(domain: "com.yardenah.pqkeystore", code: Int(addStatus), userInfo: [NSLocalizedDescriptionKey: "Failed to add item to keychain."])
          }
      } else if status != errSecSuccess {
          throw NSError(domain: "com.yardenah.pqkeystore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to update item in keychain."])
      }
  }
  
  private func get(key: String) throws -> Data? {
      let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.yardenah.pqkeystore",
          kSecAttrAccount as String: key,
          kSecReturnData as String: kCFBooleanTrue!,
          kSecMatchLimit as String: kSecMatchLimitOne
      ]
      
      var dataTypeRef: AnyObject?
      let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
      
      if status == errSecSuccess {
          return dataTypeRef as? Data
      } else if status == errSecItemNotFound {
          return nil
      } else {
          throw NSError(domain: "com.yardenah.pqkeystore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to read item from keychain."])
      }
  }
  
  private func delete(key: String) throws {
      let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.yardenah.pqkeystore",
          kSecAttrAccount as String: key
      ]
      
      let status = SecItemDelete(query as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound {
          throw NSError(domain: "com.yardenah.pqkeystore", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Failed to delete item from keychain."])
      }
  }
  
  private func contains(key: String) throws -> Bool {
      return try get(key: key) != nil
  }
}
