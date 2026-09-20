import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

enum TimedKeyLog {
    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Timed Key", isDirectory: true)
    private static let fileURL = directory.appendingPathComponent("scheduled-fire.log")

    static func write(_ message: String, date: Date = Date()) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        writeLine("[Timed Key] \(formatter.string(from: date)) \(message)\n")
    }

    static func writeTiming(target: Date, released: Date, drift: TimeInterval) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let line = String(
            format: "[Timed Key] target=%@ released=%@ drift=%+.3fs\n",
            formatter.string(from: target),
            formatter.string(from: released),
            drift
        )
        writeLine(line)
    }

    private static func writeLine(_ line: String) {
        let data = Data(line.utf8)
        FileHandle.standardError.write(data)

        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            fileURL.path,
            O_WRONLY | O_APPEND | O_CREAT,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return }
        defer { Darwin.close(descriptor) }
        _ = Darwin.fchmod(descriptor, S_IRUSR | S_IWUSR)
        data.withUnsafeBytes { buffer in
            guard let address = buffer.baseAddress else { return }
            _ = Darwin.write(descriptor, address, buffer.count)
        }
    }
}

enum DeliveryFailureKind: String {
    case permissionDenied
    case screenLocked
    case appUnavailable
    case launchTimedOut
    case activationFailed
    case eventCreationFailed

    var isTransient: Bool {
        switch self {
        case .screenLocked, .appUnavailable, .launchTimedOut, .activationFailed:
            true
        case .permissionDenied, .eventCreationFailed:
            false
        }
    }
}

struct KeyDeliveryResult {
    let succeeded: Bool
    let message: String
    let failureKind: DeliveryFailureKind?

    static func success(_ message: String) -> KeyDeliveryResult {
        KeyDeliveryResult(succeeded: true, message: message, failureKind: nil)
    }

    static func failure(_ kind: DeliveryFailureKind, _ message: String) -> KeyDeliveryResult {
        KeyDeliveryResult(succeeded: false, message: message, failureKind: kind)
    }
}

enum KeyEventSender {
    struct PermissionState: Equatable {
        let accessibility: Bool
        let postEvent: Bool

        var canSendKeys: Bool { accessibility && postEvent }
        var missingNames: [String] {
            var names: [String] = []
            if !accessibility { names.append("Accessibility") }
            if !postEvent { names.append("PostEvent") }
            return names
        }
    }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ]
        return AXIsProcessTrustedWithOptions(options)
    }

    static func hasPostEventPermission() -> Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestRequiredPermissions() -> PermissionState {
        let accessibility = hasAccessibilityPermission(prompt: true)
        var postEvent = CGPreflightPostEventAccess()
        if !postEvent {
            postEvent = CGRequestPostEventAccess()
        }
        return PermissionState(
            accessibility: accessibility || hasAccessibilityPermission(prompt: false),
            postEvent: postEvent || CGPreflightPostEventAccess()
        )
    }

    static func currentPermissionState() -> PermissionState {
        PermissionState(
            accessibility: hasAccessibilityPermission(prompt: false),
            postEvent: hasPostEventPermission()
        )
    }

    static func fire(
        keyCode: CGKeyCode,
        keyName: String,
        targetAppName: String,
        targetBundleIdentifier: String?,
        targetAppPath: String?
    ) -> KeyDeliveryResult {
        let permissions = currentPermissionState()
        guard permissions.canSendKeys else {
            let missing = permissions.missingNames.joined(separator: " and ")
            let message = "Missing \(missing) permission. Open Timed Key and finish granting access."
            log(message)
            return .failure(.permissionDenied, message)
        }

        guard !isScreenLocked else {
            let message = "The Mac is locked, so the key was not sent to another app."
            log(message)
            return .failure(.screenLocked, message)
        }

        guard let app = resolveAndLaunchApp(
            named: targetAppName,
            bundleIdentifier: targetBundleIdentifier,
            appPath: targetAppPath
        ) else {
            let message = "Could not find or launch \(targetAppName)."
            log(message)
            return .failure(.appUnavailable, message)
        }

        let launchDeadline = Date().addingTimeInterval(15)
        while Date() < launchDeadline, !app.isFinishedLaunching {
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard app.isFinishedLaunching else {
            let message = "\(targetAppName) did not finish launching within 15 seconds."
            log(message)
            return .failure(.launchTimedOut, message)
        }

        let focusDeadline = Date().addingTimeInterval(5)
        while Date() < focusDeadline {
            _ = app.activate(options: [.activateAllWindows])
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            let actual = NSWorkspace.shared.frontmostApplication?.localizedName ?? "another application"
            let message = "Could not make \(targetAppName) frontmost; \(actual) remained active. No key was sent."
            log(message)
            return .failure(.activationFailed, message)
        }

        Thread.sleep(forTimeInterval: 0.25)
        guard postKeyPress(keyCode: keyCode) else {
            let message = "Could not create keyboard events for \(keyName)."
            log(message)
            return .failure(.eventCreationFailed, message)
        }

        // WindowServer and TCC can finish attributing the event after post()
        // returns. Keep this signed process alive until that work completes.
        Thread.sleep(forTimeInterval: 1.5)
        let message = "\(keyName) was submitted to \(targetAppName)."
        log(message)
        return .success(message)
    }

    static var isScreenLocked: Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return dictionary["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private static func resolveAndLaunchApp(
        named name: String,
        bundleIdentifier: String?,
        appPath: String?
    ) -> NSRunningApplication? {
        if let bundleIdentifier,
           let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
           ).first {
            return running
        }
        if let running = findRunningApp(named: name) {
            return running
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let appPath, FileManager.default.fileExists(atPath: appPath) {
            process.arguments = [appPath]
        } else if let bundleIdentifier, !bundleIdentifier.isEmpty {
            process.arguments = ["-b", bundleIdentifier]
        } else {
            process.arguments = ["-a", name]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("open failed for \(name): \(error.localizedDescription)")
            return nil
        }
        guard process.terminationStatus == 0 else {
            log("open returned \(process.terminationStatus) for \(name)")
            return nil
        }

        for _ in 0..<75 {
            if let bundleIdentifier,
               let launched = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
               ).first {
                return launched
            }
            if let launched = findRunningApp(named: name) {
                return launched
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return nil
    }

    private static func findRunningApp(named name: String) -> NSRunningApplication? {
        let wanted = name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        return NSWorkspace.shared.runningApplications.first { app in
            guard let localizedName = app.localizedName else { return false }
            return localizedName.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ) == wanted
        }
    }

    private static func postKeyPress(keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
              )
        else { return false }

        source.localEventsSuppressionInterval = 0
        keyDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.035)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func log(_ message: String) {
        TimedKeyLog.write(message)
    }
}
