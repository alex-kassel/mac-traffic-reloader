import Foundation
import AppKit

protocol MenuBarControllerDelegate: AnyObject {
    func menuBarDidChangeActive(_ active: Bool)
    func menuBarDidChangeInterval(_ minutes: Int)
    func menuBarDidRequestReload()
    func menuBarDidRequestQuit()
}

final class MenuBarHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "📊 Quota: Syncing...")
    private let snackLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "Checked: Never")
    private let statusLabel = NSTextField(labelWithString: "Status: Ready")

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 82))
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        // 1. Title / Quota (bright, bold, 100% readable)
        titleLabel.frame = NSRect(x: 16, y: 58, width: 268, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13.0, weight: .bold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        // 2. Data Snack subline (high contrast accent)
        snackLabel.frame = NSRect(x: 16, y: 39, width: 268, height: 16)
        snackLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        snackLabel.textColor = .systemGreen
        addSubview(snackLabel)

        // 3. Last Check & Countdown (clear secondary)
        timeLabel.frame = NSRect(x: 16, y: 21, width: 268, height: 15)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.0, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        addSubview(timeLabel)

        // 4. Status description
        statusLabel.frame = NSRect(x: 16, y: 5, width: 268, height: 14)
        statusLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        addSubview(statusLabel)
    }

    func update(quota: String?, lastCheck: Date?, intervalMinutes: Int, status: String?) {
        if let q = quota, !q.isEmpty {
            if let openParen = q.range(of: " (davon ") {
                let mainPart = String(q[..<openParen.lowerBound])
                let snackPart = String(q[openParen.lowerBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                titleLabel.stringValue = "📊 \(mainPart)"
                snackLabel.stringValue = "⚡ \(snackPart)"
                snackLabel.isHidden = false
            } else {
                titleLabel.stringValue = "📊 \(q)"
                snackLabel.isHidden = true
            }
        } else {
            titleLabel.stringValue = "📊 Quota: Not synced yet"
            snackLabel.isHidden = true
        }

        if let date = lastCheck {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let elapsed = Int(Date().timeIntervalSince(date))
            let total = intervalMinutes * 60
            let remaining = max(0, total - elapsed)
            let remMin = remaining / 60
            let remSec = remaining % 60
            timeLabel.stringValue = String(format: "Checked: %@ • Next in %02d:%02d", formatter.string(from: date), remMin, remSec)
        } else {
            timeLabel.stringValue = "Checked: Never"
        }

        if let s = status, !s.isEmpty {
            let short = s.count > 42 ? String(s.prefix(42)) + "..." : s
            statusLabel.stringValue = "Status: \(short)"
        } else {
            statusLabel.stringValue = "Status: Idle"
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

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuStates()
    }

    private func buildMenu() {
        menu.removeAllItems()

        // 1. High-Contrast Custom Header View (Bright, bold, readable)
        headerView = MenuBarHeaderView()
        let headerItem = NSMenuItem()
        headerItem.view = headerView
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. ACTIVE TOGGLE
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

        // Update High-Contrast Header View
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
        NSWorkspace.shared.open(logUrl)
    }

    @objc private func quitApp() {
        delegate?.menuBarDidRequestQuit()
    }
}
