import Foundation
import Security

/// Where the Spotify login is kept between launches.
protocol SpotifyTokenStore: AnyObject, Sendable {
    func load() -> SpotifyTokens?
    func save(_ tokens: SpotifyTokens)
    func clear()
}

/// The login as one generic password in the login Keychain. sideB is ad-hoc signed, so after a rebuild
/// macOS may ask once whether the new build may read it.
final class KeychainTokenStore: SpotifyTokenStore, @unchecked Sendable {
    private let service: String
    private let account = "tokens"

    init(service: String = "com.mfelouro.SideB.spotify") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> SpotifyTokens? {
        var match = query
        match[kSecReturnData as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(match as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
    }

    func save(_ tokens: SpotifyTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "sideB Spotify sign-in"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// For tests and previews.
final class MemoryTokenStore: SpotifyTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SpotifyTokens?

    func load() -> SpotifyTokens? { lock.withLock { tokens } }
    func save(_ tokens: SpotifyTokens) { lock.withLock { self.tokens = tokens } }
    func clear() { lock.withLock { tokens = nil } }
}
