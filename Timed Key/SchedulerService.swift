import Foundation
import Darwin

struct ProcessResult {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
}

enum ProcessRunner {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ProcessResult(status: process.terminationStatus, output: output)
        } catch {
            return ProcessResult(status: -1, output: error.localizedDescription)
        }
    }
}

enum StableInstallState: Equatable {
    case ready(URL)
    case updateAvailable(URL)
    case missing
    case invalid(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .ready(let url):
            return url.deletingLastPathComponent().path
        case .updateAvailable:
            return "Stable copy needs this update"
        case .missing:
            return "Install a stable copy before scheduling"
        case .invalid(let message):
            return message
        }
    }
}

enum StableInstallManager {
    static let userApplicationsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
    static let canonicalURL = userApplicationsURL
        .appendingPathComponent("Timed Key.app", isDirectory: true)
    static let systemURL = URL(fileURLWithPath: "/Applications/Timed Key.app", isDirectory: true)

    static func state() -> StableInstallState {
        let current = Bundle.main.bundleURL.standardizedFileURL
        if isStableLocation(current) {
            return .ready(current)
        }

        var outdatedCandidate: URL?
        for candidate in [systemURL, canonicalURL] where FileManager.default.fileExists(atPath: candidate.path) {
            guard bundleIdentifier(at: candidate) == Bundle.main.bundleIdentifier else { continue }
            if versionsMatch(current, candidate) {
                return .ready(candidate.standardizedFileURL)
            }
            outdatedCandidate = outdatedCandidate ?? candidate.standardizedFileURL
        }

        if let outdatedCandidate {
            return .updateAvailable(outdatedCandidate)
        }
        return .missing
    }

    static func executionURL() -> URL? {
        if case .ready(let url) = state() { return url }
        return nil
    }

    static func installCurrentBuild() -> Result<URL, Error> {
        let current = Bundle.main.bundleURL.standardizedFileURL
        if isStableLocation(current) {
            return .success(current)
        }

        let fileManager = FileManager.default
        let stagingURL = userApplicationsURL
            .appendingPathComponent(".Timed Key.installing.app", isDirectory: true)

        do {
            try fileManager.createDirectory(at: userApplicationsURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            try fileManager.copyItem(at: current, to: stagingURL)

            if fileManager.fileExists(atPath: canonicalURL.path) {
                _ = try fileManager.replaceItemAt(
                    canonicalURL,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: stagingURL, to: canonicalURL)
            }

            guard bundleIdentifier(at: canonicalURL) == Bundle.main.bundleIdentifier,
                  versionsMatch(current, canonicalURL)
            else {
                throw NSError(
                    domain: "TimedKey.StableInstall",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "The stable copy could not be verified after installation."]
                )
            }

            return .success(canonicalURL.standardizedFileURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            return .failure(error)
        }
    }

    static func isStableLocation(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path == systemURL.standardizedFileURL.path
            || path == canonicalURL.standardizedFileURL.path
    }

    private static func versionsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = Bundle(url: lhs), let right = Bundle(url: rhs) else { return false }
        guard left.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            == right.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            && left.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            == right.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return false }

        guard let leftExecutable = left.executableURL,
              let rightExecutable = right.executableURL
        else { return false }
        return FileManager.default.contentsEqual(
            atPath: leftExecutable.path,
            andPath: rightExecutable.path
        )
    }

    private static func bundleIdentifier(at url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }
}

struct SchedulerHealth: Equatable {
    let activeSchedules: Int
    let installedAgents: Int
    let problems: [String]

    var isHealthy: Bool { problems.isEmpty && installedAgents == activeSchedules }
    var summary: String {
        if isHealthy {
            return activeSchedules == 0 ? "Ready for schedules" : "\(activeSchedules) agent\(activeSchedules == 1 ? "" : "s") verified"
        }
        return problems.first ?? "Scheduler requires attention"
    }
}

enum LaunchAgentManager {
    static let labelPrefix = "com.timedkey.trigger."

    static func label(for scheduleID: UUID) -> String {
        labelPrefix + scheduleID.uuidString.lowercased()
    }

    static func plistURL(for scheduleID: UUID) -> URL {
        launchAgentsDirectory.appendingPathComponent("\(label(for: scheduleID)).plist")
    }

    @discardableResult
    static func install(_ schedule: TimedKeySchedule, appBundleURL: URL) -> ProcessResult {
        guard StableInstallManager.isStableLocation(appBundleURL) else {
            return ProcessResult(
                status: -1,
                output: "Timed Key must be installed in Applications before a reliable schedule can be created."
            )
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.month, .day, .weekday, .hour, .minute, .second],
            from: schedule.fireDate
        )
        guard let hour = components.hour,
              let minute = components.minute,
              let second = components.second
        else {
            return ProcessResult(status: -1, output: "The selected date or time is invalid.")
        }

        var fireArguments = [
            "/usr/bin/open", "-W", "-n", "-g", "-j", appBundleURL.standardizedFileURL.path,
            "--args", "--fire", String(schedule.keyCode), schedule.appName,
            "--schedule-id", schedule.id.uuidString,
            "--hour", String(hour),
            "--minute", String(minute),
            "--second", String(second),
            "--start-epoch", String(schedule.fireDate.timeIntervalSince1970),
            "--repeat-mode", schedule.repeatMode.rawValue,
            "--key-name", schedule.keyName
        ]
        if let bundleIdentifier = schedule.appBundleIdentifier, !bundleIdentifier.isEmpty {
            fireArguments += ["--target-bundle-id", bundleIdentifier]
        }
        if let appURLPath = schedule.appURLPath, !appURLPath.isEmpty {
            fireArguments += ["--target-app-path", appURLPath]
        }

        let interval = calendarInterval(
            mode: schedule.repeatMode,
            month: components.month,
            day: components.day,
            weekday: components.weekday,
            hour: hour,
            minute: minute
        )
        let logPath = logsDirectory.appendingPathComponent("scheduled-fire.log").path
        var plist: [String: Any] = [
            "Label": label(for: schedule.id),
            "ProgramArguments": fireArguments,
            "StartCalendarInterval": interval,
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "ThrottleInterval": 10,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            plist["AssociatedBundleIdentifiers"] = [bundleIdentifier]
        }

        do {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logPath) {
                guard FileManager.default.createFile(
                    atPath: logPath,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                ) else {
                    return ProcessResult(status: -1, output: "Could not create the scheduled-run log.")
                }
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: logPath
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            let plistURL = plistURL(for: schedule.id)
            try data.write(to: plistURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: plistURL.path
            )

            let domain = "gui/\(getuid())"
            _ = ProcessRunner.run("/bin/launchctl", ["bootout", "\(domain)/\(label(for: schedule.id))"])
            let bootstrap = ProcessRunner.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            guard bootstrap.succeeded else { return bootstrap }

            let verification = ProcessRunner.run(
                "/bin/launchctl",
                ["print", "\(domain)/\(label(for: schedule.id))"]
            )
            guard verification.succeeded else {
                return ProcessResult(status: verification.status, output: "launchd did not retain the new schedule: \(verification.output)")
            }

            kickstartIfImminent(schedule)
            return ProcessResult(status: 0, output: "")
        } catch {
            return ProcessResult(status: -1, output: error.localizedDescription)
        }
    }

    @discardableResult
    static func uninstall(scheduleID: UUID) -> ProcessResult {
        let domain = "gui/\(getuid())"
        let service = "\(domain)/\(label(for: scheduleID))"
        let plist = plistURL(for: scheduleID)
        let bootout = ProcessRunner.run("/bin/launchctl", ["bootout", service])

        do {
            if FileManager.default.fileExists(atPath: plist.path) {
                try FileManager.default.removeItem(at: plist)
            }
        } catch {
            return ProcessResult(status: -1, output: "Could not remove the schedule file: \(error.localizedDescription)")
        }

        let stillLoaded = ProcessRunner.run("/bin/launchctl", ["print", service]).succeeded
        if stillLoaded {
            return ProcessResult(status: -1, output: "launchd still reports the schedule as loaded.")
        }

        if !bootout.succeeded,
           !bootout.output.localizedCaseInsensitiveContains("could not find service"),
           !bootout.output.localizedCaseInsensitiveContains("no such process") {
            return ProcessResult(status: bootout.status, output: bootout.output)
        }
        return ProcessResult(status: 0, output: "")
    }

    static func repairAndReconcile(_ schedules: inout [TimedKeySchedule], appBundleURL: URL?) -> [String] {
        var problems: [String] = []
        let now = Date()
        let calendar = Calendar.current

        for index in schedules.indices {
            let schedule = schedules[index]
            if schedule.repeatMode == .once,
               schedule.isEnabled,
               schedule.fireDate < calendar.startOfDay(for: now) {
                let record = ScheduleRunRecord(
                    scheduleID: schedule.id,
                    targetDate: schedule.fireDate,
                    status: .missed,
                    message: "The Mac was unavailable past the scheduled day. Use Retry to run it again.",
                    appName: schedule.appName,
                    keyName: schedule.keyName
                )
                schedules[index].lastRun = record
                schedules[index].isEnabled = false
                _ = uninstall(scheduleID: schedule.id)
            }
        }

        removeLegacyAgent()
        removeOrphans(knownScheduleIDs: Set(schedules.map(\.id)))

        guard let appBundleURL else {
            if schedules.contains(where: \.isEnabled) {
                problems.append("Install the current build in Applications to repair active schedules.")
            }
            _ = ScheduleStore.save(schedules)
            return problems
        }

        for schedule in schedules where schedule.isEnabled {
            let expectedPath = appBundleURL.standardizedFileURL.path
            let installed = installedArguments(for: schedule.id)
            if installed?.contains(expectedPath) != true
                || installed?.contains("--second") != true
                || installed?.contains("--schedule-id") != true {
                let result = install(schedule, appBundleURL: appBundleURL)
                if !result.succeeded {
                    problems.append("Could not repair \(schedule.keyName) → \(schedule.appName): \(result.output)")
                }
            }
        }

        _ = ScheduleStore.save(schedules)
        return problems
    }

    static func health(for schedules: [TimedKeySchedule], appBundleURL: URL?) -> SchedulerHealth {
        let enabled = schedules.filter(\.isEnabled)
        guard let appBundleURL else {
            return SchedulerHealth(
                activeSchedules: enabled.count,
                installedAgents: 0,
                problems: enabled.isEmpty ? [] : ["Stable installation required"]
            )
        }

        var installed = 0
        var problems: [String] = []
        let domain = "gui/\(getuid())"
        for schedule in enabled {
            let plist = plistURL(for: schedule.id)
            let arguments = installedArguments(for: schedule.id)
            let loaded = ProcessRunner.run(
                "/bin/launchctl",
                ["print", "\(domain)/\(label(for: schedule.id))"]
            ).succeeded
            let valid = FileManager.default.fileExists(atPath: plist.path)
                && loaded
                && arguments?.contains(appBundleURL.standardizedFileURL.path) == true
            if valid {
                installed += 1
            } else {
                problems.append("\(schedule.keyName) → \(schedule.appName) is not fully registered")
            }
        }

        return SchedulerHealth(
            activeSchedules: enabled.count,
            installedAgents: installed,
            problems: problems
        )
    }

    static func installedArguments(for scheduleID: UUID) -> [String]? {
        let url = plistURL(for: scheduleID)
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else { return nil }
        return plist["ProgramArguments"] as? [String]
    }

    static func removeOrphans(knownScheduleIDs: Set<UUID>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: launchAgentsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        let known = Set(knownScheduleIDs.map { $0.uuidString.lowercased() })
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(labelPrefix) else { continue }
            let suffix = String(name.dropFirst(labelPrefix.count)).lowercased()
            guard UUID(uuidString: suffix) != nil, !known.contains(suffix) else { continue }
            _ = uninstallLabel(name, plistURL: file)
        }
    }

    private static func removeLegacyAgent() {
        let file = launchAgentsDirectory.appendingPathComponent("com.timedkey.trigger.plist")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        _ = uninstallLabel("com.timedkey.trigger", plistURL: file)
    }

    private static func uninstallLabel(_ label: String, plistURL: URL) -> ProcessResult {
        let service = "gui/\(getuid())/\(label)"
        let result = ProcessRunner.run("/bin/launchctl", ["bootout", service])
        try? FileManager.default.removeItem(at: plistURL)
        return result
    }

    private static func kickstartIfImminent(_ schedule: TimedKeySchedule) {
        guard let next = ScheduleCalculator.nextOccurrence(
            for: schedule,
            after: Date().addingTimeInterval(-1)
        ) else { return }
        let interval = next.timeIntervalSinceNow
        guard interval > 0, interval < 60 else { return }
        _ = ProcessRunner.run(
            "/bin/launchctl",
            ["kickstart", "-k", "gui/\(getuid())/\(label(for: schedule.id))"]
        )
    }

    private static func calendarInterval(
        mode: ScheduleRepeatMode,
        month: Int?,
        day: Int?,
        weekday: Int?,
        hour: Int,
        minute: Int
    ) -> Any {
        let base: [String: Any] = ["Hour": hour, "Minute": minute]
        switch mode {
        case .once:
            var once = base
            if let month { once["Month"] = month }
            if let day { once["Day"] = day }
            return once
        case .daily:
            return base
        case .weekdays:
            return Array(1...5).map { weekday -> [String: Any] in
                var value = base
                value["Weekday"] = weekday
                return value
            }
        case .weekends:
            return [0, 6].map { weekday -> [String: Any] in
                var value = base
                value["Weekday"] = weekday
                return value
            }
        case .weekly:
            var weekly = base
            if let weekday {
                weekly["Weekday"] = weekday - 1
            }
            return weekly
        }
    }

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Timed Key", isDirectory: true)
    }
}
