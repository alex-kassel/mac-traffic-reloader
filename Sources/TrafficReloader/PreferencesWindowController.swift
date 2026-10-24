import Foundation
import AppKit

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var providerPopUp: NSPopUpButton!
    private var customHostField: NSTextField!
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var touchIdBtn: NSButton!
    private var captchaKeyField: NSSecureTextField!
    private var balanceLabel: NSTextField!
    private var intervalPopUp: NSPopUpButton!
    private var notifyCheckBox: NSButton!
    private var keychainCheckBox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 410),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Traffic Reloader Settings"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)

        setupUI()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        var y: CGFloat = 360.0
        let labelX: CGFloat = 20.0
        let fieldX: CGFloat = 160.0
        let fieldWidth: CGFloat = 270.0

        // 1. Provider
        let providerLabel = createLabel(text: "Servicewelt Provider:", x: labelX, y: y)
        contentView.addSubview(providerLabel)

        providerPopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: fieldWidth, height: 26), pullsDown: false)
        for p in Provider.allCases {
            providerPopUp.addItem(withTitle: p.displayName)
            providerPopUp.lastItem?.representedObject = p
        }
        providerPopUp.target = self
        providerPopUp.action = #selector(providerChanged)
        contentView.addSubview(providerPopUp)

        // 2. Custom Host
        y -= 36
        let customHostLabel = createLabel(text: "Custom Domain:", x: labelX, y: y)
        contentView.addSubview(customHostLabel)
        customHostField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 22))
        customHostField.placeholderString = "https://service.example.de"
        contentView.addSubview(customHostField)

        // 3. Username with Apple AutoFill support
        y -= 36
        let userLabel = createLabel(text: "Username / Phone:", x: labelX, y: y)
        contentView.addSubview(userLabel)
        usernameField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 22))
        usernameField.placeholderString = "01511234567 or username"
        if #available(macOS 11.0, *) {
            usernameField.contentType = .username
        }
        contentView.addSubview(usernameField)

        // 4. Password with Apple AutoFill & Touch ID Button
        y -= 36
        let pwdLabel = createLabel(text: "Servicewelt Password:", x: labelX, y: y)
        contentView.addSubview(pwdLabel)

        let pwdFieldWidth: CGFloat = 185.0
        passwordField = NSSecureTextField(frame: NSRect(x: fieldX, y: y - 2, width: pwdFieldWidth, height: 22))
        if #available(macOS 11.0, *) {
            passwordField.contentType = .password
        }
        contentView.addSubview(passwordField)

        // Touch ID button
        touchIdBtn = NSButton(title: "Touch ID", target: self, action: #selector(touchIdClicked))
        touchIdBtn.frame = NSRect(x: fieldX + pwdFieldWidth + 6, y: y - 4, width: 78, height: 25)
        touchIdBtn.bezelStyle = .rounded
        if #available(macOS 11.0, *) {
            let img = NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID")
            if img != nil {
                touchIdBtn.image = img
                touchIdBtn.imagePosition = .imageLeading
            }
        }
        contentView.addSubview(touchIdBtn)

        // 5. 2Captcha API Key
        y -= 36
        let captchaLabel = createLabel(text: "2Captcha API Key:", x: labelX, y: y)
        contentView.addSubview(captchaLabel)
        captchaKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 22))
        captchaKeyField.placeholderString = "2Captcha secret key"
        contentView.addSubview(captchaKeyField)

        // Balance button + label
        y -= 28
        let balanceBtn = NSButton(title: "Check Balance", target: self, action: #selector(checkBalanceClicked))
        balanceBtn.frame = NSRect(x: fieldX, y: y, width: 110, height: 24)
        balanceBtn.bezelStyle = .rounded
        contentView.addSubview(balanceBtn)

        balanceLabel = createLabel(text: "", x: fieldX + 118, y: y + 2)
        balanceLabel.font = NSFont.systemFont(ofSize: 11.0)
        balanceLabel.textColor = .secondaryLabelColor
        contentView.addSubview(balanceLabel)

        // 6. Check Interval
        y -= 36
        let intervalLabel = createLabel(text: "Check Interval:", x: labelX, y: y)
        contentView.addSubview(intervalLabel)
        intervalPopUp = NSPopUpButton(frame: NSRect(x: fieldX, y: y - 4, width: 160, height: 26), pullsDown: false)
        let intervals = [5, 10, 15, 30, 60]
        for min in intervals {
            intervalPopUp.addItem(withTitle: "\(min) minutes")
            intervalPopUp.lastItem?.tag = min
        }
        contentView.addSubview(intervalPopUp)

        // 7. Apple Keychain Save Checkbox
        y -= 32
        keychainCheckBox = NSButton(checkboxWithTitle: "Save password to Apple Keychain", target: nil, action: nil)
        keychainCheckBox.frame = NSRect(x: fieldX, y: y, width: 310, height: 22)
        keychainCheckBox.state = .on
        contentView.addSubview(keychainCheckBox)

        // 8. Notifications
        y -= 26
        notifyCheckBox = NSButton(checkboxWithTitle: "Show notifications on reload (+2 GB)", target: nil, action: nil)
        notifyCheckBox.frame = NSRect(x: fieldX, y: y, width: 310, height: 22)
        contentView.addSubview(notifyCheckBox)

        // Bottom Save button
        y -= 45
        let saveBtn = NSButton(title: "Save & Check Now", target: self, action: #selector(saveClicked))
        saveBtn.frame = NSRect(x: fieldX + 110, y: y, width: 155, height: 28)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.frame = NSRect(x: fieldX + 20, y: y, width: 80, height: 28)
        cancelBtn.bezelStyle = .rounded
        contentView.addSubview(cancelBtn)
    }

    func showPreferences() {
        loadValues()
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadValues() {
        let config = ConfigManager.shared.config

        for item in providerPopUp.itemArray {
            if let p = item.representedObject as? Provider, p == config.provider {
                providerPopUp.select(item)
                break
            }
        }

        customHostField.stringValue = config.customHost
        customHostField.isEnabled = (config.provider == .custom)
        usernameField.stringValue = config.username

        // Load password: from config or Keychain fallback
        if !config.password.isEmpty {
            passwordField.stringValue = config.password
        } else if let kcPass = KeychainManager.shared.getPassword(service: config.effectiveBaseUrl, account: config.username) {
            passwordField.stringValue = kcPass
        }

        captchaKeyField.stringValue = config.captchaApiKey
        intervalPopUp.selectItem(withTag: config.checkIntervalMinutes)
        notifyCheckBox.state = config.notificationsEnabled ? .on : .off
        keychainCheckBox.state = .on
        balanceLabel.stringValue = ""
    }

    @objc private func providerChanged() {
        guard let p = providerPopUp.selectedItem?.representedObject as? Provider else { return }
        customHostField.isEnabled = (p == .custom)
    }

    @objc private func touchIdClicked() {
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = (providerPopUp.selectedItem?.representedObject as? Provider) ?? .sim24
        let service = (p == .custom) ? customHostField.stringValue : p.defaultHost

        Task {
            let authenticated = await KeychainManager.shared.authenticateWithTouchID(
                reason: "Access your stored credentials for \(p.displayName)"
            )

            guard authenticated else { return }

            await MainActor.run {
                // Check if we have password in Keychain
                if let pass = KeychainManager.shared.getPassword(service: service, account: username) {
                    self.passwordField.stringValue = pass
                    Logger.log("[Preferences] Filled password from Apple Keychain via Touch ID.")
                } else if let pass = KeychainManager.shared.getPassword(service: "https://service.sim24.de", account: username) {
                    self.passwordField.stringValue = pass
                    Logger.log("[Preferences] Filled password from Apple Keychain (SIM24 service) via Touch ID.")
                } else {
                    // Try finding any account stored
                    let accounts = KeychainManager.shared.findStoredAccounts(service: service)
                    if let first = accounts.first, let pass = KeychainManager.shared.getPassword(service: service, account: first) {
                        self.usernameField.stringValue = first
                        self.passwordField.stringValue = pass
                        Logger.log("[Preferences] Auto-detected account '%@' from Apple Keychain via Touch ID.", first)
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Touch ID Verified"
                        alert.informativeText = "No saved credentials found in Keychain for \(username.isEmpty ? "this service" : username). Enter your password once and it will be saved."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            }
        }
    }

    @objc private func checkBalanceClicked() {
        let key = captchaKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            balanceLabel.stringValue = "Key is empty"
            balanceLabel.textColor = .systemRed
            return
        }

        balanceLabel.stringValue = "Checking..."
        balanceLabel.textColor = .secondaryLabelColor

        Task {
            do {
                let client = TwoCaptchaClient()
                let balance = try await client.getBalance(apiKey: key)
                await MainActor.run {
                    self.balanceLabel.stringValue = String(format: "$%.2f", balance)
                    self.balanceLabel.textColor = .systemGreen
                }
            } catch {
                await MainActor.run {
                    self.balanceLabel.stringValue = "Error"
                    self.balanceLabel.textColor = .systemRed
                }
            }
        }
    }

    @objc private func saveClicked() {
        let p = (providerPopUp.selectedItem?.representedObject as? Provider) ?? .sim24
        let interval = intervalPopUp.selectedItem?.tag ?? 5
        let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        let captchaKey = captchaKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let customHost = customHostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveHost = (p == .custom) ? customHost : p.defaultHost

        // 1. Save to Apple Keychain if enabled
        if keychainCheckBox.state == .on && !username.isEmpty && !password.isEmpty {
            KeychainManager.shared.savePassword(service: effectiveHost, account: username, password: password)
            if !captchaKey.isEmpty {
                KeychainManager.shared.savePassword(service: "2captcha.com", account: "api_key", password: captchaKey)
            }
            Logger.log("[Preferences] Credentials saved to Apple Keychain.")
        }

        // 2. Update AppConfig
        ConfigManager.shared.update(
            provider: p,
            customHost: customHost,
            username: username,
            password: password,
            captchaApiKey: captchaKey,
            checkIntervalMinutes: interval,
            notificationsEnabled: (notifyCheckBox.state == .on)
        )

        Logger.log("[Preferences] Settings saved. Provider: %@, Interval: %ld min. Triggering immediate check...", p.displayName, interval)

        self.window?.close()

        // 3. Post notification to immediately restart timer and trigger check
        NotificationCenter.default.post(name: NSNotification.Name("TrafficReloaderSettingsSaved"), object: nil)
    }

    @objc private func cancelClicked() {
        self.window?.close()
    }

    private func createLabel(text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 135, height: 18)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 12.0)
        return label
    }
}
