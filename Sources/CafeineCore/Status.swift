import Foundation

/// État affiché à l'utilisateur.
public enum Status: Equatable {
    case inactive
    case active(until: Date?)
    case paused(PauseReason)
    case stopped(StopReason)
    case error(String)

    /// Vrai seulement quand Caféine maintient effectivement le Mac éveillé.
    public var isAwake: Bool {
        if case .active = self { return true }
        return false
    }
}

public enum StatusText {
    /// Texte de la ligne d'état du menu.
    public static func text(for status: Status, timeZone: TimeZone = .current) -> String {
        switch status {
        case .inactive:
            return "Inactif"
        case .active(until: nil):
            return "Actif"
        case .active(until: let date?):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            return "Actif jusqu'à \(formatter.string(from: date))"
        case .paused(.onBattery):
            return "En pause : sur batterie"
        case .stopped(.batteryLow(let percent)):
            return "Arrêté : batterie à \(percent) %"
        case .stopped(.thermal):
            return "Arrêté : surchauffe"
        case .stopped(.timerElapsed):
            return "Arrêté : minuteur écoulé"
        case .error(let message):
            return message
        }
    }
}
