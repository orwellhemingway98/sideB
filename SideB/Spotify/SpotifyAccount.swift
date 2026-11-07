import AppKit
import AuthenticationServices

/// The author's Spotify sign-in, for the UI: whether sideB is signed in, and signing in and out.
/// The Client ID of the author's own Spotify developer app is remembered in UserDefaults; the login itself
/// lives in the Keychain.
@MainActor
final class SpotifyAccount: ObservableObject {
    static let clientIDKey = "spotifyClientID"
    static let expiredNotice = "Spotify sign-in expired."
    static let failedNotice = "Couldn't sign in to Spotify."
    static let newSignInNote = "Sign in to Spotify again so its window stays where it is."

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var isSigningIn = false
    /// Shown above the Sign in button: why sideB is signed out, when it wasn't the author's choice.
    @Published private(set) var notice: String?
    /// Spotify refused a call because this sign-in predates a permission: signing in again grants it.
    @Published private(set) var needsNewSignIn = false

    let api: SpotifyWebAPI
    private let client: SpotifyClient
    private let defaults: UserDefaults
    private let authenticate: @MainActor (URL) async throws -> URL

    /// `authenticate` opens Spotify's sign-in page and returns the URL it redirects to.
    init(store: SpotifyTokenStore = KeychainTokenStore(), transport: HTTPTransport = URLSessionTransport(),
         defaults: UserDefaults = .standard,
         authenticate: @escaping @MainActor (URL) async throws -> URL = SpotifyWebSignIn.run) {
        self.defaults = defaults
        self.authenticate = authenticate
        nonisolated(unsafe) let settings = defaults
        let owner = WeakBox<SpotifyAccount>()
        client = SpotifyClient(clientID: { settings.string(forKey: SpotifyAccount.clientIDKey) }, store: store,
                               transport: transport,
                               onSignedOut: { expired in
                                   Task { @MainActor in owner.value?.signedOut(expired: expired) }
                               },
                               onMissingPermission: {
                                   Task { @MainActor in owner.value?.needsNewSignIn = true }
                               })
        api = SpotifyWebAPI(client: client)
        isSignedIn = client.isSignedIn
        owner.value = self
    }

    var clientID: String? { defaults.string(forKey: Self.clientIDKey) }

    func signIn(clientID: String) async {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !isSigningIn else { return }
        defaults.set(id, forKey: Self.clientIDKey)
        isSigningIn = true
        defer { isSigningIn = false }
        let verifier = SpotifyAuth.makeVerifier()
        let state = SpotifyAuth.makeState()
        let url = SpotifyAuth.authorizeURL(clientID: id, challenge: SpotifyAuth.challenge(for: verifier), state: state)
        let callback: URL
        do { callback = try await authenticate(url) }
        catch { return }  // Closed or cancelled: back to the button, nothing to say.
        do {
            let code = try SpotifyAuth.code(from: callback, state: state)
            let client = self.client
            try await Task.detached { try client.exchange(code: code, verifier: verifier) }.value
            notice = nil
            needsNewSignIn = false
            isSignedIn = true
        } catch SpotifyAuth.CallbackError.denied {
            return
        } catch {
            notice = Self.failedNotice
        }
    }

    func signOut() {
        client.signOut()
        signedOut(expired: false)
    }

    private func signedOut(expired: Bool) {
        if isSignedIn { isSignedIn = false }
        needsNewSignIn = false
        notice = expired ? Self.expiredNotice : nil
    }
}

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

/// Spotify's sign-in page in the system's web sheet, which catches the `sideb://callback` redirect itself.
enum SpotifyWebSignIn {
    @MainActor private static var session: ASWebAuthenticationSession?
    @MainActor private static let anchor = Anchor()

    @MainActor
    static func run(_ url: URL) async throws -> URL {
        NSApp.forceActivate()
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(SpotifyAuth.callbackScheme)) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? CancellationError()) }
                Task { @MainActor in SpotifyWebSignIn.session = nil }
            }
            session.presentationContextProvider = anchor
            // Reuse the browser's Spotify login, so a signed-in author just approves.
            session.prefersEphemeralWebBrowserSession = false
            Self.session = session
            if !session.start() {
                Self.session = nil
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    private final class Anchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            MainActor.assumeIsolated {
                NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey } ?? NSWindow()
            }
        }
    }
}

/// Spotify's play, pause and skip work without any of this. Listing its albums and playlists is the optional extra,
/// which needs your own Spotify developer app. This asks for its Client ID, until it gets one or is cancelled.
enum SpotifyClientIDPrompt {
    static let explanation = "Optional. Play, pause and skip already work; this also lists a song's album or playlist. "
        + "It needs Spotify Premium: create a free app at developer.spotify.com/dashboard with redirect URI "
        + "sideb://callback, then paste its Client ID."

    static func buttonTitle(hasClientID: Bool) -> String {
        hasClientID ? "Sign in to Spotify" : "Set Up Album Lists\u{2026}"
    }
    static let notAnID = "That isn't a Client ID. It's 32 letters and numbers at the top of your Spotify app's "
        + "Settings page (not the app name or the client secret)."

    /// A Client ID is 32 hexadecimal characters; anything else (a username, the app's name) is refused here
    /// rather than by Spotify's sign-in page.
    static func validated(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard id.count == 32, id.allSatisfy(\.isHexDigit) else { return nil }
        return id
    }

    @MainActor
    static func ask(current: String?) -> String? {
        var text = current ?? ""
        var message = explanation
        while true {
            let alert = NSAlert()
            alert.messageText = "List Spotify albums and playlists"
            alert.informativeText = message
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.placeholderString = "Client ID"
            field.stringValue = text
            alert.accessoryView = field
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            NSApp.forceActivate()
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            if let id = validated(field.stringValue) { return id }
            text = field.stringValue
            message = notAnID
        }
    }
}
