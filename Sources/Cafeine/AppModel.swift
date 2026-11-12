import CafeineCore
import Combine
import Foundation
import ServiceManagement

/// Relie les réglages, l'alimentation et le contrôle de la veille.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var status: Status = .inactive
    /// Message sans rapport avec l'état de veille (lancement au démarrage).
    @Published private(set) var notice: String?

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
    @Published private var enabled = false {
        didSet { updateActivity() }
    }
    private var endDate: Date?
    /// Vrai tant que la veille du système est, ou pourrait être, désactivée.
    /// Ne repasse à faux qu'après un retour à la veille normale confirmé.
    private var sleepDisabled = false
    /// Une demande d'autorisation est en cours.
    private var authorizing = false
    private var revertingLaunchAtLogin = false
    /// Empêche macOS de ralentir le minuteur de réévaluation (App Nap).
    private var activity: NSObjectProtocol?

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
        // En cas de doute sur l'état réel, on tente aussi de la rétablir.
        if (try? controller.isSleepDisabled()) != false {
            sleepDisabled = true
            restoreNormalSleep()
            if sleepDisabled {
                status = .error("Erreur : impossible de rétablir la veille")
            }
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

    /// Rétablit la veille normale avant de quitter. L'état réel du système
    /// est relu : on ne se fie pas seulement à l'état mémorisé.
    func shutdown() {
        timer?.invalidate()
        enabled = false
        if sleepDisabled || (try? controller.isSleepDisabled()) != false {
            restoreNormalSleep()
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
        let wasAwake = sleepDisabled

        switch decision {
        case .inactive:
            // Le statut garde la raison du dernier arrêt ou la dernière erreur.
            // Si un retour à la veille normale a échoué, on réessaie ici.
            if sleepDisabled {
                restoreNormalSleep()
            }
        case .stayAwake:
            if apply(sleepDisabled: true) {
                status = .active(until: endDate)
            }
        case .pause(let reason):
            if apply(sleepDisabled: false) {
                status = .paused(reason)
                if wasAwake { sleepIfLidClosed() }
            }
        case .stop(let reason):
            if deactivate() {
                status = .stopped(reason)
                if wasAwake { sleepIfLidClosed() }
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

    /// Applique l'état voulu s'il diffère de l'état mémorisé.
    /// En cas d'échec, désactive Caféine, affiche l'erreur et renvoie `false`.
    private func apply(sleepDisabled wanted: Bool) -> Bool {
        guard wanted != sleepDisabled else { return true }
        if wanted {
            // Pessimiste : dès la tentative, la veille est peut-être désactivée.
            sleepDisabled = true
        }
        do {
            try controller.setSleepDisabled(wanted)
            sleepDisabled = wanted
            return true
        } catch {
            enabled = false
            endDate = nil
            if wanted {
                restoreNormalSleep()
            }
            // Si `sleepDisabled` reste vrai, `evaluate()` réessaiera.
            if let error = error as? SleepError, error == .unauthorized {
                status = .error("Autorisation manquante")
            } else {
                status = .error("Erreur : impossible de modifier la veille")
            }
            return false
        }
    }

    /// Tente de revenir à la veille normale ; `sleepDisabled` ne repasse à
    /// faux qu'en cas de succès confirmé.
    private func restoreNormalSleep() {
        do {
            try controller.setSleepDisabled(false)
            sleepDisabled = false
        } catch {
            sleepDisabled = true
        }
    }

    /// Après un arrêt ou une pause automatique capot fermé, macOS ne se
    /// rendort pas forcément de lui-même : on le lui demande.
    private func sleepIfLidClosed() {
        if controller.isLidClosed() {
            controller.sleepNow()
        }
    }

    private func updateActivity() {
        if enabled, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Surveillance de la batterie et du minuteur")
        } else if !enabled, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
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
            // L'état réel est relu ci-dessous.
        }
        let actual = SMAppService.mainApp.status == .enabled
        notice = actual == launchAtLogin ? nil : "Lancement au démarrage indisponible"
        if actual != launchAtLogin {
            revertingLaunchAtLogin = true
            launchAtLogin = actual
            revertingLaunchAtLogin = false
        }
    }
}
