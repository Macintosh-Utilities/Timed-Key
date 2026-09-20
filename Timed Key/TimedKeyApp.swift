import SwiftUI
import AppKit
import CoreGraphics
import QuartzCore
import Darwin

private enum TriggerDecision {
    case ready(target: Date, drift: TimeInterval)
    case skip
    case missed(target: Date, message: String)
}

private struct ScheduledFireRequest {
    let keyCode: CGKeyCode
    let keyName: String
    let appName: String
    let targetBundleIdentifier: String?
    let targetAppPath: String?
    let scheduleID: UUID
    let hour: Int
    let minute: Int
    let second: Int
    let startDate: Date
    let repeatMode: ScheduleRepeatMode

    static var current: ScheduledFireRequest? {
        parse(CommandLine.arguments)
    }

    static func parse(_ arguments: [String]) -> ScheduledFireRequest? {
        guard let fireIndex = arguments.firstIndex(of: "--fire"),
              arguments.count > fireIndex + 2,
              let rawKeyCode = UInt16(arguments[fireIndex + 1])
        else { return nil }

        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.count > index + 1
            else { return nil }
            return arguments[index + 1]
        }

        guard let scheduleIDString = value(after: "--schedule-id"),
              let scheduleID = UUID(uuidString: scheduleIDString),
              let rawHour = value(after: "--hour").flatMap(Int.init),
              let rawMinute = value(after: "--minute").flatMap(Int.init),
              let rawSecond = value(after: "--second").flatMap(Int.init),
              (0...23).contains(rawHour),
              (0...59).contains(rawMinute),
              (0...59).contains(rawSecond),
              let epoch = value(after: "--start-epoch").flatMap(Double.init),
              let repeatValue = value(after: "--repeat-mode"),
              let repeatMode = ScheduleRepeatMode(rawValue: repeatValue)
        else { return nil }

        return ScheduledFireRequest(
            keyCode: CGKeyCode(rawKeyCode),
            keyName: value(after: "--key-name") ?? "Key \(rawKeyCode)",
            appName: arguments[fireIndex + 2],
            targetBundleIdentifier: value(after: "--target-bundle-id"),
            targetAppPath: value(after: "--target-app-path"),
            scheduleID: scheduleID,
            hour: rawHour,
            minute: rawMinute,
            second: rawSecond,
            startDate: Date(timeIntervalSince1970: epoch),
            repeatMode: repeatMode
        )
    }

    func waitUntilDue(now initialNow: Date = Date()) -> TriggerDecision {
        let calendar = Calendar.current
        let target: Date

        if repeatMode == .once {
            if initialNow < calendar.startOfDay(for: startDate) {
                return .skip
            }
            guard calendar.isDate(initialNow, inSameDayAs: startDate) else {
                return .missed(
                    target: startDate,
                    message: "The Mac was unavailable until after the scheduled day."
                )
            }
            target = startDate
        } else {
            let shell = TimedKeySchedule(
                id: scheduleID,
                fireDate: startDate,
                keyName: keyName,
                keyCode: UInt16(keyCode),
                appName: appName,
                isEnabled: true,
                repeatMode: repeatMode
            )
            guard ScheduleCalculator.shouldRun(shell, on: initialNow, calendar: calendar),
                  let todayTarget = ScheduleCalculator.occurrence(
                    for: shell,
                    on: initialNow,
                    calendar: calendar
                  )
            else { return .skip }
            target = todayTarget
        }

        let initialDelay = target.timeIntervalSince(initialNow)
        if initialDelay > 70 {
            return .skip
        }

        let maximumLateness: TimeInterval = repeatMode == .once ? 12 * 60 * 60 : 15 * 60
        if initialDelay < -maximumLateness {
            return .missed(
                target: target,
                message: "The scheduled time was missed by more than \(Int(maximumLateness / 60)) minutes."
            )
        }

        while target.timeIntervalSinceNow > 0 {
            Thread.sleep(forTimeInterval: min(target.timeIntervalSinceNow, 0.2))
        }

        let drift = Date().timeIntervalSince(target)
        logTiming(target: target, drift: drift)
        return .ready(target: target, drift: drift)
    }

    private func logTiming(target: Date, drift: TimeInterval) {
        TimedKeyLog.writeTiming(target: target, released: Date(), drift: drift)
    }
}

private struct ScheduledRunBannerView: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.surfaceRaised)
                    .frame(width: 34, height: 34)
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Delivering scheduled key")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceRaised)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: pulse ? geometry.size.width : geometry.size.width * 0.32)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 370, height: 62)
        .background(Theme.window.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.30), radius: 18, x: 0, y: 8)
        .onAppear {
            guard !reduceMotion else {
                pulse = true
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private final class ScheduledRunBannerController {
    private let panel: NSPanel
    private let size = NSSize(width: 370, height: 62)
    private var targetOrigin = NSPoint.zero

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.contentView = NSHostingView(rootView: ScheduledRunBannerView())
    }

    func show() {
        guard let screen = preferredScreen() else { return }
        let frame = screen.visibleFrame
        targetOrigin = NSPoint(
            x: round(frame.midX - size.width / 2),
            y: round(frame.maxY - size.height - 12)
        )
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: targetOrigin.x, y: targetOrigin.y + 10))
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    func dismiss(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(
                NSPoint(x: targetOrigin.x, y: targetOrigin.y + 6)
            )
        }, completionHandler: { [panel] in
            panel.orderOut(nil)
            completion()
        })
    }

    private func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let request = ScheduledFireRequest.current
    private let isSelfTest = CommandLine.arguments.contains("--self-test")
    private var bannerController: ScheduledRunBannerController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard request != nil || isSelfTest else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isSelfTest {
            NSApp.setActivationPolicy(.accessory)
            let status = ReliabilitySelfTest.run()
            fflush(stdout)
            fflush(stderr)
            Darwin.exit(status)
        }

        guard let request else { return }
        NSApp.setActivationPolicy(.accessory)
        NSApp.unhideWithoutActivation()

        DispatchQueue.global(qos: .userInitiated).async {
            switch request.waitUntilDue() {
            case .skip:
                DispatchQueue.main.async { NSApp.terminate(nil) }

            case .missed(let target, let message):
                self.recordFailure(
                    request: request,
                    target: target,
                    status: .missed,
                    message: message,
                    drift: Date().timeIntervalSince(target)
                )
                DispatchQueue.main.async { Darwin.exit(2) }

            case .ready(let target, let drift):
                DispatchQueue.main.async {
                    self.beginDelivery(request: request, target: target, drift: drift)
                }
            }
        }
    }

    private func beginDelivery(
        request: ScheduledFireRequest,
        target: Date,
        drift: TimeInterval
    ) {
        let banner = ScheduledRunBannerController()
        bannerController = banner
        banner.show()

        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.deliverWithRecovery(request)
            let exitCode: Int32
            if result.succeeded {
                exitCode = 0
                let record = ScheduleRunRecord(
                    scheduleID: request.scheduleID,
                    targetDate: target,
                    status: .succeeded,
                    message: result.message,
                    appName: request.appName,
                    keyName: request.keyName,
                    drift: drift
                )
                if request.repeatMode == .once {
                    ScheduleStore.completeOneTime(scheduleID: request.scheduleID, record: record)
                    _ = LaunchAgentManager.uninstall(scheduleID: request.scheduleID)
                } else {
                    ScheduleStore.record(record)
                }
            } else {
                exitCode = 1
                self.recordFailure(
                    request: request,
                    target: target,
                    status: result.failureKind == .screenLocked ? .deferred : .failed,
                    message: result.message,
                    drift: drift
                )
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.finishDelivery(exitCode: exitCode)
            }
        }
    }

    private func deliverWithRecovery(_ request: ScheduledFireRequest) -> KeyDeliveryResult {
        let lockDeadline = Date().addingTimeInterval(5 * 60)
        var attempt = 0
        var lastResult = KeyDeliveryResult.failure(.appUnavailable, "Delivery was not attempted.")

        while attempt < 3 {
            lastResult = KeyEventSender.fire(
                keyCode: request.keyCode,
                keyName: request.keyName,
                targetAppName: request.appName,
                targetBundleIdentifier: request.targetBundleIdentifier,
                targetAppPath: request.targetAppPath
            )
            if lastResult.succeeded { return lastResult }

            if lastResult.failureKind == .screenLocked {
                while Date() < lockDeadline, KeyEventSender.isScreenLocked {
                    Thread.sleep(forTimeInterval: 2)
                }
                if KeyEventSender.isScreenLocked { return lastResult }
            } else if lastResult.failureKind?.isTransient != true {
                return lastResult
            }

            attempt += 1
            if attempt < 3 {
                Thread.sleep(forTimeInterval: attempt == 1 ? 2 : 5)
            }
        }
        return lastResult
    }

    private func recordFailure(
        request: ScheduledFireRequest,
        target: Date,
        status: ScheduleRunStatus,
        message: String,
        drift: TimeInterval
    ) {
        let record = ScheduleRunRecord(
            scheduleID: request.scheduleID,
            targetDate: target,
            status: status,
            message: message,
            appName: request.appName,
            keyName: request.keyName,
            drift: drift
        )
        let oneTime = request.repeatMode == .once
        ScheduleStore.record(record, disableOneTimeOnFailure: oneTime)
        if oneTime {
            _ = LaunchAgentManager.uninstall(scheduleID: request.scheduleID)
        }
    }

    private func finishDelivery(exitCode: Int32) {
        guard let bannerController else {
            Darwin.exit(exitCode)
        }
        bannerController.dismiss { [weak self] in
            guard let self else { return }
            self.bannerController = nil
            Darwin.exit(exitCode)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        request == nil
    }
}

@main
struct TimedKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let isHeadless = ScheduledFireRequest.current != nil
        || CommandLine.arguments.contains("--self-test")

    var body: some Scene {
        WindowGroup {
            Group {
                if isHeadless {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear {
                            DispatchQueue.main.async {
                                NSApp.windows
                                    .filter { !($0 is NSPanel) }
                                    .forEach { $0.orderOut(nil) }
                            }
                        }
                } else {
                    ContentView()
                        .frame(minWidth: 560, idealWidth: 620, minHeight: 680, idealHeight: 760)
                }
            }
        }
        .defaultSize(width: 620, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

private enum ReliabilitySelfTest {
    static func run() -> Int32 {
        var failures: [String] = []
        let calendar = Calendar(identifier: .gregorian)

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
            calendar.date(from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                second: second
            ))!
        }

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if !condition() { failures.append(name) }
        }

        let monday = date(2026, 9, 21, 9, 30, 5)
        let saturday = date(2026, 9, 19, 9, 30, 5)
        let base = TimedKeySchedule(
            fireDate: monday,
            keyName: "Return",
            keyCode: 36,
            appName: "Test App",
            repeatMode: .weekdays
        )
        check(ScheduleCalculator.shouldRun(base, on: monday, calendar: calendar), "weekday accepts Monday")
        check(!ScheduleCalculator.shouldRun(base, on: saturday, calendar: calendar), "weekday rejects Saturday")

        var weekend = base
        weekend.repeatMode = .weekends
        weekend.fireDate = saturday
        check(ScheduleCalculator.shouldRun(weekend, on: saturday, calendar: calendar), "weekend accepts Saturday")
        check(!ScheduleCalculator.shouldRun(weekend, on: monday, calendar: calendar), "weekend rejects Monday")

        var weekly = base
        weekly.repeatMode = .weekly
        check(ScheduleCalculator.shouldRun(weekly, on: monday, calendar: calendar), "weekly accepts anchor weekday")
        check(
            ScheduleCalculator.nextOccurrence(
                for: weekly,
                after: date(2026, 9, 21, 10, 0, 0),
                calendar: calendar
            ) == date(2026, 9, 28, 9, 30, 5),
            "weekly advances seven days"
        )

        var once = base
        once.repeatMode = .once
        check(
            ScheduleCalculator.nextOccurrence(
                for: once,
                after: date(2026, 9, 21, 9, 30, 4),
                calendar: calendar
            ) == monday,
            "one-time occurrence remains available before target"
        )
        check(
            ScheduleCalculator.nextOccurrence(
                for: once,
                after: date(2026, 9, 21, 9, 30, 6),
                calendar: calendar
            ) == nil,
            "one-time occurrence expires after target"
        )

        let id = UUID()
        let validArguments = [
            "Timed Key", "--fire", "36", "Test App",
            "--schedule-id", id.uuidString,
            "--hour", "9", "--minute", "30", "--second", "5",
            "--start-epoch", String(monday.timeIntervalSince1970),
            "--repeat-mode", "once", "--key-name", "Return"
        ]
        check(ScheduledFireRequest.parse(validArguments) != nil, "strict trigger parser accepts valid arguments")
        check(
            ScheduledFireRequest.parse(Array(validArguments.dropLast(4))) == nil,
            "strict trigger parser rejects incomplete arguments"
        )

        if failures.isEmpty {
            print("Timed Key self-test: PASS (9 checks)")
            return 0
        }

        print("Timed Key self-test: FAIL")
        failures.forEach { print("- \($0)") }
        return 1
    }
}
