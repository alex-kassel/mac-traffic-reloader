import Foundation
import AppKit

final class StatisticsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = StatisticsWindowController()

    private var providerLabel: NSTextField!
    private var accountLabel: NSTextField!

    private var quotaValueLabel: NSTextField!
    private var snackValueLabel: NSTextField!
    private var statusValueLabel: NSTextField!
    private var intervalValueLabel: NSTextField!
    private var lastCheckValueLabel: NSTextField!
    private var lastResultValueLabel: NSTextField!
    private var nextScanValueLabel: NSTextField!

    private var reloadBtn: NSButton!
    private var updateTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Usage & Statistics"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self

        setupUI()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        var y: CGFloat = 308.0

        // 1. Header (Provider & Account)
        providerLabel = NSTextField(labelWithString: "SIM24 Servicewelt")
        providerLabel.frame = NSRect(x: 24, y: y, width: 432, height: 22)
        providerLabel.font = NSFont.systemFont(ofSize: 16.0, weight: .bold)
        providerLabel.textColor = .labelColor
        contentView.addSubview(providerLabel)

        y -= 20
        accountLabel = NSTextField(labelWithString: "Account: -")
        accountLabel.frame = NSRect(x: 24, y: y, width: 432, height: 18)
        accountLabel.font = NSFont.systemFont(ofSize: 12.0, weight: .regular)
        accountLabel.textColor = .labelColor
        contentView.addSubview(accountLabel)

        // 2. Statistics Group Box
        y -= 210
        let box = NSBox(frame: NSRect(x: 20, y: y, width: 440, height: 200))
        box.title = "Traffic & Usage Status"
        box.titleFont = NSFont.systemFont(ofSize: 12.0, weight: .semibold)
        contentView.addSubview(box)

        let boxView = NSView(frame: box.contentView!.bounds)
        boxView.autoresizingMask = [.width, .height]
        box.contentView = boxView

        var rowY: CGFloat = 148.0
        let colLabelX: CGFloat = 16.0
        let colValueX: CGFloat = 150.0
        let colValueWidth: CGFloat = 265.0
        let rowHeight: CGFloat = 24.0

        // Row 1: Quota
        let qTitle = makeRowLabel(text: "Data Quota:", x: colLabelX, y: rowY)
        boxView.addSubview(qTitle)
        quotaValueLabel = makeValueLabel(text: "Syncing...", x: colValueX, y: rowY, width: colValueWidth, bold: true)
        boxView.addSubview(quotaValueLabel)

        // Row 2: Active Snacks
        rowY -= rowHeight
        let sTitle = makeRowLabel(text: "Active Snacks:", x: colLabelX, y: rowY)
        boxView.addSubview(sTitle)
        snackValueLabel = makeValueLabel(text: "None", x: colValueX, y: rowY, width: colValueWidth)
        boxView.addSubview(snackValueLabel)

        // Row 3: Status
        rowY -= rowHeight
        let stTitle = makeRowLabel(text: "Auto-Reload:", x: colLabelX, y: rowY)
        boxView.addSubview(stTitle)
        statusValueLabel = makeValueLabel(text: "Active", x: colValueX, y: rowY, width: colValueWidth)
        boxView.addSubview(statusValueLabel)

        // Row 4: Interval
        rowY -= rowHeight
        let ivTitle = makeRowLabel(text: "Check Frequency:", x: colLabelX, y: rowY)
        boxView.addSubview(ivTitle)
        intervalValueLabel = makeValueLabel(text: "Every 5 minutes", x: colValueX, y: rowY, width: colValueWidth)
        boxView.addSubview(intervalValueLabel)

        // Row 5: Last Check
        rowY -= rowHeight
        let lcTitle = makeRowLabel(text: "Last Checked:", x: colLabelX, y: rowY)
        boxView.addSubview(lcTitle)
        lastCheckValueLabel = makeValueLabel(text: "Never", x: colValueX, y: rowY, width: colValueWidth)
        boxView.addSubview(lastCheckValueLabel)

        // Row 6: Next Scan
        rowY -= rowHeight
        let nsTitle = makeRowLabel(text: "Next Scan:", x: colLabelX, y: rowY)
        boxView.addSubview(nsTitle)
        nextScanValueLabel = makeValueLabel(text: "in --:--", x: colValueX, y: rowY, width: colValueWidth, monospaced: true)
        boxView.addSubview(nextScanValueLabel)

        // Row 7: Last Server Result
        rowY -= rowHeight
        let lrTitle = makeRowLabel(text: "Server Result:", x: colLabelX, y: rowY)
        boxView.addSubview(lrTitle)
        lastResultValueLabel = makeValueLabel(text: "Idle", x: colValueX, y: rowY, width: colValueWidth)
        boxView.addSubview(lastResultValueLabel)

        // 3. Bottom Action Buttons
        let bottomY: CGFloat = 16.0
        reloadBtn = NSButton(title: "Check & Reload Now", target: self, action: #selector(reloadNowClicked))
        reloadBtn.frame = NSRect(x: 20, y: bottomY, width: 170, height: 28)
        reloadBtn.bezelStyle = .rounded
        contentView.addSubview(reloadBtn)

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeBtn.frame = NSRect(x: 360, y: bottomY, width: 100, height: 28)
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        contentView.addSubview(closeBtn)
    }

    private func makeRowLabel(text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: 130, height: 18)
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .regular)
        label.textColor = .labelColor
        return label
    }

    private func makeValueLabel(text: String, x: CGFloat, y: CGFloat, width: CGFloat, bold: Bool = false, monospaced: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        if monospaced {
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: bold ? .bold : .medium)
        } else {
            label.font = NSFont.systemFont(ofSize: 12.5, weight: bold ? .bold : .regular)
        }
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func showStatistics() {
        refreshUI()
        startTimer()

        if let window = self.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refreshUI() {
        let config = ConfigManager.shared.config

        // Provider & Username
        let pName = config.provider.displayName
        let url = config.effectiveBaseUrl
        providerLabel.stringValue = "\(pName) (\(url))"
        let user = config.username.isEmpty ? "Not configured" : config.username
        accountLabel.stringValue = "Logged in as: \(user)"

        // Parse Quota & Snacks
        if let raw = config.lastQuotaSummary, !raw.isEmpty {
            if let openParen = raw.range(of: " (davon ") {
                let main = String(raw[..<openParen.lowerBound])
                let snack = String(raw[openParen.lowerBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
                quotaValueLabel.stringValue = main
                snackValueLabel.stringValue = snack
            } else {
                quotaValueLabel.stringValue = raw
                snackValueLabel.stringValue = "None"
            }
        } else {
            quotaValueLabel.stringValue = "Not synced yet"
            snackValueLabel.stringValue = "None"
        }

        // Status
        let isRunning = ReloaderEngine.shared.isRunning
        reloadBtn.isEnabled = !isRunning
        reloadBtn.title = isRunning ? "Checking..." : "Check & Reload Now"

        if isRunning {
            statusValueLabel.stringValue = "Checking quota now..."
        } else if config.active {
            statusValueLabel.stringValue = "Active (Auto-Reload enabled)"
        } else {
            statusValueLabel.stringValue = "Paused (Auto-Reload disabled)"
        }

        // Interval
        intervalValueLabel.stringValue = "Every \(config.checkIntervalMinutes) minutes"

        // Last Checked
        if let date = config.lastCheckDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss (dd.MM.yyyy)"
            lastCheckValueLabel.stringValue = formatter.string(from: date)
        } else {
            lastCheckValueLabel.stringValue = "Never"
        }

        // Server Result
        if let status = config.lastStatus, !status.isEmpty {
            lastResultValueLabel.stringValue = status
        } else {
            lastResultValueLabel.stringValue = "Ready"
        }

        updateCountdown()
    }

    private func updateCountdown() {
        let config = ConfigManager.shared.config
        if !config.active {
            nextScanValueLabel.stringValue = "Paused"
            return
        }
        if ReloaderEngine.shared.isRunning {
            nextScanValueLabel.stringValue = "Scan in progress..."
            return
        }

        if let date = config.lastCheckDate {
            let elapsed = Int(Date().timeIntervalSince(date))
            let total = config.checkIntervalMinutes * 60
            let remaining = max(0, total - elapsed)
            let remMin = remaining / 60
            let remSec = remaining % 60
            nextScanValueLabel.stringValue = String(format: "in %02d:%02d", remMin, remSec)
        } else {
            nextScanValueLabel.stringValue = "Imminent"
        }
    }

    private func startTimer() {
        stopTimer()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }

    private func stopTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopTimer()
    }

    @objc private func reloadNowClicked() {
        ReloaderEngine.shared.triggerReload(isManual: true)
        refreshUI()
    }

    @objc private func closeClicked() {
        window?.close()
    }
}
