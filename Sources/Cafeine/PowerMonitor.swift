import CafeineCore
import Foundation
import IOKit.ps

/// Lit l'alimentation et l'état thermique, et signale leurs changements.
final class PowerMonitor {
    private let onChange: () -> Void
    private var runLoopSource: CFRunLoopSource?
    private var thermalObserver: NSObjectProtocol?

    /// `onChange` est appelé sur la file principale.
    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().onChange()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            // `commonModes` : la notification arrive aussi quand le menu est ouvert.
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }

        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange()
        }
    }

    func currentPower() -> PowerState {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            // Lecture impossible : traité comme un Mac sans batterie, sur secteur.
            return PowerState(onAC: true, batteryPercent: nil)
        }

        let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        let onAC = providing == nil || providing == kIOPSACPowerValue

        var percent: Int?
        let sources = (IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int,
                maximum > 0
            else { continue }
            percent = current * 100 / maximum
            break
        }

        return PowerState(onAC: onAC, batteryPercent: percent)
    }

    func currentThermal() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}
