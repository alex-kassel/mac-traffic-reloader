import Foundation

enum TwoCaptchaError: LocalizedError {
    case missingApiKey
    case invalidBase64
    case submissionError(String)
    case solvingError(String)
    case timeout
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "2Captcha API key is not configured. Please set your key in Settings."
        case .invalidBase64:
            return "Invalid base64 captcha image data."
        case .submissionError(let msg):
            return "2Captcha submission failed: \(msg)"
        case .solvingError(let msg):
            return "2Captcha solving error: \(msg)"
        case .timeout:
            return "2Captcha timed out after 60 seconds."
        case .networkError(let err):
            return "2Captcha network error: \(err.localizedDescription)"
        }
    }
}

final class TwoCaptchaClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        self.session = URLSession(configuration: config)
    }

    func getBalance(apiKey: String) async throws -> Double {
        guard !apiKey.isEmpty else {
            throw TwoCaptchaError.missingApiKey
        }

        guard let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://2captcha.com/res.php?key=\(encodedKey)&action=getbalance&json=1") else {
            throw TwoCaptchaError.submissionError("Invalid URL formatting")
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TwoCaptchaError.submissionError("Balance query failed (non-200 HTTP)")
        }

        struct BalanceResponse: Decodable {
            let status: Int
            let request: String
        }

        guard let parsed = try? JSONDecoder().decode(BalanceResponse.self, from: data) else {
            throw TwoCaptchaError.submissionError("Failed to decode balance response")
        }

        if parsed.status == 1, let balance = Double(parsed.request) {
            return balance
        }

        throw TwoCaptchaError.submissionError(parsed.request)
    }

    func solveImage(apiKey: String, base64Image: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw TwoCaptchaError.missingApiKey
        }

        let cleanBase64 = base64Image
            .replacingOccurrences(of: "data:image/png;base64,", with: "")
            .replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanBase64.isEmpty else {
            throw TwoCaptchaError.invalidBase64
        }

        // Step 1: Submit Task
        guard let submitUrl = URL(string: "https://2captcha.com/in.php") else {
            throw TwoCaptchaError.submissionError("Invalid submit URL")
        }

        var request = URLRequest(url: submitUrl)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "method": "base64",
            "key": apiKey,
            "body": cleanBase64,
            "json": "1"
        ]

        let postBodyString = params.compactMap { key, value -> String? in
            guard let encKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let encVal = value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
            return "\(encKey)=\(encVal)"
        }.joined(separator: "&")

        request.httpBody = postBodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TwoCaptchaError.submissionError("Task submission failed with non-200 HTTP")
        }

        struct SubmitResponse: Decodable {
            let status: Int
            let request: String
        }

        guard let parsed = try? JSONDecoder().decode(SubmitResponse.self, from: data) else {
            let rawStr = String(data: data, encoding: .utf8) ?? "unknown"
            throw TwoCaptchaError.submissionError("Invalid JSON from 2Captcha in.php: \(rawStr)")
        }

        guard parsed.status == 1 else {
            throw TwoCaptchaError.submissionError(parsed.request)
        }

        let captchaId = parsed.request
        Logger.log("[TwoCaptcha] Task submitted successfully (ID: %@). Waiting for solution...", captchaId)

        // Step 2: Poll for solution
        let timeoutSeconds: TimeInterval = 60.0
        let pollIntervalNanoseconds: UInt64 = 5_000_000_000 // 5 seconds
        let startTime = Date()

        // Wait initial 5 seconds before first poll
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)

        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            guard let encKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let encId = captchaId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let pollUrl = URL(string: "https://2captcha.com/res.php?key=\(encKey)&action=get&id=\(encId)&json=1") else {
                throw TwoCaptchaError.solvingError("Invalid poll URL")
            }

            let (pollData, pollResponse) = try await session.data(from: pollUrl)
            if let pHttp = pollResponse as? HTTPURLResponse, pHttp.statusCode == 200 {
                if let pollParsed = try? JSONDecoder().decode(SubmitResponse.self, from: pollData) {
                    if pollParsed.status == 1 {
                        let answer = pollParsed.request.trimmingCharacters(in: .whitespacesAndNewlines)
                        Logger.log("[TwoCaptcha] Captcha solved successfully: '%@'", answer)
                        return answer
                    }

                    if pollParsed.request != "CAPCHA_NOT_READY" {
                        throw TwoCaptchaError.solvingError(pollParsed.request)
                    }
                }
            }

            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        throw TwoCaptchaError.timeout
    }
}
