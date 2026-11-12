import CafeineCore
import Foundation
import ServiceManagement

/// Relie les réglages, l'alimentation et le contrôle de la veille.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var status: Status = .inactive

    @Published var acOnly: Bool {
        didSet {
            preferences.acOnly = acOnly
            evaluate()
        }
    }

    @Published var batteryThreshold: Int {
        didSet {
            preferences.batteryThreshold = batteryThreshold
            evaluate()
        }
    }

    @Published var duration: AwakeDuration {
        didSet {
            preferences.duration = duration
            // Changer la durée pendant que Caféine est active relance le minuteur.
            if enabled {
                endDate = duration.endDate(from: Date())
            }
            evaluate()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !revertingLaunchAtLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    var isEnabled: Bool { enabled }

    private let preferences: Preferences
    private let controller: SleepController
    private var monitor: PowerMonitor?
    private var timer: Timer?

    /// L'utilisateur a activé Caféine (elle peut néanmoins être en pause).
    @Published private var enabled = false
    private var endDate: Date?
    /// Dernier état `disablesleep` appliqué avec succès.
    private var sleepDisabled = false
    /// Une demande d'autorisation est en cours.
    private var authorizing = false
    private var revertingLaunchAtLogin = false

    private init() {
        let preferences = Preferences(defaults: .standard)
        self.preferences = preferences
        self.controller = SleepController(runner: ProcessCommandRunner(), userName: NSUserName())
        self.acOnly = preferences.acOnly
        self.batteryThreshold = preferences.batteryThreshold
        self.duration = preferences.duration
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Cycle de vie

    func start() {
        // Un plantage ou une extinction brutale a pu laisser la veille désactivée.
        if (try? controller.isSleepDisabled()) == true {
            try? controller.setSleepDisabled(false)
        }

        let monitor = PowerMonitor { [weak self] in
            Task { @MainActor in self?.evaluate() }
        }
        monitor.start()
        self.monitor = monitor

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Rétablit la veille normale avant de quitter. Les erreurs sont ignorées :
    /// il n'y a plus d'interface pour les afficher.
    func shutdown() {
        timer?.invalidate()
        enabled = false
        if sleepDisabled {
            try? controller.setSleepDisabled(false)
            sleepDisabled = false
        }
    }

    // MARK: Actions

    func toggle() {
        if enabled {
            if deactivate() {
                status = .inactive
            }
            return
        }
        guard !authorizing else { return }
        authorizing = true

        // La boîte de dialogue d'authentification est bloquante : elle
        // s'exécute hors de la file principale.
        let controller = self.controller
        Task {
            let failure: Error? = await Task.detached { () -> Error? in
                if controller.isAuthorized() { return nil }
                do {
                    try controller.installAuthorization()
                    return nil
                } catch {
                    return error
                }
            }.value

            authorizing = false
            if let failure {
                status = Self.status(forAuthorizationFailure: failure)
                return
            }
            enabled = true
            endDate = duration.endDate(from: Date())
            evaluate()
        }
    }

    func evaluate() {
        guard let monitor else { return }
        let decision = Policy.decide(
            enabled: enabled,
            acOnly: acOnly,
            batteryThreshold: batteryThreshold,
            power: monitor.currentPower(),
            thermal: monitor.currentThermal(),
            endDate: endDate,
            now: Date())

        switch decision {
        case .inactive:
            // Le statut garde la raison du dernier arrêt ou la dernière erreur.
            break
        case .stayAwake:
            if apply(sleepDisabled: true) {
                status = .active(until: endDate)
            }
        case .pause(let reason):
            if apply(sleepDisabled: false) {
                status = .paused(reason)
            }
        case .stop(let reason):
            if deactivate() {
                status = .stopped(reason)
            }
        }
    }

    // MARK: Interne

    /// Renvoie `false` si la veille normale n'a pas pu être rétablie ;
    /// le statut porte alors l'erreur.
    private func deactivate() -> Bool {
        enabled = false
        endDate = nil
        return apply(sleepDisabled: false)
    }

    /// Applique l'état voulu s'il diffère du dernier état appliqué.
    /// En cas d'échec, désactive Caféine, affiche l'erreur et renvoie `false`.
    private func apply(sleepDisabled wanted: Bool) -> Bool {
        guard wanted != sleepDisabled else { return true }
        do {
            try controller.setSleepDisabled(wanted)
            sleepDisabled = wanted
            return true
        } catch {
            enabled = false
            endDate = nil
            if wanted {
                // Par prudence, tente de revenir à la veille normale.
                try? controller.setSleepDisabled(false)
            }
            sleepDisabled = false
            if let error = error as? SleepError, error == .unauthorized {
                status = .error("Autorisation manquante")
            } else {
                status = .error("Erreur : impossible de modifier la veille")
            }
            return false
        }
    }

    private static func status(forAuthorizationFailure error: Error) -> Status {
        switch error as? SleepError {
        case .authorizationCancelled:
            return .inactive
        case .invalidUserName:
            return .error("Erreur : nom d'utilisateur non pris en charge")
        default:
            return .error("Erreur : installation de l'autorisation impossible")
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            revertingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            revertingLaunchAtLogin = false
            status = .error("Lancement au démarrage indisponible")
        }
    }
}
