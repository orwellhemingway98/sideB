import AppKit
import Combine
import SwiftUI

/// Where the list window goes: below the panel when it fits, else beside it (left, then right), top-aligned.
enum ListPlacement {
    static let gap: CGFloat = 12
    static let width: CGFloat = 272
    static let maxHeight: CGFloat = 360

    /// Decided for the tallest list (`maxHeight`), so a list that grows as it loads doesn't jump from
    /// below the panel to beside it.
    static func frame(panel: NSRect, height: CGFloat, visible: NSRect) -> NSRect {
        let h = min(height, maxHeight)
        if panel.minY - gap - maxHeight >= visible.minY {
            return NSRect(x: panel.minX, y: panel.minY - gap - h, width: width, height: h)
        }
        let left = panel.minX - gap - width
        if left >= visible.minX { return NSRect(x: left, y: panel.maxY - h, width: width, height: h) }
        return NSRect(x: panel.maxX + gap, y: panel.maxY - h, width: width, height: h)
    }

    static let oneLineRow: CGFloat = 30
    /// An episode: its title, with the date and length underneath.
    static let twoLineRow: CGFloat = 44

    /// Rows plus the title bar, capped.
    static func height(rows: Int, rowHeight: CGFloat = oneLineRow) -> CGFloat {
        guard rows < 1_000 else { return maxHeight }
        return min(maxHeight, 56 + CGFloat(max(rows, 1)) * rowHeight + 12)
    }
}

/// Which clicks close the dial panel: those in another Spindle window, but not in the panel, its menu bar
/// item or the panel's own child windows (the list).
enum PanelClickPolicy {
    static func closesPanel(clickWindow: NSWindow?, panel: NSWindow, anchor: NSWindow?, children: [NSWindow]) -> Bool {
        guard let clickWindow else { return false }
        if clickWindow === panel || clickWindow === anchor { return false }
        return !children.contains { $0 === clickWindow }
    }
}

/// Whether the droplet has spread into the window.
@MainActor
final class DropletState: ObservableObject {
    @Published var open = false
}

/// The list window under the dial panel. It opens as a glass drop that falls from the panel and spreads into
/// the window, and closes the same way in reverse.
@MainActor
final class ListWindowController {
    static let spring = Animation.spring(response: 0.6, dampingFraction: 0.78)
    private static let closeDelay: TimeInterval = 0.4

    private let window: NSPanel
    private let hosting: NSHostingView<ListDropletView>
    private let model: ListModel
    private let nowPlaying: NowPlaying
    private let state = DropletState()
    private weak var parent: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    private var lastIdentity: String?
    private var placedBelow = true

    init(model: ListModel, nowPlaying: NowPlaying) {
        self.model = model
        self.nowPlaying = nowPlaying
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: ListPlacement.width, height: ListPlacement.maxHeight),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        hosting = NSHostingView(rootView: ListDropletView(state: state, model: model, nowPlaying: nowPlaying))
        hosting.sizingOptions = []
        // A hosting view that is the window's content view resizes the window to follow animated content,
        // which the droplet's spring turned into a layout loop that crashed. Inside a plain view it can't.
        let container = NSView(frame: window.contentLayoutRect)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container

        // Close when what the list is about changes (a new show, album or playlist); follow songs within it.
        model.$content.sink { [weak self] content in
            DispatchQueue.main.async { self?.contentChanged(content) }
        }.store(in: &cancellables)
        // Keep the list current while it is open, but only when what it shows has changed (not on every
        // position tick); NowPlaying changes often, so wait for a quiet moment first.
        nowPlaying.objectWillChange
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.isShown, self.model.needsReload else { return }
                Task { await self.model.reload() }
            }.store(in: &cancellables)
        // Signing in or out of Spotify changes what a Spotify song's list shows (the song's details or its
        // album), which isn't the author moving on: adopt the new list rather than closing.
        model.spotify?.$isSignedIn.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isShown else { return }
                self.lastIdentity = nil
                Task { await self.model.reload(force: true); self.place() }
            }
        }.store(in: &cancellables)
        model.$tab.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: DialPanelController.didClose)
            .sink { [weak self] _ in self?.close(animated: false) }
            .store(in: &cancellables)
    }

    var isShown: Bool { window.isVisible && state.open }
    var frame: NSRect { window.frame }

    func toggle(below parent: NSWindow) {
        if isShown { close(animated: true) } else { show(below: parent) }
    }

    func show(below parent: NSWindow) {
        self.parent = parent
        lastIdentity = nil
        window.level = parent.level
        window.collectionBehavior = parent.collectionBehavior
        Task {
            await model.reload(force: true)
            place()
        }
        place()
        parent.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        state.open = false
        DispatchQueue.main.async {
            withAnimation(Self.spring) { self.state.open = true }
        }
    }

    func close(animated: Bool) {
        guard animated else {
            finishClosing()
            return
        }
        withAnimation(Self.spring) { state.open = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeDelay) { [weak self] in
            guard let self, !self.state.open else { return }
            self.finishClosing()
        }
    }

    /// Escape: closes the list if it is open, and says so (so the panel stays).
    func handleEscape() -> Bool {
        guard isShown else { return false }
        close(animated: true)
        return true
    }

    private func finishClosing() {
        state.open = false
        parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    private func contentChanged(_ content: ListContent) {
        guard window.isVisible, state.open else { return }
        if case .nothing = content {
            close(animated: true)
            return
        }
        switch ListCloseRule.decide(last: lastIdentity, identity: content.identity, isLoading: content.isLoading) {
        case .close:
            close(animated: true)
        case .keep(let identity):
            lastIdentity = identity
            place()
        }
    }

    /// Sizes the window for its rows and puts it below (or beside) the panel. Below the panel, the window also
    /// covers the gap, so the drop can be seen leaving the panel.
    private func place() {
        guard let parent else { return }
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let rowHeight = isEpisodeList ? ListPlacement.twoLineRow : ListPlacement.oneLineRow
        var frame = ListPlacement.frame(panel: parent.frame, height: ListPlacement.height(rows: rowCount, rowHeight: rowHeight),
                                        visible: visible)
        placedBelow = frame.maxY <= parent.frame.minY
        if placedBelow { frame.size.height += ListPlacement.gap }
        window.setFrame(frame, display: true)
        hosting.rootView =
            ListDropletView(state: state, model: model, nowPlaying: nowPlaying, topInset: placedBelow ? ListPlacement.gap : 0)
    }

    private var isEpisodeList: Bool {
        if case .podcast = model.content { return model.tab == .episodes }
        return false
    }

    private var rowCount: Int {
        switch model.content {
        case .podcast(let episodes, _, let chapters, _, _):
            if model.tab == .episodes { return episodes.count }
            return chapters.isEmpty ? .max : chapters.count   // no chapters: the description, given the full height
        case .music(let context, _):
            return context.tracks.count + (context.totalCount > context.tracks.count ? 1 : 0)
                + (nowPlaying.music?.source == .spotify ? 1 : 0)   // Sign out of Spotify
        case .spotify: return 7
        case .musicLoading: return .max     // size for the tallest list while it loads
        case .musicMessage: return 2
        case .nothing: return 1
        }
    }
}

// MARK: - The droplet

struct ListDropletView: View {
    @ObservedObject var state: DropletState
    @ObservedObject var model: ListModel
    let nowPlaying: NowPlaying
    var topInset: CGFloat = ListPlacement.gap
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            ZStack(alignment: .top) {
                if state.open {
                    ListBody(model: model, nowPlaying: nowPlaying)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .glassEffectID("list", in: glass)
                } else {
                    // The drop, about to fall from the panel's bottom edge.
                    Color.clear
                        .frame(width: 34, height: 34)
                        .glassEffect(.regular, in: Circle())
                        .glassEffectID("list", in: glass)
                        .offset(y: -26)
                }
            }
            .padding(.top, topInset)
        }
    }
}

private struct ListBody: View {
    @ObservedObject var model: ListModel
    let nowPlaying: NowPlaying

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.content {
            case .podcast(let episodes, let current, let chapters, let currentChapter, let description):
                Picker("", selection: $model.tab) {
                    Text("Episodes").tag(PodcastTab.episodes)
                    Text(ListContent.secondTabTitle(hasChapters: !chapters.isEmpty)).tag(PodcastTab.chapters)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.tab == .episodes {
                    rows(episodes, id: \.persistentModelID, currentID: current.persistentModelID) { episode in
                        episodeRow(episode, current: episode === current) { nowPlaying.play(episode) }
                    }
                } else if chapters.isEmpty {
                    ScrollView { Text(description).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }
                        .scrollEdgeEffectStyle(.soft, for: .all)
                } else {
                    rows(chapters, id: \.start, currentID: currentChapter?.start) { chapter in
                        row(title: chapter.title, detail: TimeFormat.clock(chapter.start),
                            current: chapter == currentChapter) { nowPlaying.jump(to: chapter.start) }
                    }
                }
            case .music(let context, let currentTrackID):
                title("\(context.title) \u{00B7} \(context.totalCount) song\(context.totalCount == 1 ? "" : "s")")
                rows(context.tracks, id: \.id, currentID: currentTrackID,
                     footer: context.totalCount > context.tracks.count
                        ? "and \(context.totalCount - context.tracks.count) more" : nil) { song in
                    row(title: song.title, detail: TimeFormat.clock(song.duration),
                        number: context.kind == .album ? song.number : nil,
                        current: song.id == currentTrackID) {
                        nowPlaying.music?.play(contextTrack: song, in: context)
                    }
                }
                if nowPlaying.music?.source == .spotify, let account = model.spotify {
                    Button("Sign out of Spotify") { account.signOut() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            case .musicLoading:
                note(nowPlaying.music?.source == .spotify ? "Reading Spotify\u{2026}" : "Reading Music\u{2026}")
            case .musicMessage(_, let text):
                note(text)
            case .spotify(let track):
                title(track.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.artist)
                    Text(track.album)
                    if track.duration > 0 { Text(TimeFormat.clock(track.duration)) }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                if let account = model.spotify {
                    SpotifySignInButton(account: account)
                } else {
                    note("Sign in to Spotify to see the album and playlist.")
                }
            case .nothing:
                EmptyView()
            }
        }
        .padding(14)
    }

    private func title(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A scrolling list that opens on the current item and fades at its edges rather than cutting rows.
    private func rows<Item, ID: Hashable, Row: View>(_ items: [Item], id: KeyPath<Item, ID>, currentID: ID?,
                                                    footer: String? = nil,
                                                    @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: id) { item in row(item) }
                    if let footer {
                        Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 6)
                    }
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onAppear { if let currentID { proxy.scrollTo(currentID, anchor: .center) } }
            .onChange(of: currentID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private func row(title: String, detail: String, number: Int? = nil, current: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let number { Text("\(number)").foregroundStyle(.secondary).frame(width: 18, alignment: .trailing) }
                Text(title).lineLimit(1).fontWeight(current ? .semibold : .regular)
                Spacer(minLength: 6)
                Text(detail).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(current ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func episodeRow(_ episode: Episode, current: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title).font(.system(size: 12)).fontWeight(current ? .semibold : .regular).lineLimit(1)
                Text(Self.episodeDetail(episode)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: ListPlacement.twoLineRow, alignment: .leading)
            .background(current ? Color.white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func episodeDetail(_ episode: Episode) -> String {
        var parts: [String] = []
        if let published = episode.published { parts.append(ListContent.episodeDate(published)) }
        if let duration = episode.duration {
            parts.append(!episode.played && episode.position > 0
                         ? "\(TimeFormat.clock(max(0, duration - episode.position))) left" : TimeFormat.clock(duration))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// Signs in to Spotify, asking for the Client ID of the author's Spotify app the first time.
private struct SpotifySignInButton: View {
    @ObservedObject var account: SpotifyAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = account.notice {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button {
                guard let id = account.clientID ?? SpotifyClientIDPrompt.ask(current: nil) else { return }
                Task { await account.signIn(clientID: id) }
            } label: {
                Text(account.isSigningIn ? "Signing in\u{2026}" : "Sign in to Spotify")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.glass)
            .disabled(account.isSigningIn)
            .contextMenu {
                Button("Change Client ID\u{2026}") {
                    guard let id = SpotifyClientIDPrompt.ask(current: account.clientID) else { return }
                    Task { await account.signIn(clientID: id) }
                }
            }
        }
        .padding(.top, 4)
    }
}
