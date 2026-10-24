import Foundation

enum ServiceweltStatus {
    case success(quotaBefore: String?, quotaAfter: String?, captchaSolved: Bool, message: String)
    case notNeeded(quota: String?, message: String)
    case buttonInactive(quota: String?, message: String)
    case failed(message: String)
}

final class ServiceweltClient {
    private let cookieJar = HTTPCookieStorage()
    private var session: URLSession!
    private let twoCaptcha = TwoCaptchaClient()

    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookieJar
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 35.0
        self.session = URLSession(configuration: config)
    }

    func executeReload(baseUrl: String, config: AppConfig) async -> ServiceweltStatus {
        guard !config.username.isEmpty, !config.password.isEmpty else {
            return .failed(message: "Servicewelt username and password are required. Set them in Settings.")
        }

        do {
            Logger.log("[ServiceweltClient] Starting reload cycle for: %@", baseUrl)

            // Step 1: Login
            let loginOk = try await performLogin(baseUrl: baseUrl, username: config.username, password: config.password)
            guard loginOk else {
                return .failed(message: "Login failed. Please check your username and password.")
            }

            // Step 2: Check /start for 'Datenvolumen nachbuchen'
            let startHtml = try await httpGet(url: "\(baseUrl)/start")
            let hasButton = startHtml.contains("Datenvolumen nachbuchen")

            if !hasButton {
                // Try reading quota from usage page anyway to update display
                let quotaSummary = try? await readQuotaSummary(baseUrl: baseUrl)
                return .notNeeded(quota: quotaSummary, message: "No 'Datenvolumen nachbuchen' button found. Sufficient traffic available.")
            }

            // Step 3: Fetch Data Usage Page
            let usageHtml = try await httpGet(url: "\(baseUrl)/mytariff/invoice/showGprsDataUsage")
            let quotaBefore = extractQuotaSummary(from: usageHtml)
            let buchenState = extractBuchenState(from: usageHtml)

            if !buchenState.exists {
                return .notNeeded(quota: quotaBefore, message: "Booking form not found on data usage page.")
            }

            if buchenState.disabled {
                return .buttonInactive(quota: quotaBefore, message: "'Buchen' button is currently disabled. Will retry later.")
            }

            // Step 4: Request Modal via AJAX
            Logger.log("[ServiceweltClient] Requesting booking modal via AJAX...")
            let modalHtml = try await httpPostForm(
                url: "\(baseUrl)/mytariff/invoice/getChangeServiceInfo",
                params: buchenState.inputs,
                headers: ["X-Requested-With": "XMLHttpRequest"]
            )

            // Step 5: Check Captcha
            var modalInputs = extractModalInputs(from: modalHtml)
            var captchaSolved = false

            if let captchaUrlMatch = matchRegex(pattern: "src=\"([^\"]*generate-captcha[^\"]*)\"", in: modalHtml) {
                var captchaPath = decodeHtmlEntities(captchaUrlMatch)
                if !captchaPath.hasPrefix("http") {
                    if !captchaPath.hasPrefix("/") {
                        captchaPath = "/" + captchaPath
                    }
                    captchaPath = baseUrl + captchaPath
                }

                Logger.log("[ServiceweltClient] Captcha detected: %@. Downloading...", captchaPath)
                guard let captchaUrl = URL(string: captchaPath) else {
                    return .failed(message: "Invalid captcha URL")
                }

                let (captchaData, _) = try await session.data(from: captchaUrl)
                guard captchaData.count > 50 else {
                    return .failed(message: "Downloaded captcha image is empty or invalid.")
                }

                guard !config.captchaApiKey.isEmpty else {
                    return .failed(message: "Captcha was presented but 2Captcha API key is not configured in Settings.")
                }

                Logger.log("[ServiceweltClient] Sending captcha to 2Captcha API...")
                let base64Image = captchaData.base64EncodedString()
                let solution = try await twoCaptcha.solveImage(apiKey: config.captchaApiKey, base64Image: base64Image)
                captchaSolved = true

                let fieldName = findCaptchaFieldName(in: modalHtml) ?? "\(buchenState.serviceCodePrefix)[captcha]"
                modalInputs[fieldName] = solution
                Logger.log("[ServiceweltClient] Inserted solved captcha '%@' into field: %@", solution, fieldName)
            }

            // Step 6: Submit Booking Activation
            Logger.log("[ServiceweltClient] Submitting service activation request...")
            _ = try await httpPostForm(
                url: "\(baseUrl)/mytariff/invoice/changeService",
                params: modalInputs,
                headers: ["X-Requested-With": "XMLHttpRequest"]
            )

            // Step 7: Read updated quota
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            let afterHtml = try await httpGet(url: "\(baseUrl)/mytariff/invoice/showGprsDataUsage")
            let quotaAfter = extractQuotaSummary(from: afterHtml)

            Logger.log("[ServiceweltClient] SUCCESS! 2 GB booked. Quota: %@", quotaAfter ?? "N/A")
            return .success(
                quotaBefore: quotaBefore,
                quotaAfter: quotaAfter,
                captchaSolved: captchaSolved,
                message: "Successfully booked and activated 2 GB Highspeed-Datenpaket!"
            )

        } catch {
            Logger.log("[ServiceweltClient] Error during reload: %@", error.localizedDescription)
            return .failed(message: error.localizedDescription)
        }
    }

    private func performLogin(baseUrl: String, username: String, password: String) async throws -> Bool {
        let loginPageHtml = try await httpGet(url: "\(baseUrl)/")

        let sid = matchRegex(pattern: "name=\"_SID\"\\s+value=\"([^\"]+)\"", in: loginPageHtml) ?? ""
        let csrf = matchRegex(pattern: "name=\"UserLoginType\\[_token\\]\"\\s+value=\"([^\"]+)\"", in: loginPageHtml) ?? ""

        guard !csrf.isEmpty else {
            Logger.log("[ServiceweltClient] Failed to extract CSRF token from login page.")
            return false
        }

        let loginParams: [String: String] = [
            "_SID": sid,
            "UserLoginType[alias]": username,
            "UserLoginType[password]": password,
            "UserLoginType[logindata]": "",
            "UserLoginType[_token]": csrf
        ]

        _ = try await httpPostForm(url: "\(baseUrl)/public/login_check", params: loginParams)

        let startHtml = try await httpGet(url: "\(baseUrl)/start")
        let lower = startHtml.lowercased()

        if lower.contains("servicewelt") || lower.contains("startseite") || lower.contains("datenvolumen") {
            Logger.log("[ServiceweltClient] Authentication successful for user: %@", username)
            return true
        }

        return false
    }

    func readQuotaSummary(baseUrl: String) async throws -> String? {
        let usageHtml = try await httpGet(url: "\(baseUrl)/mytariff/invoice/showGprsDataUsage")
        return extractQuotaSummary(from: usageHtml)
    }

    // MARK: - HTML Extraction Helpers

    private func extractQuotaSummary(from html: String) -> String? {
        let quota = matchRegex(pattern: "\\d+[,.]\\d+\\s*GB\\s*von\\s*\\d+[,.]\\d+\\s*GB[^\n<]*", in: html)
        let snack = matchRegex(pattern: "davon\\s*\\d+\\s*x\\s*2[,.]00\\s*GB[^\n)<]*", in: html)

        if let q = quota {
            var result = q.trimmingCharacters(in: .whitespacesAndNewlines)
            if let s = snack {
                result += " (\(s.trimmingCharacters(in: .whitespacesAndNewlines)))"
            }
            return result
        }
        return nil
    }

    private struct BuchenState {
        let exists: Bool
        let disabled: Bool
        let serviceCodePrefix: String
        let inputs: [String: String]
    }

    private func extractBuchenState(from html: String) -> BuchenState {
        guard let formBody = matchRegexGroup(pattern: "<form[^>]+id=\"([^\"]*ChangeServiceType[^\"]*)\"[^>]*>(.*?)</form>", in: html, group: 2) else {
            return BuchenState(exists: false, disabled: true, serviceCodePrefix: "", inputs: [:])
        }

        let isDisabled = formBody.contains("disabled") || formBody.contains("c-button--disabled")
        let inputs = extractAllInputs(from: formBody)

        var prefix = "ChangeServiceType_V5I3"
        for key in inputs.keys {
            if let pMatch = matchRegexGroup(pattern: "^([a-zA-Z0-9_]+)\\[", in: key, group: 1) {
                prefix = pMatch
                break
            }
        }

        return BuchenState(
            exists: true,
            disabled: isDisabled,
            serviceCodePrefix: prefix,
            inputs: inputs
        )
    }

    private func extractModalInputs(from html: String) -> [String: String] {
        let searchHtml = matchRegexGroup(pattern: "<form[^>]+id=\"([^\"]*ChangeServiceType[^\"]*)\"[^>]*>(.*?)</form>", in: html, group: 2) ?? html
        return extractAllInputs(from: searchHtml)
    }

    private func extractAllInputs(from html: String) -> [String: String] {
        var results: [String: String] = [:]
        let regex = try? NSRegularExpression(pattern: "<input[^>]+name=\"([^\"]+)\"[^>]+value=\"([^\"]*)\"", options: .caseInsensitive)
        let nsString = html as NSString
        let matches = regex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

        for match in matches {
            if match.numberOfRanges >= 3 {
                let name = nsString.substring(with: match.range(at: 1))
                let val = nsString.substring(with: match.range(at: 2))
                results[name] = decodeHtmlEntities(val)
            }
        }
        return results
    }

    private func findCaptchaFieldName(in html: String) -> String? {
        return matchRegexGroup(pattern: "<input[^>]+name=\"([^\"]*captcha[^\"]*)\"", in: html, group: 1)
    }

    private func matchRegex(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let first = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        if first.numberOfRanges > 1 {
            return ns.substring(with: first.range(at: 1))
        }
        return ns.substring(with: first.range(at: 0))
    }

    private func matchRegexGroup(pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let first = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard group < first.numberOfRanges else { return nil }
        return ns.substring(with: first.range(at: group))
    }

    private func decodeHtmlEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: - HTTP Primitives

    private func httpGet(url: String) async throws -> String {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func httpPostForm(url: String, params: [String: String], headers: [String: String] = [:]) async throws -> String {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")

        for (k, v) in headers {
            req.setValue(v, forHTTPHeaderField: k)
        }

        let bodyString = params.compactMap { key, value -> String? in
            guard let encKey = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let encVal = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
            return "\(encKey)=\(encVal)"
        }.joined(separator: "&")

        req.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
