import AppKit
import CafeineCore
import SwiftUI

@main
struct CafeineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.status.isAwake ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.shutdown()
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(StatusText.text(for: model.status))

        Divider()

        Button(model.isEnabled ? "Désactiver" : "Activer") {
            model.toggle()
        }

        Picker("Durée", selection: $model.duration) {
            ForEach(AwakeDuration.allCases, id: \.self) { duration in
                Text(duration.label).tag(duration)
            }
        }

        Toggle("Sur secteur uniquement", isOn: $model.acOnly)

        Picker("Seuil de batterie", selection: $model.batteryThreshold) {
            ForEach(Preferences.thresholds, id: \.self) { threshold in
                Text("\(threshold) %").tag(threshold)
            }
        }

        Divider()

        Toggle("Lancer au démarrage", isOn: $model.launchAtLogin)

        Button("Quitter") {
            NSApplication.shared.terminate(nil)
        }
    }
}
