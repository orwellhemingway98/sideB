import AppKit

protocol HapticPerforming {
    func perform(_ kind: HapticKind)
}

/// Trackpad taps while scrubbing: a light tick, a firmer bump on chapters.
final class Haptics: HapticPerforming {
    private let performer: NSHapticFeedbackPerformer

    init(performer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer) {
        self.performer = performer
    }

    func perform(_ kind: HapticKind) {
        switch kind {
        case .tick: performer.perform(.generic, performanceTime: .now)
        case .chapter: performer.perform(.levelChange, performanceTime: .now)
        }
    }
}
