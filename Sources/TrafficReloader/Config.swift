import Foundation

struct AppConfig: Codable {
    var provider: Provider = .sim24
    var customHost: String = ""
    var username: String = ""
    var password: String = ""
    var captchaApiKey: String = ""
    var checkIntervalMinutes: Int = 15
    var active: Bool = true
    var notificationsEnabled: Bool = true

    var lastQuotaSummary: String? = nil
    var lastCheckDate: Date? = nil
    var lastStatus: String? = nil

    var effectiveBaseUrl: String {
        if provider == .custom {
            var host = customHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.hasPrefix("http://") && !host.hasPrefix("https://") {
                host = "https://" + host
            }
            if host.hasSuffix("/") {
                host = String(host.dropLast())
            }
            return host.isEmpty ? "https://service.sim24.de" : host
        }
        return provider.defaultHost
    }
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let fileManager = FileManager.default
    private let configDir: URL
    private let configFile: URL
    private let envFile: URL

    private(set) var config: AppConfig

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".trafficreloader", isDirectory: true)
        configFile = configDir.appendingPathComponent("config.json")
        envFile = configDir.appendingPathComponent(".env")

        try? fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        config = ConfigManager.load(from: configFile)

        // If config.json didn't exist or was empty, check if we can import from existing sim24 .env
        importFromLegacyEnvIfNeeded()
    }

    private static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url) else {
            return AppConfig()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode(AppConfig.self, from: data) {
            return loaded
        }

        // Fallback for non-iso8601 date formats
        if let fallback = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return fallback
        }

        return AppConfig()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
    }

    func update(
        provider: Provider? = nil,
        customHost: String? = nil,
        username: String? = nil,
        password: String? = nil,
        captchaApiKey: String? = nil,
        checkIntervalMinutes: Int? = nil,
        active: Bool? = nil,
        notificationsEnabled: Bool? = nil,
        lastQuotaSummary: String? = nil,
        lastCheckDate: Date? = nil,
        lastStatus: String? = nil
    ) {
        if let provider = provider { config.provider = provider }
        if let customHost = customHost { config.customHost = customHost }
        if let username = username { config.username = username }
        if let password = password { config.password = password }
        if let captchaApiKey = captchaApiKey { config.captchaApiKey = captchaApiKey }
        if let checkIntervalMinutes = checkIntervalMinutes { config.checkIntervalMinutes = max(1, checkIntervalMinutes) }
        if let active = active { config.active = active }
        if let notificationsEnabled = notificationsEnabled { config.notificationsEnabled = notificationsEnabled }
        if let lastQuotaSummary = lastQuotaSummary { config.lastQuotaSummary = lastQuotaSummary }
        if let lastCheckDate = lastCheckDate { config.lastCheckDate = lastCheckDate }
        if let lastStatus = lastStatus { config.lastStatus = lastStatus }

        save()
    }

    private func importFromLegacyEnvIfNeeded() {
        if !config.username.isEmpty || !config.password.isEmpty {
            return
        }

        // Check if there is an existing .env in Herd / package directory or ~/.trafficreloader/.env
        let possibleEnvPaths = [
            envFile.path,
            NSHomeDirectory() + "/Projects/PHP/Herd/packages-dev/packages/alex-kassel/sim24-traffic-reloader/.env"
        ]

        for path in possibleEnvPaths {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            var found = false
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SIM24_USER=") {
                    config.username = String(trimmed.dropFirst("SIM24_USER=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
                    found = true
                } else if trimmed.hasPrefix("SIM24_PWD=") {
                    config.password = String(trimmed.dropFirst("SIM24_PWD=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
                    found = true
                } else if trimmed.hasPrefix("2CAPTCHA_API_KEY=") {
                    config.captchaApiKey = String(trimmed.dropFirst("2CAPTCHA_API_KEY=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
                    found = true
                }
            }
            if found {
                Logger.log("[Config] Imported credentials from existing .env: %@", path)
                save()
                break
            }
        }
    }
}
