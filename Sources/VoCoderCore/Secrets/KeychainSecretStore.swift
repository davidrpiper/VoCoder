// Secrets in the macOS Keychain (DESIGN §4.9, ADR 0009): generic passwords in the login keychain,
// service `dev.vocoder.<module>`, account = the secret's name. Values are never logged.
import Foundation
import Security

public struct KeychainSecretStore: SecretStore {
  /// `dev.vocoder`; tests use their own prefix.
  public let servicePrefix: String

  public init(servicePrefix: String = "dev.vocoder") { self.servicePrefix = servicePrefix }

  public func service(for key: SecretKey) -> String { "\(servicePrefix).\(key.module)" }

  private func query(_ key: SecretKey) -> [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service(for: key),
      kSecAttrAccount: key.name,
    ]
  }

  public func secret(for key: SecretKey) throws -> String? {
    var query = query(key)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError(operation: "read \(key)", status: status)
    }
    guard let value = String(data: data, encoding: .utf8) else {
      throw KeychainError(operation: "read \(key)", status: errSecDecode)
    }
    return value
  }

  public func hasSecret(for key: SecretKey) throws -> Bool {
    // Attributes only: reading them doesn't need the item's access-control approval.
    var query = query(key)
    query[kSecReturnAttributes] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess: return true
    case errSecItemNotFound: return false
    default: throw KeychainError(operation: "look up \(key)", status: status)
    }
  }

  public func setSecret(_ value: String, for key: SecretKey) throws {
    let data = Data(value.utf8)
    let update = SecItemUpdate(query(key) as CFDictionary, [kSecValueData: data] as CFDictionary)
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else {
      throw KeychainError(operation: "update \(key)", status: update)
    }
    var item = query(key)
    item[kSecValueData] = data
    item[kSecAttrLabel] = "VoCoder: \(key)"
    let add = SecItemAdd(item as CFDictionary, nil)
    guard add == errSecSuccess else { throw KeychainError(operation: "store \(key)", status: add) }
  }

  public func removeSecret(for key: SecretKey) throws {
    let status = SecItemDelete(query(key) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(operation: "remove \(key)", status: status)
    }
  }
}

/// A Keychain call that failed, with the system's explanation.
public struct KeychainError: Error, Sendable, Equatable, CustomStringConvertible {
  public let operation: String
  public let status: OSStatus

  public var description: String {
    let reason = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "unknown error"
    return "Keychain: couldn't \(operation): \(reason) (\(status))"
  }
}
