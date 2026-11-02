import Foundation
@testable import Spindle

@MainActor
final class FakeEngine: AudioEngine {
    private(set) var loads: [(url: URL, time: TimeInterval)] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seeks: [TimeInterval] = []

    var rate: Float = 1
    var volume: Float = 1
    var currentTime: TimeInterval = 0
    var duration: TimeInterval?

    var onTime: ((TimeInterval) -> Void)?
    var onEnd: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    func load(_ url: URL, at time: TimeInterval) { loads.append((url, time)); currentTime = time }
    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func seek(to time: TimeInterval) { seeks.append(time); currentTime = time }

    func fireTime(_ time: TimeInterval) { currentTime = time; onTime?(time) }
    func fireEnd() { onEnd?() }
    /// Like the real engine, drops a callback from a load that has since been replaced.
    /// `ofLoad` is the index into `loads` the callback belongs to; nil means the latest.
    func fireFailure(_ error: Error, ofLoad index: Int? = nil) {
        guard index == nil || index == loads.count - 1 else { return }
        onFailure?(error)
    }
}
