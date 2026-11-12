import Foundation

/// Durée pendant laquelle Caféine reste active après son activation.
public enum AwakeDuration: Int, CaseIterable {
    case indefinite = 0
    case oneHour = 3600
    case twoHours = 7200
    case fourHours = 14400

    public var label: String {
        switch self {
        case .indefinite: return "Indéfiniment"
        case .oneHour: return "1 h"
        case .twoHours: return "2 h"
        case .fourHours: return "4 h"
        }
    }

    /// Date de fin pour une activation à `now`, ou `nil` sans limite de durée.
    public func endDate(from now: Date) -> Date? {
        self == .indefinite ? nil : now.addingTimeInterval(TimeInterval(rawValue))
    }
}

/// Réglages de l'utilisateur, conservés dans `UserDefaults`.
/// Une valeur stockée invalide est lue comme la valeur par défaut.
public struct Preferences {
    public static let thresholds = [10, 20, 30]
    static let defaultThreshold = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var acOnly: Bool {
        get { defaults.bool(forKey: "acOnly") }
        nonmutating set { defaults.set(newValue, forKey: "acOnly") }
    }

    public var batteryThreshold: Int {
        get {
            let stored = defaults.integer(forKey: "batteryThreshold")
            return Self.thresholds.contains(stored) ? stored : Self.defaultThreshold
        }
        nonmutating set { defaults.set(newValue, forKey: "batteryThreshold") }
    }

    public var duration: AwakeDuration {
        get { AwakeDuration(rawValue: defaults.integer(forKey: "duration")) ?? .indefinite }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "duration") }
    }
}
