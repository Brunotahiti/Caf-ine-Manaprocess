import Foundation

/// Alimentation du Mac à un instant donné.
public struct PowerState: Equatable {
    public var onAC: Bool
    /// `nil` : pas de batterie, ou lecture impossible.
    public var batteryPercent: Int?

    public init(onAC: Bool, batteryPercent: Int?) {
        self.onAC = onAC
        self.batteryPercent = batteryPercent
    }
}

public enum ThermalLevel: Equatable {
    case nominal, fair, serious, critical
}

/// Raison d'un arrêt : l'utilisateur doit réactiver Caféine lui-même.
public enum StopReason: Equatable {
    case thermal
    case timerElapsed
    case batteryLow(percent: Int)
}

/// Raison d'une pause : Caféine reprend seule quand la condition disparaît.
public enum PauseReason: Equatable {
    case onBattery
}

public enum Decision: Equatable {
    /// Caféine n'est pas activée.
    case inactive
    case stayAwake
    case pause(PauseReason)
    case stop(StopReason)
}

public enum Policy {
    /// Décide s'il faut garder le Mac éveillé. Les garde-fous sont évalués
    /// du plus grave au moins grave : surchauffe, minuteur, batterie faible,
    /// puis l'option « sur secteur uniquement ».
    public static func decide(
        enabled: Bool,
        acOnly: Bool,
        batteryThreshold: Int,
        power: PowerState,
        thermal: ThermalLevel,
        endDate: Date?,
        now: Date
    ) -> Decision {
        guard enabled else { return .inactive }

        if thermal == .serious || thermal == .critical {
            return .stop(.thermal)
        }
        if let endDate, now >= endDate {
            return .stop(.timerElapsed)
        }
        // Sans batterie lisible, les règles liées à la batterie ne s'appliquent pas.
        if !power.onAC, let percent = power.batteryPercent {
            if percent <= batteryThreshold {
                return .stop(.batteryLow(percent: percent))
            }
            if acOnly {
                return .pause(.onBattery)
            }
        }
        return .stayAwake
    }
}
