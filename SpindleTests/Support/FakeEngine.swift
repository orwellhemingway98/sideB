import Foundation
@testable import Spindle

@MainActor
final class FakeEngine: AudioEngine {
    private(set) var loads: [(url: URL, time: TimeInterval)] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var seeks: [TimeInterval] = []

    var rate: Float = 1
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
    func fireFailure(_ error: Error) { onFailure?(error) }
}
