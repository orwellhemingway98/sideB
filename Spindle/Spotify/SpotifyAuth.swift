import CryptoKit
import Foundation

/// A Spotify login: the short-lived access token and the refresh token that renews it.
struct SpotifyTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// Spotify's Authorization Code flow with PKCE, for an app that can't keep a secret. Pure: it builds requests
/// and reads replies; `SpotifyClient` sends them.
enum SpotifyAuth {
    static let redirectURI = "spindle://callback"
    static let callbackScheme = "spindle"
    static let scopes = "user-read-currently-playing user-read-playback-state playlist-read-private playlist-read-collaborative"
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    enum CallbackError: Error, Equatable {
        case denied, stateMismatch, missingCode
    }

    private static let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// A random 64-character code verifier (RFC 7636 allows 43–128).
    static func makeVerifier() -> String {
        String((0..<64).map { _ in unreserved.randomElement()! })
    }

    static func makeState() -> String {
        String((0..<24).map { _ in unreserved.randomElement()! })
    }

    /// base64url(SHA-256(verifier)), without padding.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func authorizeURL(clientID: String, challenge: String, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes),
        ]
        return components.url!
    }

    /// The authorization code from Spotify's redirect back to Spindle.
    static func code(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw CallbackError.stateMismatch }
        if value("error") != nil { throw CallbackError.denied }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        return code
    }

    static func tokenRequest(code: String, verifier: String, clientID: String) -> URLRequest {
        form([("grant_type", "authorization_code"), ("code", code), ("redirect_uri", redirectURI),
              ("client_id", clientID), ("code_verifier", verifier)])
    }

    static func refreshRequest(refreshToken: String, clientID: String) -> URLRequest {
        form([("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", clientID)])
    }

    /// Reads a token reply. A refresh reply may leave out the refresh token, which then stays the same.
    static func tokens(from data: Data, previous: SpotifyTokens?, now: Date) throws -> SpotifyTokens {
        struct Reply: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let refresh = reply.refresh_token ?? previous?.refreshToken else { throw CallbackError.missingCode }
        return SpotifyTokens(accessToken: reply.access_token, refreshToken: refresh,
                             expiresAt: now.addingTimeInterval(reply.expires_in))
    }

    private static func form(_ fields: [(String, String)]) -> URLRequest {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $1)" }
            .joined(separator: "&")
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)
        return request
    }
}
