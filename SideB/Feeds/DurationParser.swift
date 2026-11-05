import Foundation

enum DurationParser {
    /// Reads "3120", "52:00", "1:04:00" or "00:00:05.500" as seconds; nil when it isn't a duration.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total: TimeInterval = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}
