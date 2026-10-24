import Foundation

final class Logger {
    static let shared = Logger()
    private let logFileURL: URL
    private let backupFileURL: URL
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.fcc.trafficreloader.logger", qos: .utility)
    private let maxLogSizeBytes: UInt64 = 2 * 1024 * 1024 // 2 MB limit

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".trafficreloader", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        self.logFileURL = dir.appendingPathComponent("trafficreloader.log")
        self.backupFileURL = dir.appendingPathComponent("trafficreloader.log.1")

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        openHandle()
    }

    var logPath: String {
        return logFileURL.path
    }

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        self.fileHandle?.seekToEndOfFile()
    }

    static func log(_ message: String, _ args: CVarArg...) {
        let formatted = String(format: message, arguments: args)
        shared.write(formatted)
    }

    static func writeRaw(_ rawText: String) {
        shared.queue.async {
            shared.rotateIfNeeded()
            guard let handle = shared.fileHandle, let data = rawText.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    /// Outputs an empty line preceding every new scan and prints a prominent scan start banner
    static func startScan(url: String, isManual: Bool = false) {
        writeRaw("\n")
        log("--------------------------------------------------------------------------------")
        let trigger = isManual ? "Manual Request" : "Scheduled Timer"
        log(">>> [SCAN START] Provider: %@ (%@)", url, trigger)
    }

    /// Prints a visually expressive result banner based on the outcome of the scan
    static func endScan(status: ServiceweltStatus) {
        switch status {
        case .success(let before, let after, let captchaSolved, let msg):
            writeRaw("\n")
            log("********************************************************************************")
            log("*** [RELOAD SUCCESS: +2 GB DATA SNACK BOOKED!] ********************************")
            log("********************************************************************************")
            if let b = before, let a = after {
                log("* Quota Before: %@", b)
                log("* Quota After:  %@", a)
            } else if let a = after ?? before {
                log("* Quota:        %@", a)
            }
            log("* Captcha:      %@", captchaSolved ? "Solved successfully via 2Captcha" : "Not required")
            log("* Server Note:  %@", msg)
            log("********************************************************************************\n")

        case .buttonInactive(let quota, _):
            log("--------------------------------------------------------------------------------")
            log("<<< [SCAN RESULT: IDLE - NO RELOAD NEEDED]")
            if let q = quota {
                log("* Quota:        %@", q)
            }
            log("* Reason:       'Buchen' button is disabled (quota threshold not reached yet)")
            log("--------------------------------------------------------------------------------")

        case .notNeeded(let quota, let msg):
            log("--------------------------------------------------------------------------------")
            log("<<< [SCAN RESULT: IDLE - NOT NEEDED]")
            if let q = quota {
                log("* Quota:        %@", q)
            }
            log("* Reason:       %@", msg)
            log("--------------------------------------------------------------------------------")

        case .failed(let msg):
            writeRaw("\n")
            log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            log("!!! [SCAN FAILED: ERROR OCCURRED] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            log("! Error:        %@", msg)
            log("! Action:       Will retry on next scheduled interval")
            log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n")
        }
    }

    private func write(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        NSLog("%@", message)

        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateIfNeeded()

            guard let handle = self.fileHandle, let data = line.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    private func rotateIfNeeded() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        let size = (attrs?[.size] as? UInt64) ?? 0

        if size >= maxLogSizeBytes {
            try? fileHandle?.close()
            fileHandle = nil

            try? FileManager.default.removeItem(at: backupFileURL)
            try? FileManager.default.moveItem(at: logFileURL, to: backupFileURL)

            openHandle()
            if let handle = fileHandle, let notice = "[\(dateFormatter.string(from: Date()))] [Logger] Log rotated (exceeded 2MB limit).\n".data(using: .utf8) {
                handle.write(notice)
            }
        }
    }
}
