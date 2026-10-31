import Foundation
@testable import Spindle

@MainActor
final class FakeMediaCenter: MediaCenterPublishing {
    private(set) var published: [NowPlayingInfo?] = []
    var onCommand: ((MediaCommand) -> Void)?

    func publish(_ info: NowPlayingInfo?) { published.append(info) }
}

final class FakeHaptics: HapticPerforming {
    private(set) var performed: [HapticKind] = []

    func perform(_ kind: HapticKind) { performed.append(kind) }
}
