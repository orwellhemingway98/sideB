import Foundation
import SwiftData

@Model
final class UpNextEntry {
    var episode: Episode?
    var order: Int

    init(episode: Episode, order: Int) {
        self.episode = episode
        self.order = order
    }
}
