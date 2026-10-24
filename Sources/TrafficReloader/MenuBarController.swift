import Foundation
import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidChangeActive(_ active: Bool)
    func menuBarDidChangeInterval(_ minutes: Int)
    func menuBarDidRequestReload()
    func menuBarDidRequestQuit()
}

final class MenuBarHeaderView: NSView {
    private let quotaLabel = NSTextField(labelWithString: "Quota: Syncing...")
    private let statusLabel = NSTextField(labelWithString: "Status: Ready")

    var onHeaderClicked: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 48))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Quota Summary (Clean, 13pt semibold, standard labelColor)
        quotaLabel.frame = NSRect(x: 16, y: 25, width: 250, height: 18)
        quotaLabel.font = NSFont.systemFont(ofSize: 13.0, weight: .semibold)
        quotaLabel.textColor = .labelColor
        quotaLabel.lineBreakMode = .byTruncatingTail
        addSubview(quotaLabel)

        // 2. Status & Next Scan (Readable 12pt regular, labelColor)
        statusLabel.frame = NSRect(x: 16, y: 7, width: 250, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 12.0, weight: .regular)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        addSubview(statusLabel)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onHeaderClicked?()
    }

    func update(quota: String?, lastCheck: Date?, intervalMinutes: Int, status: String?) {
        // Format clean quota title
        if let q = quota, !q.isEmpty {
            if let openParen = q.range(of: " (davon ") {
                let mainPart = String(q[..<openParen.lowerBound])
                    .replacingOccurrences(of: " verbraucht", with: "")
                quotaLabel.stringValue = "Quota: \(mainPart)"
            } else {
                let clean = q.replacingOccurrences(of: " verbraucht", with: "")
                quotaLabel.stringValue = "Quota: \(clean)"
            }
        } else {
            quotaLabel.stringValue = "Quota: Not synced yet"
        }

        // Format clean status & next scan countdown
        let active = ConfigManager.shared.config.active
        if !active {
            statusLabel.stringValue = "Status: Paused (Deactivated)"
        } else if ReloaderEngine.shared.isRunning {
            statusLabel.stringValue = "Status: Checking quota now..."
        } else if let date = lastCheck {
            let elapsed = Int(Date().timeIntervalSince(date))
            let total = intervalMinutes * 60
            let remaining = max(0, total - elapsed)
            let remMin = remaining / 60
            let remSec = remaining % 60
            statusLabel.stringValue = String(format: "Active • Next scan in %02d:%02d", remMin, remSec)
        } else {
            statusLabel.stringValue = "Status: Active • Ready"
        }
    }
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    weak var delegate: MenuBarControllerDelegate?

    private var headerView: MenuBarHeaderView!
    private var activeMenuItem: NSMenuItem!
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

    private var menuTimer: Timer?

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStates()
        startMenuTimer()
    }

    func menuDidClose(_ menu: NSMenu) {
        stopMenuTimer()
    }

    private func startMenuTimer() {
        stopMenuTimer()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshMenuStates()
        }
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    private func stopMenuTimer() {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 1. Clean Minimal Header View (High contrast, readable, no emojis)
        headerView = MenuBarHeaderView()
        headerView.onHeaderClicked = { [weak self] in
            self?.menu.cancelTracking()
            self?.openStatistics()
        }
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        menu.addItem(headerItem)

        // 2. Open Detailed Statistics Modal Window
        let statsItem = NSMenuItem(title: "Usage & Statistics...", action: #selector(openStatistics), keyEquivalent: "s")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(NSMenuItem.separator())

        // 3. ACTIVE TOGGLE
        activeMenuItem = NSMenuItem(title: "Active (Auto-Reload)", action: #selector(toggleActive), keyEquivalent: "a")
        activeMenuItem.target = self
        menu.addItem(activeMenuItem)

        // 4. Check Now Button
        let reloadNowItem = NSMenuItem(title: "Check & Reload Now", action: #selector(triggerManualReload), keyEquivalent: "r")
        reloadNowItem.target = self
        menu.addItem(reloadNowItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Provider Submenu
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

        // 6. Interval Submenu
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

        // 7. Launch at Login
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        // 8. Preferences
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // 9. Open Log
        let logItem = NSMenuItem(title: "Open Log File", action: #selector(openLogFile), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        // 10. Quit
        let quitItem = NSMenuItem(title: "Quit Traffic Reloader", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        refreshMenuStates()
    }

    func refreshMenuStates() {
        let config = ConfigManager.shared.config

        // Update Minimal Clean Header View
        headerView?.update(
            quota: config.lastQuotaSummary,
            lastCheck: config.lastCheckDate,
            intervalMinutes: config.checkIntervalMinutes,
            status: config.lastStatus
        )

        // Active State
        activeMenuItem.state = config.active ? .on : .off

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

    @objc private func openStatistics() {
        StatisticsWindowController.shared.showStatistics()
    }

    @objc private func toggleActive() {
        let newActive = !ConfigManager.shared.config.active
        ConfigManager.shared.update(active: newActive)
        Logger.log("[MenuBar] User changed Active state to: %@", newActive ? "ENABLED" : "PAUSED")
        refreshMenuStates()
        StatisticsWindowController.shared.refreshUI()
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
        StatisticsWindowController.shared.refreshUI()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        let minutes = sender.tag
        ConfigManager.shared.update(checkIntervalMinutes: minutes)
        Logger.log("[MenuBar] Selected interval: %ld minutes", minutes)
        refreshMenuStates()
        StatisticsWindowController.shared.refreshUI()
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
        NSWorkspace.shared.open(logUrl)
    }

    @objc private func quitApp() {
        delegate?.menuBarDidRequestQuit()
    }
}
