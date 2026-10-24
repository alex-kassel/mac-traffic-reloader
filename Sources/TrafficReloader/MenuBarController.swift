import Foundation
import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidChangeActive(_ active: Bool)
    func menuBarDidChangeInterval(_ minutes: Int)
    func menuBarDidRequestReload()
    func menuBarDidRequestQuit()
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    weak var delegate: MenuBarControllerDelegate?

    private var activeMenuItem: NSMenuItem!
    private var quotaMenuItem: NSMenuItem!
    private var lastCheckMenuItem: NSMenuItem!
    private var lastStatusMenuItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var intervalSubmenu: NSMenu!
    private var providerSubmenu: NSMenu!

    override init() {
        super.init()
        setupStatusItem()
        buildMenu()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon(isReloading: false)
        statusItem.menu = menu
        menu.delegate = self
    }

    func updateStatusIcon(isReloading: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }

            if isReloading {
                button.image = nil
                button.title = "↻ 2GB"
                button.toolTip = "Traffic Reloader: Checking..."
                return
            }

            let active = ConfigManager.shared.config.active
            if #available(macOS 11.0, *) {
                let symbolName = active ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Traffic Reloader")
                image?.isTemplate = true
                button.image = image
                button.title = ""
            } else {
                button.image = nil
                button.title = active ? "📶 2GB" : "⏸ 2GB"
            }

            button.toolTip = active ? "Traffic Reloader: Active" : "Traffic Reloader: Paused (Deactivated)"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStates()
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 1. Quota Summary
        quotaMenuItem = NSMenuItem(title: "Quota: Checking...", action: nil, keyEquivalent: "")
        quotaMenuItem.isEnabled = false
        menu.addItem(quotaMenuItem)

        lastCheckMenuItem = NSMenuItem(title: "Last Check: Never", action: nil, keyEquivalent: "")
        lastCheckMenuItem.isEnabled = false
        menu.addItem(lastCheckMenuItem)

        lastStatusMenuItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        lastStatusMenuItem.isEnabled = false
        menu.addItem(lastStatusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 2. ACTIVE TOGGLE (Main user requirement)
        activeMenuItem = NSMenuItem(title: "Active (Auto-Reload)", action: #selector(toggleActive), keyEquivalent: "a")
        activeMenuItem.target = self
        menu.addItem(activeMenuItem)

        // 3. Check Now Button
        let reloadNowItem = NSMenuItem(title: "Check & Reload Now", action: #selector(triggerManualReload), keyEquivalent: "r")
        reloadNowItem.target = self
        menu.addItem(reloadNowItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Provider Submenu
        let providerParent = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        providerSubmenu = NSMenu(title: "Provider")
        for p in Provider.allCases {
            let item = NSMenuItem(title: p.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p
            providerSubmenu.addItem(item)
        }
        providerParent.submenu = providerSubmenu
        menu.addItem(providerParent)

        // 5. Interval Submenu
        let intervalParent = NSMenuItem(title: "Check Interval", action: nil, keyEquivalent: "")
        intervalSubmenu = NSMenu(title: "Check Interval")
        for min in [5, 10, 15, 30, 60] {
            let item = NSMenuItem(title: "\(min) minutes", action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = min
            intervalSubmenu.addItem(item)
        }
        intervalParent.submenu = intervalSubmenu
        menu.addItem(intervalParent)

        // 6. Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Preferences
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // 8. Open Log
        let logItem = NSMenuItem(title: "Open Log File", action: #selector(openLogFile), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        // 9. Quit
        let quitItem = NSMenuItem(title: "Quit Traffic Reloader", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuStates()
    }

    func refreshMenuStates() {
        let config = ConfigManager.shared.config

        // Active State
        activeMenuItem.state = config.active ? .on : .off

        // Quota
        if let quota = config.lastQuotaSummary, !quota.isEmpty {
            quotaMenuItem.title = "Quota: \(quota)"
        } else {
            quotaMenuItem.title = "Quota: Not synced yet"
        }

        // Last Check Time
        if let date = config.lastCheckDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            lastCheckMenuItem.title = "Last Check: \(formatter.string(from: date))"
        } else {
            lastCheckMenuItem.title = "Last Check: Never"
        }

        // Last Status
        if let status = config.lastStatus, !status.isEmpty {
            let short = status.count > 45 ? String(status.prefix(45)) + "..." : status
            lastStatusMenuItem.title = "Status: \(short)"
        } else {
            lastStatusMenuItem.title = "Status: Ready"
        }

        // Interval checks
        for item in intervalSubmenu.items {
            item.state = (item.tag == config.checkIntervalMinutes) ? .on : .off
        }

        // Provider checks
        for item in providerSubmenu.items {
            if let p = item.representedObject as? Provider {
                item.state = (p == config.provider) ? .on : .off
            }
        }

        // Login item
        launchAtLoginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off

        updateStatusIcon(isReloading: ReloaderEngine.shared.isRunning)
    }

    @objc private func toggleActive() {
        let newActive = !ConfigManager.shared.config.active
        ConfigManager.shared.update(active: newActive)
        Logger.log("[MenuBar] User changed Active state to: %@", newActive ? "ENABLED" : "PAUSED")
        refreshMenuStates()
        delegate?.menuBarDidChangeActive(newActive)
    }

    @objc private func triggerManualReload() {
        Logger.log("[MenuBar] Manual reload triggered by user.")
        delegate?.menuBarDidRequestReload()
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? Provider else { return }
        ConfigManager.shared.update(provider: p)
        Logger.log("[MenuBar] Selected provider: %@", p.displayName)
        refreshMenuStates()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        let minutes = sender.tag
        ConfigManager.shared.update(checkIntervalMinutes: minutes)
        Logger.log("[MenuBar] Selected interval: %ld minutes", minutes)
        refreshMenuStates()
        delegate?.menuBarDidChangeInterval(minutes)
    }

    @objc private func toggleLaunchAtLogin() {
        let current = LaunchAtLoginManager.shared.isEnabled
        _ = LaunchAtLoginManager.shared.setEnabled(!current)
        refreshMenuStates()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showPreferences()
    }

    @objc private func openLogFile() {
        let logUrl = URL(fileURLWithPath: Logger.shared.logPath)
        NSWorkspace.shared.activateFileViewerSelecting([logUrl])
    }

    @objc private func quitApp() {
        delegate?.menuBarDidRequestQuit()
    }
}
