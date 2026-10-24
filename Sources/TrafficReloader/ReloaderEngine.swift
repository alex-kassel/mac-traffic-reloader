import Foundation

protocol ReloaderEngineDelegate: AnyObject {
    func engineDidStartCycle()
    func engineDidFinishCycle(status: ServiceweltStatus)
}

final class ReloaderEngine {
    static let shared = ReloaderEngine()

    weak var delegate: ReloaderEngineDelegate?
    private(set) var isRunning: Bool = false
    private let client = ServiceweltClient()

    private init() {}

    func triggerReload(isManual: Bool = false) {
        guard !isRunning else {
            Logger.log("[ReloaderEngine] Reload is already in progress. Skipping trigger.")
            return
        }

        let config = ConfigManager.shared.config
        if !isManual && !config.active {
            Logger.log("[ReloaderEngine] App is currently DEACTIVATED. Skipping automatic check.")
            return
        }

        isRunning = true
        delegate?.engineDidStartCycle()

        Task {
            let baseUrl = config.effectiveBaseUrl
            // Start scan with an empty line delimiter and prominent header
            Logger.startScan(url: baseUrl, isManual: isManual)
            let status = await client.executeReload(baseUrl: baseUrl, config: config)

            await MainActor.run {
                self.handleResult(status: status)
                self.isRunning = false
                self.delegate?.engineDidFinishCycle(status: status)
            }
        }
    }

    private func handleResult(status: ServiceweltStatus) {
        let now = Date()
        var quotaSummary: String? = nil
        var statusStr = ""

        switch status {
        case .success(let before, let after, _, let msg):
            quotaSummary = after ?? before
            statusStr = msg
            ConfigManager.shared.update(
                lastQuotaSummary: quotaSummary,
                lastCheckDate: now,
                lastStatus: statusStr
            )
            NotificationManager.shared.send(
                title: "Traffic Reloaded (+2 GB)",
                body: "Successfully booked 2 GB data snack!\n\(after ?? "")"
            )

        case .notNeeded(let quota, let msg):
            quotaSummary = quota
            statusStr = msg
            ConfigManager.shared.update(
                lastQuotaSummary: quotaSummary ?? ConfigManager.shared.config.lastQuotaSummary,
                lastCheckDate: now,
                lastStatus: statusStr
            )

        case .buttonInactive(let quota, let msg):
            quotaSummary = quota
            statusStr = msg
            ConfigManager.shared.update(
                lastQuotaSummary: quotaSummary ?? ConfigManager.shared.config.lastQuotaSummary,
                lastCheckDate: now,
                lastStatus: statusStr
            )

        case .failed(let msg):
            statusStr = "Error: \(msg)"
            ConfigManager.shared.update(
                lastCheckDate: now,
                lastStatus: statusStr
            )
            NotificationManager.shared.send(
                title: "Traffic Reload Failed",
                body: msg
            )
        }

        // Output cycle summary and visually expressive end scan banner
        Logger.endScan(status: status)
    }
}
