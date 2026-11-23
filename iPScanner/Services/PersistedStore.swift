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

    static var defaults: UserDefaults = .standard

    /// Set when stored data could not be read in full. The unreadable value is copied
    /// to a backup key first, so the next save cannot silently destroy it.
    private(set) static var recoveryNotice: String?

    static func consumeRecoveryNotice() -> String? {
        defer { recoveryNotice = nil }
        return recoveryNotice
    }

    private static func backUp(_ value: Any, from key: String, reason: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let backupKey = "\(key).backup-\(stamp)"
        defaults.set(value, forKey: backupKey)
        recoveryNotice = "\(reason) A copy was kept in iPScanner's preferences (\(backupKey))."
    }

    static func loadLabels() -> [String: String] {
        guard let raw = defaults.object(forKey: labelsKey) else { return [:] }
        if let labels = raw as? [String: String] { return labels }
        guard let dict = raw as? [String: Any] else {
            backUp(raw, from: labelsKey, reason: "Saved labels could not be read.")
            return [:]
        }
        // Keep every readable label instead of discarding all of them for one bad value.
        let readable = dict.compactMapValues { $0 as? String }
        backUp(raw, from: labelsKey, reason: "\(dict.count - readable.count) saved label(s) could not be read.")
        return readable
    }

    static func saveLabels(_ labels: [String: String]) {
        if labels.isEmpty {
            defaults.removeObject(forKey: labelsKey)
        } else {
            defaults.set(labels, forKey: labelsKey)
        }
    }

    static func loadRanges() -> [SavedRange] {
        if let data = defaults.data(forKey: savedRangesKeyV2) {
            if let decoded = try? JSONDecoder().decode([SavedRange].self, from: data) { return decoded }
            backUp(data, from: savedRangesKeyV2, reason: "Saved networks could not be read.")
            return []
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
