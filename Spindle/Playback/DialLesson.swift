import Combine
import Foundation

/// The one-time caption under the disc that teaches the turn. It shows until the dial is first turned, and
/// that is remembered, so it never comes back. To see it again:
/// `defaults delete com.mfelouro.Spindle dialLessonLearned`.
@MainActor
final class DialLesson: ObservableObject {
    static let key = "dialLessonLearned"

    @Published private(set) var learned: Bool
    private var subscription: AnyCancellable?

    init(defaults: UserDefaults = .standard, turned: AnyPublisher<Void, Never>) {
        learned = defaults.bool(forKey: Self.key)
        guard !learned else { return }
        subscription = turned.first().sink { [weak self] in
            defaults.set(true, forKey: Self.key)
            self?.learned = true
        }
    }

    static func caption(for kind: NowPlayingDisplay.Kind) -> String {
        "Turn the dial to move through the \(kind == .music ? "song" : "episode") \u{00B7} \u{2325} + turn for volume"
    }
}
