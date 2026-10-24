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

        // Setup standard Edit menu so Cmd+C / Cmd+V / Cmd+A work in accessory app text fields
        setupMainMenu()

        menuBarController = MenuBarController()
        menuBarController.delegate = self

        ReloaderEngine.shared.delegate = self

        // Listen for settings saved event from Preferences
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsSaved),
            name: NSNotification.Name("TrafficReloaderSettingsSaved"),
            object: nil
        )

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

    func menuBarDidChangeInterval(_ minutes: Int) {
        Logger.log("[AppDelegate] Check interval changed to %ld minutes. Restarting timer and checking now...", minutes)
        restartTimer()
        ReloaderEngine.shared.triggerReload(isManual: true)
    }

    @objc private func settingsSaved() {
        Logger.log("[AppDelegate] Settings saved event received. Restarting timer and triggering immediate sync...")
        restartTimer()
        ReloaderEngine.shared.triggerReload(isManual: true)
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

    // MARK: - Standard Edit Menu for Cut/Copy/Paste/SelectAll in Accessory Apps

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Traffic Reloader", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Traffic Reloader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. Edit menu (Crucial for Cmd+C, Cmd+V, Cmd+X, Cmd+A in accessory apps)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())

        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
