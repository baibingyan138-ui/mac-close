import AppKit
import SwiftUI

struct PowerState {
    enum SleepStatus {
        case enabled, disabled, unavailable
    }

    let sleepStatus: SleepStatus
    let onACPower: Bool
    let batteryPercent: Int?

    var sleepDisabled: Bool { sleepStatus == .enabled }

    static func read() -> PowerState {
        let settings = Shell.run("/usr/bin/pmset", ["-g"])
        let battery = Shell.run("/usr/bin/pmset", ["-g", "batt"])
        let percent = battery.output.range(of: #"\d+(?=%)"#, options: .regularExpression)
            .flatMap { Int(battery.output[$0]) }

        return PowerState(
            sleepStatus: sleepStatus(from: settings),
            onACPower: battery.output.contains("AC Power"),
            batteryPercent: percent
        )
    }

    static func sleepStatus(from result: CommandResult) -> SleepStatus {
        guard result.status == 0 else { return .unavailable }
        guard let line = result.output.split(separator: "\n").first(where: { $0.contains("SleepDisabled") }),
              let value = line.split(whereSeparator: { $0.isWhitespace }).last else {
            return .unavailable
        }
        return value == "1" ? .enabled : .disabled
    }

    static func selfTest() -> Bool {
        sleepStatus(from: CommandResult(output: " SleepDisabled\t\t1\n", status: 0)) == .enabled
            && sleepStatus(from: CommandResult(output: " SleepDisabled 0\n", status: 0)) == .disabled
            && sleepStatus(from: CommandResult(output: "error", status: 1)) == .unavailable
    }
}

struct CommandResult {
    let output: String
    let status: Int32
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
        } catch {
            return CommandResult(output: error.localizedDescription, status: -1)
        }
    }
}

enum Launcher {
    static func start(hours: Int, unlimited: Bool, onACPower: Bool) throws {
        let scriptName = onACPower ? "合盖持续运行.command" : "合盖持续运行_电池临时.command"
        guard let resources = Bundle.main.resourceURL else { throw AppError("应用资源不可用。") }

        let script = resources.appendingPathComponent("Scripts/\(scriptName)")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            throw AppError("找不到合盖运行脚本，请重新安装应用。")
        }

        let wrapper = FileManager.default.temporaryDirectory
            .appendingPathComponent("合盖运行-\(UUID().uuidString).command")
        let command = """
        #!/bin/zsh
        /bin/rm -f -- "$0"
        exec \(shellQuote(script.path)) \(unlimited ? "unlimited" : String(hours))
        """

        try command.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
        guard NSWorkspace.shared.open(wrapper) else {
            try? FileManager.default.removeItem(at: wrapper)
            throw AppError("无法打开终端。")
        }
    }

    static func restoreSleep() -> CommandResult {
        Shell.run("/usr/bin/osascript", [
            "-e",
            "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"
        ])
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state = PowerState.read()
    @Published var hours = 1
    @Published var unlimited = false
    @Published var busy = false
    @Published var notice: String?
    @Published var errorMessage: String?

    var maximumHours: Int { state.onACPower ? 24 : 4 }

    func refresh() {
        state = PowerState.read()
        hours = min(hours, maximumHours)
    }

    func start() {
        do {
            try Launcher.start(hours: hours, unlimited: unlimited, onACPower: state.onACPower)
            notice = "终端已打开，请完成管理员授权。"
            Task {
                for _ in 0..<60 where !state.sleepDisabled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    refresh()
                }
                if state.sleepDisabled { notice = nil }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restoreSleep() {
        busy = true
        notice = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Launcher.restoreSleep()
            DispatchQueue.main.async {
                self.busy = false
                if result.status == 0 {
                    self.notice = "已恢复正常休眠。"
                    self.refresh()
                } else if !result.output.contains("User canceled") && result.status != -128 {
                    self.errorMessage = "未能恢复休眠，请确认管理员密码后重试。"
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 18) {
                statusPanel
                if model.state.sleepDisabled { restorePanel } else { startPanel }
                safetyNote
            }
            .padding(24)
        }
        .frame(width: 460, height: 430)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .onReceive(timer) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer.and.arrow.down")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("合盖运行控制").font(.title3.weight(.semibold))
                Text("定时保持 MacBook 运行").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭应用")
            Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新状态")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var statusPanel: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(model.state.sleepDisabled ? Color.green.opacity(0.14) : Color.gray.opacity(0.12))
                Image(systemName: model.state.sleepDisabled ? "checkmark.circle.fill" : "moon.zzz.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(model.state.sleepDisabled ? .green : .secondary)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline)
                Label(powerDescription, systemImage: powerSymbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var startPanel: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("运行时长").font(.headline)
                    Text(durationLimitDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.unlimited {
                    Label("不限时", systemImage: "infinity")
                        .font(.body.weight(.medium))
                } else {
                    Stepper(value: $model.hours, in: 1...model.maximumHours) {
                        Text("\(model.hours) 小时")
                            .font(.body.monospacedDigit().weight(.medium))
                            .frame(minWidth: 58, alignment: .trailing)
                    }
                }
            }
            Toggle("不限时", isOn: $model.unlimited)
                .toggleStyle(.switch)
            Button(action: model.start) {
                Label(model.unlimited ? "开启不限时运行" : "开启 \(model.hours) 小时", systemImage: "power")
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.state.sleepStatus == .unavailable)
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var restorePanel: some View {
        VStack(spacing: 12) {
            Text("恢复后，MacBook 合盖将按系统设置进入休眠。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: model.restoreSleep) {
                Label(model.busy ? "正在恢复…" : "恢复正常休眠", systemImage: "power.circle")
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(model.busy)
            if let notice = model.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var safetyNote: some View {
        Label {
            Text("合盖后自动锁屏并进入低电量模式。保持通风，勿放入包中、床上或沙发上。")
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var powerDescription: String {
        if model.state.sleepStatus == .unavailable { return "无法读取系统状态 · 请刷新重试" }
        if model.state.onACPower { return "已连接电源 · 断电自动恢复" }
        if let percent = model.state.batteryPercent { return "电池 \(percent)% · 低于 10% 自动恢复" }
        return "电池供电 · 低电量自动恢复"
    }

    private var durationLimitDescription: String {
        if model.unlimited {
            return model.state.onACPower ? "持续到断电或手动恢复" : "持续到电量 10% 或手动恢复"
        }
        return model.state.onACPower ? "接电模式最多 24 小时" : "电池模式最多 4 小时"
    }

    private var powerSymbol: String {
        if model.state.onACPower { return "powerplug.fill" }
        switch model.state.batteryPercent ?? 0 {
        case 76...: return "battery.100"
        case 51...: return "battery.75"
        case 26...: return "battery.50"
        case 1...: return "battery.25"
        default: return "battery.0"
        }
    }

    private var statusTitle: String {
        switch model.state.sleepStatus {
        case .enabled: return "合盖运行已开启"
        case .disabled: return "当前为正常休眠"
        case .unavailable: return "休眠状态不可用"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ClamshellControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            guard PowerState.selfTest() else { exit(1) }
            print("界面状态自检通过")
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
