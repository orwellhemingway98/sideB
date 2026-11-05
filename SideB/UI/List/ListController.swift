import AppKit
import Combine
import SwiftUI

/// The list's size: as wide as the panel, as tall as its rows, capped.
enum ListPlacement {
    static let width: CGFloat = 272
    static let maxHeight: CGFloat = 360

    static let oneLineRow: CGFloat = 30
    /// An episode: its title, with the date and length underneath.
    static let twoLineRow: CGFloat = 44

    /// Rows plus the title bar, capped.
    static func height(rows: Int, rowHeight: CGFloat = oneLineRow) -> CGFloat {
        guard rows < 1_000 else { return maxHeight }
        return min(maxHeight, 56 + CGFloat(max(rows, 1)) * rowHeight + 12)
    }
}

/// Which clicks close the panel: those in another sideB window, but not in the panel, its menu bar
/// item or the panel's own child windows (the list).
enum PanelClickPolicy {
    static func closesPanel(clickWindow: NSWindow?, panel: NSWindow, anchor: NSWindow?, children: [NSWindow]) -> Bool {
        guard let clickWindow else { return false }
        if clickWindow === panel || clickWindow === anchor { return false }
        return !children.contains { $0 === clickWindow }
    }
}

/// The song or episode list on the back of the cover: clicking the cover turns it over. This keeps what the
/// back shows current, and turns the cover back when the music moves to another album or show.
@MainActor
final class ListController {
    private let model: ListModel
    private let nowPlaying: NowPlaying
    private var cancellables: Set<AnyCancellable> = []
    private var lastIdentity: String?

    /// `followsPanel`: the panel's cover turns back when the panel closes; the mini player's has its own life.
    init(model: ListModel, nowPlaying: NowPlaying, followsPanel: Bool = true) {
        self.model = model
        self.nowPlaying = nowPlaying

        // Turn back when what the list is about changes (a new show, album or playlist), so the new cover
        // shows; follow songs within it.
        model.$content.sink { [weak self] content in
            DispatchQueue.main.async { self?.contentChanged(content) }
        }.store(in: &cancellables)
        // Keep the list current while it shows, but only when what it shows has changed (not on every
        // position tick); NowPlaying changes often, so wait for a quiet moment first.
        nowPlaying.objectWillChange
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.isShown, self.model.needsReload else { return }
                Task { await self.model.reload() }
            }.store(in: &cancellables)
        // Signing in or out of Spotify changes what a Spotify song's list shows (the song's details or its
        // album), which isn't the author moving on: adopt the new list rather than turning back.
        model.spotify?.$isSignedIn.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isShown else { return }
                self.lastIdentity = nil
                Task { await self.model.reload(force: true) }
            }
        }.store(in: &cancellables)
        // The panel opens on the cover next time.
        if followsPanel {
            NotificationCenter.default.publisher(for: PanelController.didClose)
                .sink { [weak self] _ in self?.close(animated: false) }
                .store(in: &cancellables)
        }
    }

    var isShown: Bool { model.showsList }

    func toggle() {
        if isShown { close(animated: true) } else { show() }
    }

    func show() {
        lastIdentity = nil
        // Show what's already known (the cached album, the episodes) as the cover turns, then read the rest.
        model.showNow(force: true)
        model.showsList = true
        Task { await model.reload(force: true) }
    }

    func close(animated: Bool) {
        guard isShown else { return }
        if animated {
            model.showsList = false
        } else {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { model.showsList = false }
        }
    }

    /// Escape in the panel turns the cover back first.
    func handleEscape() -> Bool {
        guard isShown else { return false }
        close(animated: true)
        return true
    }

    private func contentChanged(_ content: ListContent) {
        guard isShown else { return }
        if case .nothing = content {
            close(animated: true)
            return
        }
        switch ListCloseRule.decide(last: lastIdentity, identity: content.identity, isLoading: content.isLoading) {
        case .close: close(animated: true)
        case .keep(let identity): lastIdentity = identity
        }
    }
}

/// What the back of the cover shows.
struct ListBody: View {
    @ObservedObject var model: ListModel
    let nowPlaying: NowPlaying
    /// Room round the list; the bottom keeps clear of the "Cover" pill.
    var insets = EdgeInsets(top: 10, leading: 6, bottom: 32, trailing: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch model.content {
            case .podcast(let episodes, let current, let chapters, let currentChapter, let description):
                TabSwitch(tab: $model.tab, second: ListContent.secondTabTitle(hasChapters: !chapters.isEmpty))
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
                title(context.title)
                rows(context.tracks, id: \.id, currentID: currentTrackID,
                     footer: ListContent.countLine(shown: context.tracks.count, total: context.totalCount)) { song in
                    row(title: song.title, detail: TimeFormat.clock(song.duration),
                        number: context.kind == .album ? song.number : nil,
                        current: song.id == currentTrackID) {
                        nowPlaying.music?.play(contextTrack: song, in: context)
                    }
                }
            case .musicLoading:
                note(nowPlaying.music?.source == .spotify ? "Reading Spotify\u{2026}" : "Reading Music\u{2026}")
            case .musicMessage(_, let text):
                note(text)
                if model.content.canTryAgain {
                    Button { Task { await model.tryAgain() } } label: {
                        Text("Try Again").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                    }
                    .buttonStyle(.glass)
                }
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
                    note("Spotify's album and playlist can't be listed here.")
                }
            case .nothing:
                EmptyView()
            }
        }
        .padding(insets)
    }

    private func title(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(text)     // a long name is cut short; the pointer reads it whole
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A scrolling list that opens on the current item and fades at its edges rather than cutting rows. The row
    /// the arrow keys have reached gets an outline, apart from the soft highlight on what's playing.
    private func rows<Item, ID: Hashable, Row: View>(_ items: [Item], id: KeyPath<Item, ID>, currentID: ID?,
                                                    footer: String? = nil,
                                                    @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        let keyID = model.keyRow.flatMap { $0 < items.count ? items[$0][keyPath: id] : nil }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items, id: id) { item in
                        row(item)
                            .overlay {
                                if item[keyPath: id] == keyID {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Color(nsColor: .labelColor).opacity(0.55), lineWidth: 1.5)
                                }
                            }
                    }
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
            .onChange(of: keyID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
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
        .accessibilityAddTraits(current ? .isSelected : [])
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
        .accessibilityAddTraits(current ? .isSelected : [])
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

/// The optional Spotify sign-in, asking for the Client ID of your own Spotify developer app the first time.
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
                Text(account.isSigningIn ? "Signing in\u{2026}"
                     : SpotifyClientIDPrompt.buttonTitle(hasClientID: account.clientID != nil))
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

/// Episodes | Notes, drawn in SwiftUI so it turns with the cover (a system segmented control wouldn't).
private struct TabSwitch: View {
    @Binding var tab: PodcastTab
    let second: String

    var body: some View {
        HStack(spacing: 2) {
            segment("Episodes", .episodes)
            segment(second, .chapters)
        }
        .padding(2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func segment(_ title: String, _ value: PodcastTab) -> some View {
        Button { tab = value } label: {
            Text(title)
                .font(.system(size: 11, weight: tab == value ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(tab == value ? Color.white.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}
