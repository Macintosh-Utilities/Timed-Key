import Foundation
import Darwin

let schedulesDefaultsKey = "timedKey.multipleSchedules.v2"
let legacySchedulesDefaultsKey = "timedKey.multipleSchedules.v1"
let lastRunDefaultsKey = "timedKey.lastRun.v1"

enum ScheduleRepeatMode: String, Codable, CaseIterable, Identifiable {
    case once
    case daily
    case weekdays
    case weekends
    case weekly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .once: "One Time"
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekends: "Weekends"
        case .weekly: "Weekly"
        }
    }
}

enum ScheduleRunStatus: String, Codable {
    case succeeded
    case failed
    case deferred
    case missed

    var displayName: String {
        switch self {
        case .succeeded: "Success"
        case .failed: "Failed"
        case .deferred: "Deferred"
        case .missed: "Missed"
        }
    }
}

struct ScheduleRunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let scheduleID: UUID?
    let recordedAt: Date
    let targetDate: Date?
    let status: ScheduleRunStatus
    let message: String
    let appName: String
    let keyName: String
    let drift: TimeInterval?

    init(
        scheduleID: UUID?,
        targetDate: Date?,
        status: ScheduleRunStatus,
        message: String,
        appName: String,
        keyName: String,
        drift: TimeInterval? = nil
    ) {
        id = UUID()
        self.scheduleID = scheduleID
        recordedAt = Date()
        self.targetDate = targetDate
        self.status = status
        self.message = message
        self.appName = appName
        self.keyName = keyName
        self.drift = drift
    }
}

struct TimedKeySchedule: Identifiable, Codable, Equatable {
    let id: UUID
    var fireDate: Date
    var keyName: String
    var keyCode: UInt16
    var appName: String
    var appBundleIdentifier: String?
    var appURLPath: String?
    var isEnabled: Bool
    var repeatMode: ScheduleRepeatMode
    var lastRun: ScheduleRunRecord?

    init(
        id: UUID = UUID(),
        fireDate: Date,
        keyName: String,
        keyCode: UInt16,
        appName: String,
        appBundleIdentifier: String? = nil,
        appURLPath: String? = nil,
        isEnabled: Bool = true,
        repeatMode: ScheduleRepeatMode,
        lastRun: ScheduleRunRecord? = nil
    ) {
        self.id = id
        self.fireDate = fireDate
        self.keyName = keyName
        self.keyCode = keyCode
        self.appName = appName
        self.appBundleIdentifier = appBundleIdentifier
        self.appURLPath = appURLPath
        self.isEnabled = isEnabled
        self.repeatMode = repeatMode
        self.lastRun = lastRun
    }
}

private struct LegacyTimedKeySchedule: Codable {
    let id: UUID
    var hour: Int
    var minute: Int
    var keyName: String
    var keyCode: UInt16
    var appName: String
    var isEnabled: Bool
}

enum ScheduleCalculator {
    static func shouldRun(
        _ schedule: TimedKeySchedule,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        let startDay = calendar.startOfDay(for: schedule.fireDate)
        guard day >= startDay else { return false }

        switch schedule.repeatMode {
        case .once:
            return calendar.isDate(date, inSameDayAs: schedule.fireDate)
        case .daily:
            return true
        case .weekdays:
            return (2...6).contains(calendar.component(.weekday, from: date))
        case .weekends:
            let weekday = calendar.component(.weekday, from: date)
            return weekday == 1 || weekday == 7
        case .weekly:
            return calendar.component(.weekday, from: date)
                == calendar.component(.weekday, from: schedule.fireDate)
        }
    }

    static func occurrence(
        for schedule: TimedKeySchedule,
        on day: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let time = calendar.dateComponents([.hour, .minute, .second], from: schedule.fireDate)
        guard let hour = time.hour, let minute = time.minute, let second = time.second else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)
    }

    static func nextOccurrence(
        for schedule: TimedKeySchedule,
        after reference: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if schedule.repeatMode == .once {
            return schedule.fireDate >= reference ? schedule.fireDate : nil
        }

        for offset in 0...14 {
            guard let day = calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: reference)
            ) else { continue }

            guard shouldRun(schedule, on: day, calendar: calendar),
                  let candidate = occurrence(for: schedule, on: day, calendar: calendar),
                  candidate >= reference
            else { continue }

            return candidate
        }

        return nil
    }
}

enum ScheduleStore {
    static func load() -> [TimedKeySchedule] {
        withExclusiveLock {
            UserDefaults.standard.synchronize()

            if let data = UserDefaults.standard.data(forKey: schedulesDefaultsKey),
               let schedules = try? JSONDecoder().decode([TimedKeySchedule].self, from: data) {
                return schedules
            }

            guard let legacyData = UserDefaults.standard.data(forKey: legacySchedulesDefaultsKey) else {
                return []
            }

            if let schedules = try? JSONDecoder().decode([TimedKeySchedule].self, from: legacyData) {
                persistUnlocked(schedules)
                return schedules
            }

            guard let legacy = try? JSONDecoder().decode([LegacyTimedKeySchedule].self, from: legacyData) else {
                return []
            }

            let calendar = Calendar.current
            let now = Date()
            let migrated = legacy.map { old -> TimedKeySchedule in
                var components = calendar.dateComponents([.year, .month, .day], from: now)
                components.hour = old.hour
                components.minute = old.minute
                components.second = 0
                return TimedKeySchedule(
                    id: old.id,
                    fireDate: calendar.date(from: components) ?? now,
                    keyName: old.keyName,
                    keyCode: old.keyCode,
                    appName: old.appName,
                    isEnabled: old.isEnabled,
                    repeatMode: .daily
                )
            }
            persistUnlocked(migrated)
            return migrated
        }
    }

    @discardableResult
    static func save(_ schedules: [TimedKeySchedule]) -> Bool {
        withExclusiveLock {
            persistUnlocked(schedules)
        }
    }

    static func lastRun() -> ScheduleRunRecord? {
        withExclusiveLock {
            UserDefaults.standard.synchronize()
            guard let data = UserDefaults.standard.data(forKey: lastRunDefaultsKey) else { return nil }
            return try? JSONDecoder().decode(ScheduleRunRecord.self, from: data)
        }
    }

    static func record(_ record: ScheduleRunRecord, disableOneTimeOnFailure: Bool = false) {
        withExclusiveLock {
            var schedules = loadUnlocked()
            if let scheduleID = record.scheduleID,
               let index = schedules.firstIndex(where: { $0.id == scheduleID }) {
                schedules[index].lastRun = record
                if disableOneTimeOnFailure, schedules[index].repeatMode == .once {
                    schedules[index].isEnabled = false
                }
            }
            persistUnlocked(schedules)
            if let data = try? JSONEncoder().encode(record) {
                UserDefaults.standard.set(data, forKey: lastRunDefaultsKey)
                UserDefaults.standard.synchronize()
            }
        }
    }

    static func completeOneTime(scheduleID: UUID, record: ScheduleRunRecord) {
        withExclusiveLock {
            var schedules = loadUnlocked()
            schedules.removeAll { $0.id == scheduleID }
            persistUnlocked(schedules)
            if let data = try? JSONEncoder().encode(record) {
                UserDefaults.standard.set(data, forKey: lastRunDefaultsKey)
                UserDefaults.standard.synchronize()
            }
        }
    }

    private static func loadUnlocked() -> [TimedKeySchedule] {
        UserDefaults.standard.synchronize()
        guard let data = UserDefaults.standard.data(forKey: schedulesDefaultsKey),
              let schedules = try? JSONDecoder().decode([TimedKeySchedule].self, from: data)
        else { return [] }
        return schedules
    }

    @discardableResult
    private static func persistUnlocked(_ schedules: [TimedKeySchedule]) -> Bool {
        guard let data = try? JSONEncoder().encode(schedules) else { return false }
        UserDefaults.standard.set(data, forKey: schedulesDefaultsKey)
        UserDefaults.standard.set(data, forKey: legacySchedulesDefaultsKey)
        return UserDefaults.standard.synchronize()
    }

    private static func withExclusiveLock<T>(_ body: () -> T) -> T {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Timed Key", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("schedules.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        if descriptor >= 0 {
            _ = flock(descriptor, LOCK_EX)
        }
        defer {
            if descriptor >= 0 {
                _ = flock(descriptor, LOCK_UN)
                Darwin.close(descriptor)
            }
        }

        return body()
    }
}
