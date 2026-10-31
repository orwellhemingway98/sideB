import Foundation

@MainActor
protocol AudioEngine: AnyObject {
    func load(_ url: URL, at time: TimeInterval)
    func play()
    func pause()
    func seek(to time: TimeInterval)
    var rate: Float { get set }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval? { get }
    /// About every 0.5 s while playing.
    var onTime: ((TimeInterval) -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }
}
