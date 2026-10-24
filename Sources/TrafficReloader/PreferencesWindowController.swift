import Foundation
import AppKit

final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private var providerPopUp: NSPopUpButton!
    private var customHostField: NSTextField!
    private var usernameField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var captchaKeyField: NSSecureTextField!
    private var balanceLabel: NSTextField!
    private var intervalPopUp: NSPopUpButton!
    private var notifyCheckBox: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
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

        var y: CGFloat = 330.0
        let labelX: CGFloat = 24.0
        let fieldX: CGFloat = 160.0
        let fieldWidth: CGFloat = 250.0

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

        // 3. Username
        y -= 36
        let userLabel = createLabel(text: "Username / Phone:", x: labelX, y: y)
        contentView.addSubview(userLabel)
        usernameField = NSTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 22))
        usernameField.placeholderString = "01511234567 or username"
        contentView.addSubview(usernameField)

        // 4. Password
        y -= 36
        let pwdLabel = createLabel(text: "Servicewelt Password:", x: labelX, y: y)
        contentView.addSubview(pwdLabel)
        passwordField = NSSecureTextField(frame: NSRect(x: fieldX, y: y - 2, width: fieldWidth, height: 22))
        contentView.addSubview(passwordField)

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

        // 7. Notifications
        y -= 32
        notifyCheckBox = NSButton(checkboxWithTitle: "Send notification upon successful reload", target: nil, action: nil)
        notifyCheckBox.frame = NSRect(x: fieldX, y: y, width: 260, height: 20)
        contentView.addSubview(notifyCheckBox)

        // Bottom Save button
        y -= 45
        let saveBtn = NSButton(title: "Save Changes", target: self, action: #selector(saveClicked))
        saveBtn.frame = NSRect(x: fieldX + 130, y: y, width: 120, height: 28)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        contentView.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.frame = NSRect(x: fieldX + 40, y: y, width: 80, height: 28)
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
        passwordField.stringValue = config.password
        captchaKeyField.stringValue = config.captchaApiKey

        intervalPopUp.selectItem(withTag: config.checkIntervalMinutes)
        notifyCheckBox.state = config.notificationsEnabled ? .on : .off
        balanceLabel.stringValue = ""
    }

    @objc private func providerChanged() {
        guard let p = providerPopUp.selectedItem?.representedObject as? Provider else { return }
        customHostField.isEnabled = (p == .custom)
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
        let interval = intervalPopUp.selectedItem?.tag ?? 15

        ConfigManager.shared.update(
            provider: p,
            customHost: customHostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            username: usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            password: passwordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            captchaApiKey: captchaKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            checkIntervalMinutes: interval,
            notificationsEnabled: (notifyCheckBox.state == .on)
        )

        Logger.log("[Preferences] Settings saved. Provider: %@, Interval: %ld min", p.displayName, interval)
        self.window?.close()
    }

    @objc private func cancelClicked() {
        self.window?.close()
    }

    private func createLabel(text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 140, height: 18)
        label.alignment = .right
        label.font = NSFont.systemFont(ofSize: 12.0)
        return label
    }
}
