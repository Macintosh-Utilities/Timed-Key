import SwiftUI
import AppKit
import Combine

private let otherAppOptionID = "timed-key.other-application"
private let stateRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

private struct TargetApplicationOption: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let appURLPath: String?

    static let other = TargetApplicationOption(
        id: otherAppOptionID,
        name: "Other…",
        bundleIdentifier: nil,
        appURLPath: nil
    )
}

private enum MessageTone {
    case neutral
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .neutral: Theme.textSecondary
        case .success: Theme.success
        case .warning: Theme.warning
        case .error: Theme.danger
        }
    }
}

struct ContentView: View {
    @State private var selectedDate = Date()
    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = Calendar.current.component(.minute, from: Date())
    @State private var selectedSecond = Calendar.current.component(.second, from: Date())
    @State private var manualTimeText = ""
    @State private var showsManualTimeEntry = false
    @FocusState private var manualTimeFocused: Bool

    @State private var repeatMode: ScheduleRepeatMode = .once
    @State private var selectedKey = commonKeys[0]
    @State private var appOptions: [TargetApplicationOption] = []
    @State private var selectedAppID = otherAppOptionID
    @State private var customAppName = ""

    @State private var schedules: [TimedKeySchedule] = []
    @State private var permissionState = KeyEventSender.currentPermissionState()
    @State private var stableInstallState = StableInstallManager.state()
    @State private var schedulerHealth = SchedulerHealth(
        activeSchedules: 0,
        installedAgents: 0,
        problems: []
    )
    @State private var lastRun: ScheduleRunRecord?
    @State private var message = "Choose when, which key, and the target app."
    @State private var messageTone = MessageTone.neutral
    @State private var refreshCounter = 0

    private var selectedApp: TargetApplicationOption? {
        appOptions.first { $0.id == selectedAppID }
    }

    private var resolvedAppName: String {
        selectedAppID == otherAppOptionID
            ? customAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedApp?.name ?? ""
    }

    private var activeSchedules: [TimedKeySchedule] {
        schedules.filter(\.isEnabled)
    }

    private var sortedSchedules: [TimedKeySchedule] {
        schedules.sorted { lhs, rhs in
            let left = ScheduleCalculator.nextOccurrence(for: lhs, after: Date()) ?? lhs.fireDate
            let right = ScheduleCalculator.nextOccurrence(for: rhs, after: Date()) ?? rhs.fireDate
            if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled && !rhs.isEnabled }
            if left != right { return left < right }
            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    private var nextSchedule: TimedKeySchedule? {
        activeSchedules
            .compactMap { schedule -> (TimedKeySchedule, Date)? in
                guard let next = ScheduleCalculator.nextOccurrence(for: schedule, after: Date()) else {
                    return nil
                }
                return (schedule, next)
            }
            .min { $0.1 < $1.1 }?.0
    }

    private var overallReady: Bool {
        permissionState.canSendKeys
            && stableInstallState.isReady
            && schedulerHealth.isHealthy
    }

    var body: some View {
        ZStack {
            Theme.window.ignoresSafeArea()
            GridBackdrop().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    nextScheduleSummary
                    mainWorkspace
                    scheduleQueue
                    statusMessage
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            syncTimeText()
            refreshApplications()
            loadAndRepairSchedules()
            refreshState(full: true)
        }
        .onReceive(stateRefreshTimer) { _ in
            refreshCounter += 1
            refreshState(full: refreshCounter.isMultiple(of: 5))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("MacUtilitiesIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Mac Utilities")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("Timed Key")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(overallReady ? Theme.success : Theme.warning)
                    .frame(width: 8, height: 8)
                Text(overallReady ? "System ready" : "Action needed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(overallReady ? Theme.success : Theme.warning)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background((overallReady ? Theme.success : Theme.warning).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke((overallReady ? Theme.success : Theme.warning).opacity(0.28))
            }
            .accessibilityLabel(overallReady ? "Timed Key system ready" : "Timed Key action needed")
        }
    }

    private var nextScheduleSummary: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT SCHEDULED PRESS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textMuted)

                if let nextSchedule,
                   let next = ScheduleCalculator.nextOccurrence(for: nextSchedule, after: Date()) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(summaryDate(next))
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text(timeWithSeconds(next))
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    Text("\(nextSchedule.keyName) will be sent to \(nextSchedule.appName) \(nextSchedule.repeatMode == .once ? "once" : nextSchedule.repeatMode.displayName.lowercased()).")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No upcoming press")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Create a schedule below. Failed one-time runs stay recoverable in the queue.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: 8)

            Label("Local time", systemImage: "clock")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
        .glassCard(raised: true)
    }

    private var mainWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            scheduleComposer
                .frame(minWidth: 348, maxWidth: .infinity)
            diagnostics
                .frame(width: 205)
        }
    }

    private var scheduleComposer: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEW SCHEDULE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text("When → Key → App")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(repeatMode.displayName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 10) {
                stepTitle(number: "1", title: "When", selected: true)

                DatePicker(
                    "Schedule date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .labelsHidden()
                .datePickerStyle(.graphical)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Theme.window.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.border)
                }

                HStack(alignment: .top, spacing: 6) {
                    timePicker("Hour", selection: $selectedHour, values: Array(0..<24))
                    timeColon
                    timePicker("Minute", selection: $selectedMinute, values: Array(0..<60))
                    timeColon
                    timePicker("Second", selection: $selectedSecond, values: Array(0..<60))
                }
                .onChange(of: selectedHour) { _, _ in syncTimeText() }
                .onChange(of: selectedMinute) { _, _ in syncTimeText() }
                .onChange(of: selectedSecond) { _, _ in syncTimeText() }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsManualTimeEntry.toggle()
                    }
                } label: {
                    Label(
                        "Type HH:MM:SS instead",
                        systemImage: showsManualTimeEntry ? "chevron.down" : "chevron.right"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 30)
                }
                .buttonStyle(.plain)

                if showsManualTimeEntry {
                    TextField("HH:MM:SS", text: $manualTimeText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .focused($manualTimeFocused)
                        .onSubmit { applyManualTime() }
                        .onChange(of: manualTimeFocused) { _, focused in
                            if !focused { applyManualTime() }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(Theme.surfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.borderStrong)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)

            Divider().overlay(Theme.border)

            compactSelectionRow(icon: "R", title: "Repeat") {
                Picker("Repeat", selection: $repeatMode) {
                    ForEach(ScheduleRepeatMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            insetDivider

            compactSelectionRow(icon: "2", title: "Key") {
                Picker("Key", selection: $selectedKey) {
                    ForEach(commonKeys) { key in
                        Text(key.name).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }

            insetDivider

            compactSelectionRow(icon: "3", title: "App") {
                Picker("App", selection: $selectedAppID) {
                    ForEach(appOptions) { app in
                        Text(app.name).tag(app.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if selectedAppID == otherAppOptionID {
                insetDivider
                TextField("Exact app name", text: $customAppName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 42)
            }
        }
        .glassCard()
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RELIABILITY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Theme.textMuted)
                    Text("Diagnostics")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 0) {
                diagnosticRow(
                    icon: "accessibility",
                    title: "Permissions",
                    detail: permissionState.canSendKeys
                        ? "Accessibility + PostEvent"
                        : permissionState.missingNames.joined(separator: " + ") + " required",
                    healthy: permissionState.canSendKeys,
                    actionTitle: permissionState.canSendKeys ? nil : "Grant access",
                    action: requestPermissions
                )
                Divider().overlay(Theme.border).padding(.horizontal, 10)
                diagnosticRow(
                    icon: "externaldrive",
                    title: "Stable install",
                    detail: stableInstallState.detail,
                    healthy: stableInstallState.isReady,
                    actionTitle: stableInstallState.isReady ? nil : "Install / update",
                    action: installStableCopy
                )
                Divider().overlay(Theme.border).padding(.horizontal, 10)
                diagnosticRow(
                    icon: "timer",
                    title: "Scheduler",
                    detail: schedulerHealth.summary,
                    healthy: schedulerHealth.isHealthy,
                    actionTitle: schedulerHealth.problems.isEmpty ? nil : "Repair",
                    action: repairScheduler
                )
            }
            .background(Theme.window.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border)
            }

            lastRunCard

            Spacer(minLength: 0)

            Text("Creates a recoverable schedule. A failed one-time press stays in the queue for Retry.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(action: addSchedule) {
                Text("Add Schedule")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accentInk)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.16), radius: 18)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(14)
        .glassCard()
    }

    @ViewBuilder
    private var lastRunCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("LAST RUN")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                if let lastRun {
                    Text(lastRun.status.displayName.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(runColor(lastRun.status))
                }
            }

            if let lastRun {
                Text(lastRun.recordedAt.formatted(date: .abbreviated, time: .standard))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                Text(lastRun.message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
            } else {
                Text("No delivery recorded yet")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(11)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border)
        }
    }

    private var scheduleQueue: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Schedule queue")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(activeSchedules.count) active")
                    .font(.system(size: 9, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    refreshApplications()
                    refreshState(full: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Refresh apps and scheduler status")
            }

            if sortedSchedules.isEmpty {
                Text("No schedules yet. Your first one will appear here with its exact next run and delivery status.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 245), spacing: 9)],
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(sortedSchedules) { schedule in
                        scheduleCard(schedule)
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    private func scheduleCard(_ schedule: TimedKeySchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(scheduleTitle(schedule))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Text(schedule.repeatMode == .once ? "ONCE" : "REPEAT")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(schedule.isEnabled ? Theme.accent : Theme.textMuted)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((schedule.isEnabled ? Theme.accent : Theme.textMuted).opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Text("\(schedule.keyName) → \(schedule.appName)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 5)

                Toggle(
                    "",
                    isOn: Binding(
                        get: { schedule.isEnabled },
                        set: { setScheduleEnabled(schedule.id, enabled: $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

                Divider().frame(height: 28).overlay(Theme.border)

                Button {
                    deleteSchedule(schedule.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textMuted)
                .help("Delete this schedule")
            }

            if let lastRun = schedule.lastRun,
               lastRun.status != .succeeded {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(runColor(lastRun.status))
                    Text(lastRun.message)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    if schedule.repeatMode == .once {
                        Button("Retry") { retrySchedule(schedule.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(Theme.warning)
                    }
                }
            }
        }
        .padding(11)
        .background(schedule.isEnabled ? Theme.surfaceRaised : Theme.window.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(schedule.isEnabled ? Theme.borderStrong : Theme.border)
        }
    }

    private var statusMessage: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(messageTone.color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private func stepTitle(number: String, title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(selected ? Theme.accentInk : Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(selected ? Theme.accent : Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func timePicker(
        _ label: String,
        selection: Binding<Int>,
        values: [Int]
    ) -> some View {
        VStack(spacing: 4) {
            Picker(label, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.borderStrong)
            }
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
    }

    private var timeColon: some View {
        Text(":")
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .padding(.top, 4)
    }

    private func compactSelectionRow<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Text(icon)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20, height: 20)
                .background(Theme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.borderStrong)
                }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var insetDivider: some View {
        Divider().overlay(Theme.border).padding(.leading, 46)
    }

    private func diagnosticRow(
        icon: String,
        title: String,
        detail: String,
        healthy: Bool,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundStyle(healthy ? Theme.success : Theme.warning)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(healthy ? "PASS" : "CHECK")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(healthy ? Theme.success : Theme.warning)
            }
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.warning)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
    }

    private func refreshApplications() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }

        var seen = Set<String>()
        var values: [TargetApplicationOption] = []
        for app in running {
            guard let name = app.localizedName else { continue }
            let id = app.bundleIdentifier ?? app.bundleURL?.path ?? name
            guard seen.insert(id).inserted else { continue }
            values.append(
                TargetApplicationOption(
                    id: id,
                    name: name,
                    bundleIdentifier: app.bundleIdentifier,
                    appURLPath: app.bundleURL?.path
                )
            )
        }
        values.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if !values.contains(where: { $0.name == "ChatGPT" }),
           let chatURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") {
            values.insert(
                TargetApplicationOption(
                    id: "com.openai.chat",
                    name: "ChatGPT",
                    bundleIdentifier: "com.openai.chat",
                    appURLPath: chatURL.path
                ),
                at: 0
            )
        }
        values.append(.other)
        appOptions = values

        if selectedAppID == otherAppOptionID,
           let chatGPT = values.first(where: { $0.name == "ChatGPT" }) {
            selectedAppID = chatGPT.id
        } else if !values.contains(where: { $0.id == selectedAppID }) {
            selectedAppID = values.first?.id ?? otherAppOptionID
        }
    }

    private func loadAndRepairSchedules() {
        schedules = ScheduleStore.load()
        let problems = LaunchAgentManager.repairAndReconcile(
            &schedules,
            appBundleURL: StableInstallManager.executionURL()
        )
        if let problem = problems.first {
            show(problem, tone: .warning)
        }
    }

    private func refreshState(full: Bool) {
        let saved = ScheduleStore.load()
        if saved != schedules { schedules = saved }
        permissionState = KeyEventSender.currentPermissionState()
        stableInstallState = StableInstallManager.state()
        lastRun = ScheduleStore.lastRun()
        if full {
            schedulerHealth = LaunchAgentManager.health(
                for: schedules,
                appBundleURL: StableInstallManager.executionURL()
            )
        }
    }

    private func requestPermissions() {
        permissionState = KeyEventSender.requestRequiredPermissions()
        if permissionState.canSendKeys {
            show("Accessibility and PostEvent access are ready.", tone: .success)
        } else {
            show(
                "Finish granting \(permissionState.missingNames.joined(separator: " and ")) access in System Settings, then return here.",
                tone: .warning
            )
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func installStableCopy() {
        switch StableInstallManager.installCurrentBuild() {
        case .success(let url):
            stableInstallState = .ready(url)
            show("Stable copy installed at \(url.path).", tone: .success)
            repairScheduler()
        case .failure(let error):
            stableInstallState = .invalid(error.localizedDescription)
            show("Stable install failed: \(error.localizedDescription)", tone: .error)
        }
    }

    private func repairScheduler() {
        stableInstallState = StableInstallManager.state()
        let problems = LaunchAgentManager.repairAndReconcile(
            &schedules,
            appBundleURL: StableInstallManager.executionURL()
        )
        schedulerHealth = LaunchAgentManager.health(
            for: schedules,
            appBundleURL: StableInstallManager.executionURL()
        )
        if let first = problems.first {
            show(first, tone: .error)
        } else {
            show("Scheduler registration is consistent with the saved queue.", tone: .success)
        }
    }

    private func addSchedule() {
        guard let fireDate = composedFireDate() else {
            show("Enter a valid time from 00:00:00 through 23:59:59.", tone: .error)
            return
        }
        guard !resolvedAppName.isEmpty else {
            show("Choose an app or enter its exact name.", tone: .error)
            return
        }
        guard repeatMode != .once || fireDate > Date() else {
            show("A one-time schedule must be in the future.", tone: .error)
            return
        }

        permissionState = KeyEventSender.requestRequiredPermissions()

        let stableURL: URL
        if let existing = StableInstallManager.executionURL() {
            stableURL = existing
        } else {
            switch StableInstallManager.installCurrentBuild() {
            case .success(let url): stableURL = url
            case .failure(let error):
                show("Could not create a stable app copy: \(error.localizedDescription)", tone: .error)
                return
            }
        }

        let option = selectedAppID == otherAppOptionID ? nil : selectedApp
        let schedule = TimedKeySchedule(
            fireDate: fireDate,
            keyName: selectedKey.name,
            keyCode: UInt16(selectedKey.code),
            appName: resolvedAppName,
            appBundleIdentifier: option?.bundleIdentifier,
            appURLPath: option?.appURLPath,
            repeatMode: repeatMode
        )

        let previous = schedules
        var updated = schedules
        updated.append(schedule)
        guard ScheduleStore.save(updated) else {
            show("The schedule could not be saved, so no launch agent was created.", tone: .error)
            return
        }

        let installation = LaunchAgentManager.install(schedule, appBundleURL: stableURL)
        guard installation.succeeded else {
            _ = ScheduleStore.save(previous)
            _ = LaunchAgentManager.uninstall(scheduleID: schedule.id)
            show("Could not register the schedule: \(installation.output)", tone: .error)
            return
        }

        schedules = updated
        refreshState(full: true)
        if permissionState.canSendKeys {
            show("Schedule added and verified with launchd.", tone: .success)
        } else {
            show(
                "Schedule added, but delivery is blocked until \(permissionState.missingNames.joined(separator: " and ")) access is granted.",
                tone: .warning
            )
        }
    }

    private func setScheduleEnabled(_ id: UUID, enabled: Bool) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        let previous = schedules[index]
        var candidate = schedules[index]

        if enabled {
            if candidate.repeatMode == .once, candidate.fireDate <= Date() {
                show("Use Retry to give this completed or missed one-time schedule a new time.", tone: .warning)
                return
            }
            guard let appURL = StableInstallManager.executionURL() else {
                show("Install the stable copy before enabling schedules.", tone: .error)
                return
            }
            candidate.isEnabled = true
            schedules[index] = candidate
            guard ScheduleStore.save(schedules) else {
                schedules[index] = previous
                show("The schedule could not be saved, so it was not enabled.", tone: .error)
                return
            }
            let result = LaunchAgentManager.install(candidate, appBundleURL: appURL)
            guard result.succeeded else {
                schedules[index] = previous
                _ = ScheduleStore.save(schedules)
                _ = LaunchAgentManager.uninstall(scheduleID: candidate.id)
                show("Could not enable the schedule: \(result.output)", tone: .error)
                return
            }
        } else {
            candidate.isEnabled = false
            schedules[index] = candidate
            guard ScheduleStore.save(schedules) else {
                schedules[index] = previous
                show("The schedule could not be saved, so it was not paused.", tone: .error)
                return
            }
            let result = LaunchAgentManager.uninstall(scheduleID: candidate.id)
            guard result.succeeded else {
                schedules[index] = previous
                _ = ScheduleStore.save(schedules)
                show("Could not pause the schedule: \(result.output)", tone: .error)
                return
            }
        }
        show(enabled ? "Schedule enabled and verified." : "Schedule paused and removed from launchd.", tone: .success)
        refreshState(full: true)
    }

    private func deleteSchedule(_ id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        let result = LaunchAgentManager.uninstall(scheduleID: id)
        guard result.succeeded else {
            show("Could not delete the launch agent: \(result.output)", tone: .error)
            return
        }
        schedules.removeAll { $0.id == id }
        guard ScheduleStore.save(schedules) else {
            schedules.append(schedule)
            _ = ScheduleStore.save(schedules)
            if schedule.isEnabled, let appURL = StableInstallManager.executionURL() {
                _ = LaunchAgentManager.install(schedule, appBundleURL: appURL)
            }
            show("The launch agent was removed, but the saved queue could not be updated.", tone: .error)
            return
        }
        show("Schedule deleted from launchd and the saved queue.", tone: .success)
        refreshState(full: true)
    }

    private func retrySchedule(_ id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }),
              let appURL = StableInstallManager.executionURL()
        else {
            show("Install the stable copy before retrying.", tone: .error)
            return
        }
        let previous = schedules[index]
        schedules[index].fireDate = Date().addingTimeInterval(10)
        schedules[index].isEnabled = true
        schedules[index].lastRun = nil
        guard ScheduleStore.save(schedules) else {
            schedules[index] = previous
            show("Retry could not be saved, so it was not armed.", tone: .error)
            return
        }
        let result = LaunchAgentManager.install(schedules[index], appBundleURL: appURL)
        guard result.succeeded else {
            schedules[index] = previous
            _ = ScheduleStore.save(schedules)
            _ = LaunchAgentManager.uninstall(scheduleID: id)
            show("Retry registration failed: \(result.output)", tone: .error)
            return
        }
        show("Retry scheduled for 10 seconds from now.", tone: .success)
        refreshState(full: true)
    }

    private func composedFireDate() -> Date? {
        if showsManualTimeEntry, !applyManualTime(showError: false) {
            return nil
        }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: selectedDate)
        components.hour = selectedHour
        components.minute = selectedMinute
        components.second = selectedSecond
        return Calendar.current.date(from: components)
    }

    @discardableResult
    private func applyManualTime(showError: Bool = true) -> Bool {
        let parts = manualTimeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              let second = Int(parts[2]),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second)
        else {
            if showError {
                show("Use HH:MM:SS, for example 09:30:05.", tone: .error)
            }
            return false
        }
        selectedHour = hour
        selectedMinute = minute
        selectedSecond = second
        syncTimeText()
        return true
    }

    private func syncTimeText() {
        guard !manualTimeFocused else { return }
        manualTimeText = String(
            format: "%02d:%02d:%02d",
            selectedHour,
            selectedMinute,
            selectedSecond
        )
    }

    private func show(_ text: String, tone: MessageTone) {
        message = text
        messageTone = tone
    }

    private func scheduleTitle(_ schedule: TimedKeySchedule) -> String {
        switch schedule.repeatMode {
        case .once:
            schedule.fireDate.formatted(date: .abbreviated, time: .standard)
        case .daily, .weekdays, .weekends:
            "\(schedule.repeatMode.displayName) · \(timeWithSeconds(schedule.fireDate))"
        case .weekly:
            "\(schedule.fireDate.formatted(.dateTime.weekday(.wide))) · \(timeWithSeconds(schedule.fireDate))"
        }
    }

    private func summaryDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func timeWithSeconds(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute().second())
    }

    private func runColor(_ status: ScheduleRunStatus) -> Color {
        switch status {
        case .succeeded: Theme.success
        case .deferred, .missed: Theme.warning
        case .failed: Theme.danger
        }
    }
}

private struct GridBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 56
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color.white.opacity(0.018)), lineWidth: 1)
        }
        .overlay {
            RadialGradient(
                colors: [Color.white.opacity(0.032), .clear],
                center: UnitPoint(x: 0.28, y: 0.24),
                startRadius: 10,
                endRadius: 300
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
