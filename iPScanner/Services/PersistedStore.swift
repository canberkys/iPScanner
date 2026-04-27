import Foundation

struct SavedRange: Codable, Hashable, Identifiable {
    var range: String
    var name: String?

    var id: String { range }

    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return range
    }
}

enum PersistedStore {
    private static let labelsKey = "iPScanner.labels"
    private static let savedRangesKeyV1 = "iPScanner.savedRanges"
    private static let savedRangesKeyV2 = "iPScanner.savedRangesV2"

    private static var defaults: UserDefaults { .standard }

    static func loadLabels() -> [String: String] {
        defaults.dictionary(forKey: labelsKey) as? [String: String] ?? [:]
    }

    static func saveLabels(_ labels: [String: String]) {
        if labels.isEmpty {
            defaults.removeObject(forKey: labelsKey)
        } else {
            defaults.set(labels, forKey: labelsKey)
        }
    }

    static func loadRanges() -> [SavedRange] {
        if let data = defaults.data(forKey: savedRangesKeyV2),
           let decoded = try? JSONDecoder().decode([SavedRange].self, from: data) {
            return decoded
        }
        // Migration from v1 (array of plain strings).
        if let strings = defaults.stringArray(forKey: savedRangesKeyV1) {
            return strings.map { SavedRange(range: $0, name: nil) }
        }
        return []
    }

    static func saveRanges(_ ranges: [SavedRange]) {
        if ranges.isEmpty {
            defaults.removeObject(forKey: savedRangesKeyV2)
            defaults.removeObject(forKey: savedRangesKeyV1)
            return
        }
        if let data = try? JSONEncoder().encode(ranges) {
            defaults.set(data, forKey: savedRangesKeyV2)
        }
        defaults.removeObject(forKey: savedRangesKeyV1)
    }
}
