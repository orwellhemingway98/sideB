import AppKit
import ServiceManagement

/// The menu bar icon's right-click menu: Library, the floating dial, Launch at Login, signing out of Spotify
/// and Quit.
enum StatusMenu {
    enum Command: Equatable { case library, floatingDial, launchAtLogin, signOutOfSpotify, quit }

    struct Row: Equatable {
        let title: String
        let command: Command
        let isOn: Bool
    }

    /// The rows top to bottom; nil is a separator. `floatingDial` is whether it is out (nil: no floating dial).
    /// Signed in to Spotify, the menu offers to sign out (the list on the back of the cover has no account controls).
    static func rows(floatingDial: Bool?, launchAtLogin: Bool, spotifySignedIn: Bool = false) -> [Row?] {
        var rows: [Row?] = [Row(title: "Open Library\u{2026}", command: .library, isOn: false)]
        if let out = floatingDial {
            rows.append(Row(title: out ? "Put Dial Back" : "Show Floating Dial", command: .floatingDial, isOn: false))
        }
        rows += [nil, Row(title: "Launch at Login", command: .launchAtLogin, isOn: launchAtLogin), nil]
        if spotifySignedIn { rows += [Row(title: "Sign Out of Spotify", command: .signOutOfSpotify, isOn: false), nil] }
        rows.append(Row(title: "Quit Spindle", command: .quit, isOn: false))
        return rows
    }

    @MainActor
    static func toggle(_ item: LoginItem, onError: (Error) -> Void) {
        do { try item.setEnabled(!item.isEnabled) } catch { onError(error) }
    }

    @MainActor
    static func menu(floatingDial: Bool?, launchAtLogin: Bool, spotifySignedIn: Bool = false,
                     perform: @escaping (Command) -> Void) -> NSMenu {
        let menu = NSMenu()
        for row in rows(floatingDial: floatingDial, launchAtLogin: launchAtLogin, spotifySignedIn: spotifySignedIn) {
            guard let row else { menu.addItem(.separator()); continue }
            let item = CommandItem(title: row.title, keyEquivalent: row.command == .quit ? "q" : "") { perform(row.command) }
            item.state = row.isOn ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// A menu item that runs a closure.
    private final class CommandItem: NSMenuItem {
        private let run: () -> Void

        init(title: String, keyEquivalent: String, run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
            target = self
        }

        required init(coder: NSCoder) { fatalError("not used") }

        @objc private func fire() { run() }
    }
}

/// Starting Spindle when you log in.
protocol LoginItem: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// The app itself as a login item (System Settings › General › Login Items). Copied from ClickWheel.
final class MainAppLoginItem: LoginItem {
    /// Waiting for approval in System Settings counts as on, so choosing it again turns it off.
    var isEnabled: Bool { [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) }

    func setEnabled(_ on: Bool) throws {
        if on {
            try SMAppService.mainApp.register()
            // macOS may want the person to allow it in System Settings first.
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
