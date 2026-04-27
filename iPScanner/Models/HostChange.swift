import Foundation

enum HostChange: Equatable, Sendable {
    case new
    case modified(fields: [ChangedField])
    case missing(record: ScanSnapshot.HostRecord)

    enum ChangedField: String, Sendable, Equatable {
        case hostname
        case mac
        case vendor
        case openPorts
        case serviceTitle
    }

    var sfSymbol: String {
        switch self {
        case .new: "plus.circle.fill"
        case .modified: "circle.lefthalf.filled"
        case .missing: "minus.circle.fill"
        }
    }

    var tint: String {
        switch self {
        case .new: "green"
        case .modified: "yellow"
        case .missing: "red"
        }
    }

    var label: String {
        switch self {
        case .new: "New"
        case .modified(let fields): "Changed: " + fields.map(\.rawValue).joined(separator: ", ")
        case .missing: "Missing"
        }
    }
}
