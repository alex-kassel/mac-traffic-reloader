import Foundation
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, MenuBarControllerDelegate, ReloaderEngineDelegate {
    private var menuBarController: MenuBarController!
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background menu bar accessory (no Dock, no Cmd+Tab)
        NSApp.setActivationPolicy(.accessory)

        // Prevent macOS from terminating background network app
        ProcessInfo.processInfo.disableAutomaticTermination("Traffic Reloader background scheduler")

        Logger.log("[AppDelegate] Starting Traffic Reloader...")

        menuBarController = MenuBarController()
        menuBarController.delegate = self

        ReloaderEngine.shared.delegate = self

        // Initial permissions request for notifications
        NotificationManager.shared.requestAuthorization()

        // Setup scheduler
        restartTimer()

        // Trigger initial check if credentials are configured
        let config = ConfigManager.shared.config
        if !config.username.isEmpty && !config.password.isEmpty && config.active {
            Logger.log("[AppDelegate] Triggering initial startup sync...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                ReloaderEngine.shared.triggerReload()
            }
        } else if config.username.isEmpty {
            Logger.log("[AppDelegate] First run detected: credentials not configured. Opening Settings...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                PreferencesWindowController.shared.showPreferences()
            }
        }

        Logger.log("[AppDelegate] Traffic Reloader initialized successfully.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Logger.log("[AppDelegate] Application terminating...")
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil

        let intervalMinutes = ConfigManager.shared.config.checkIntervalMinutes
        let intervalSeconds = TimeInterval(max(1, intervalMinutes) * 60)

        Logger.log("[AppDelegate] Scheduling recurring timer every %ld minutes (%.0f s)...", intervalMinutes, intervalSeconds)

        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.timerFired()
        }
    }

    private func timerFired() {
        let active = ConfigManager.shared.config.active
        guard active else {
            Logger.log("[AppDelegate] Timer fired, but app is DEACTIVATED. Skipping check.")
            return
        }

        Logger.log("[AppDelegate] Timer fired. Triggering automated traffic check...")
        ReloaderEngine.shared.triggerReload()
    }

    // MARK: - MenuBarControllerDelegate

    func menuBarDidChangeActive(_ active: Bool) {
        Logger.log("[AppDelegate] Active state toggled to: %@", active ? "ACTIVE" : "PAUSED")
        if active {
            // Trigger check immediately upon re-activating
            ReloaderEngine.shared.triggerReload()
            restartTimer()
        }
    }

    func menuBarDidRequestReload() {
        ReloaderEngine.shared.triggerReload(isManual: true)
    }

    func menuBarDidRequestQuit() {
        Logger.log("[AppDelegate] Quit requested via menu bar.")
        NSApp.terminate(nil)
    }

    // MARK: - ReloaderEngineDelegate

    func engineDidStartCycle() {
        menuBarController.updateStatusIcon(isReloading: true)
    }

    func engineDidFinishCycle(status: ServiceweltStatus) {
        menuBarController.refreshMenuStates()
    }
}
