import Foundation
import MediaPlayer

struct NowPlayingInfo: Equatable {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let duration: TimeInterval?
    let position: TimeInterval
    let rate: Float
    let isPlaying: Bool
}

enum MediaCommand: Equatable {
    case play, pause, toggle
    case skip(TimeInterval)
    case seek(to: TimeInterval)
    case rate(Float)
}

@MainActor
protocol MediaCenterPublishing: AnyObject {
    func publish(_ info: NowPlayingInfo?)
    var onCommand: ((MediaCommand) -> Void)? { get set }
}

/// Control Center, the media keys and the Now Playing widget. A thin adapter; artwork waits for a later stage.
@MainActor
final class MediaCenter: MediaCenterPublishing {
    var onCommand: ((MediaCommand) -> Void)?

    private let center = MPNowPlayingInfoCenter.default()

    init() {
        let commands = MPRemoteCommandCenter.shared()
        register(commands.playCommand) { _ in .play }
        register(commands.pauseCommand) { _ in .pause }
        register(commands.togglePlayPauseCommand) { _ in .toggle }

        commands.skipBackwardCommand.preferredIntervals = [15]
        register(commands.skipBackwardCommand) { _ in .skip(-15) }
        commands.skipForwardCommand.preferredIntervals = [30]
        register(commands.skipForwardCommand) { _ in .skip(30) }

        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.send(.seek(to: event.positionTime))
            return .success
        }

        commands.changePlaybackRateCommand.supportedPlaybackRates = ResumePolicy.rates.map { NSNumber(value: $0) }
        commands.changePlaybackRateCommand.isEnabled = true
        commands.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            self?.send(.rate(event.playbackRate))
            return .success
        }
    }

    private func register(_ command: MPRemoteCommand, _ make: @escaping (MPRemoteCommandEvent) -> MediaCommand) {
        command.isEnabled = true
        command.addTarget { [weak self] event in
            self?.send(make(event))
            return .success
        }
    }

    private nonisolated func send(_ command: MediaCommand) {
        Task { @MainActor [weak self] in self?.onCommand?(command) }
    }

    func publish(_ info: NowPlayingInfo?) {
        guard let info else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var dict: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.position,
            MPNowPlayingInfoPropertyPlaybackRate: info.isPlaying ? Double(info.rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if let duration = info.duration { dict[MPMediaItemPropertyPlaybackDuration] = duration }
        center.nowPlayingInfo = dict
        center.playbackState = info.isPlaying ? .playing : .paused
    }
}
