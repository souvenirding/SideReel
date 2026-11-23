import AppKit
import Combine
import ServiceManagement
import SlideshowKit
import SwiftUI

struct PanelView: View {
    @AppStorage(ConfigKeys.folderPath) private var folderPath = ""
    @AppStorage(ConfigKeys.screenNames) private var screenNamesRaw = ""
    @AppStorage(ConfigKeys.interval) private var interval = 10.0
    @AppStorage(ConfigKeys.playbackMode) private var playbackMode = "slideshow"
    @AppStorage(ConfigKeys.driftSpeed) private var driftSpeed = 20.0
    @AppStorage(ConfigKeys.tileCount) private var tileCount = 13
    @AppStorage(ConfigKeys.shuffle) private var shuffle = true
    @AppStorage(ConfigKeys.idleEnabled) private var idleEnabled = false
    @AppStorage(ConfigKeys.idleMinutes) private var idleMinutes = 5
    @AppStorage(ConfigKeys.keepAwake) private var keepAwake = true
    @AppStorage(ConfigKeys.lockOnExit) private var lockOnExit = false
    @AppStorage(ConfigKeys.scheduleStart) private var scheduleStart = 0
    @AppStorage(ConfigKeys.scheduleEnd) private var scheduleEnd = TimeSchedule.dayEnd

    @EnvironmentObject private var slideshow: SlideshowController
    @StateObject private var counter = FolderImageCounter()
    @State private var displays: [DisplayInfo] = []
    @State private var errorMessage: String?
    @State private var quitHovering = false
    @State private var launchAtLogin = false
    @State private var launchNeedsApproval = false
    @State private var scheduleActive = true

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            GroupBox("图片") {
                Button(action: chooseFolder) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folderPath.isEmpty ? "选择图片文件夹…" : folderName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let count = counter.count {
                                Text("\(count) 张图片")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }

            GroupBox("显示器") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displays) { display in
                        Toggle(display.label, isOn: screenBinding(for: display.name))
                            .toggleStyle(.checkbox)
                    }
                    ForEach(disconnectedNames, id: \.self) { name in
                        Toggle("\(name)（未连接）", isOn: screenBinding(for: name))
                            .toggleStyle(.checkbox)
                    }
                    Text(selectionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            GroupBox("播放") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $playbackMode) {
                        Text("单图轮播").tag("slideshow")
                        Text("拼贴漂移").tag("collage")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Picker("", selection: $shuffle) {
                        Text("随机不重复").tag(true)
                        Text("按顺序").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if playbackMode == "collage" {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("漂移速度")
                            HStack(spacing: 8) {
                                Text("慢")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $driftSpeed, in: 5...80)
                                Text("快")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("同屏照片上限")
                            Spacer()
                            TextField("", value: $tileCount, format: .number)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $tileCount, in: 4...30)
                                .labelsHidden()
                            Text("张")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text("切换间隔")
                            Spacer()
                            TextField("", value: $interval, format: .number)
                                .frame(width: 48)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $interval, in: 1...3600)
                                .labelsHidden()
                            Text("秒")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("播放时防止息屏", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, on in
                            slideshow.setKeepAwake(on)
                        }

                    Toggle("退出播放时锁定屏幕", isOn: $lockOnExit)
                        .disabled(!coversAllScreens)
                        .help("退出播放后进入系统登录界面，锁定所有显示器")
                    if !coversAllScreens {
                        Text("需选择全部显示器才可开启")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .onChange(of: tileCount) { _, count in
                    tileCount = min(max(count, 4), 30)
                }
            }

            GroupBox("自动开始") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("开机时启动 SideReel", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in
                            guard on != (SMAppService.mainApp.status == .enabled) else { return }
                            setLaunchAtLogin(on)
                        }
                    if launchNeedsApproval {
                        Text("需在系统设置 › 通用 › 登录项中允许")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("闲置后自动开始", isOn: $idleEnabled)
                    if idleEnabled {
                        Picker("闲置时间", selection: $idleMinutes) {
                            ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { minute in
                                Text("\(minute) 分钟").tag(minute)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .onChange(of: idleEnabled) { appDelegate?.applyIdleMonitor() }
                .onChange(of: idleMinutes) { appDelegate?.applyIdleMonitor() }
            }

            GroupBox("生效时间") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("从")
                        DatePicker("", selection: timeBinding($scheduleStart), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("到")
                        DatePicker("", selection: timeBinding($scheduleEnd), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Spacer()
                    }
                    Text(scheduleHint)
                        .font(.caption)
                        .foregroundStyle(scheduleActive || slideshow.isRunning ? Color.secondary : Color.orange)
                }
                .padding(.vertical, 2)
                .onChange(of: scheduleStart) { _, start in
                    if start >= scheduleEnd {
                        scheduleEnd = min(start + 1, TimeSchedule.dayEnd)
                        if scheduleStart >= scheduleEnd { scheduleStart = scheduleEnd - 1 }
                    }
                    scheduleChanged()
                }
                .onChange(of: scheduleEnd) { _, end in
                    if end <= scheduleStart {
                        scheduleStart = max(end - 1, 0)
                        if scheduleEnd <= scheduleStart { scheduleEnd = scheduleStart + 1 }
                    }
                    scheduleChanged()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: togglePlayback) {
                Label(
                    slideshow.isRunning ? "停止播放" : "开始播放",
                    systemImage: slideshow.isRunning ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(slideshow.isRunning ? .red : .accentColor)
            .controlSize(.large)
            .disabled((folderPath.isEmpty || !scheduleActive) && !slideshow.isRunning)

            Text("播放时点击任意播放屏幕或按 Esc 退出")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()

            Button(action: { NSApp.terminate(nil) }) {
                Label("退出 SideReel", systemImage: "power")
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(quitHovering ? Color.red : Color.secondary)
            .onHover { quitHovering = $0 }
            .help("退出应用程序（⌘Q）")
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            displays = ScreenUtils.displays()
            counter.setFolder(folderPath)
            refreshLaunchAtLogin()
            scheduleActive = TimeSchedule.isActive()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            scheduleActive = TimeSchedule.isActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = ScreenUtils.displays()
        }
        .onChange(of: folderPath) { _, newPath in
            counter.setFolder(newPath)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("SideReel")
                    .font(.headline)
                Text("外接屏轮播相框")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if slideshow.isRunning {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 7, height: 7)
                    Text("播放中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var folderName: String {
        URL(fileURLWithPath: folderPath).lastPathComponent
    }

    private var selectedNames: Set<String> {
        Set(screenNamesRaw.split(separator: "\n").map(String.init))
    }

    private var disconnectedNames: [String] {
        selectedNames.subtracting(displays.map { $0.name }).sorted()
    }

    private var selectionHint: String {
        selectedNames.isEmpty
            ? "未选择时自动使用第一个外接显示器"
            : "已选 \(selectedNames.count) 台显示器，同时播放"
    }

    private var coversAllScreens: Bool {
        ScreenUtils.coversAllScreens(
            ScreenUtils.selectedScreens(names: Array(selectedNames))
        )
    }

    private var scheduleHint: String {
        if scheduleStart == 0 && scheduleEnd == TimeSchedule.dayEnd { return "全天生效" }
        if !scheduleActive { return "当前不在生效时间段内" }
        return "仅此时间段内播放，到点自动停止"
    }

    private func scheduleChanged() {
        scheduleActive = TimeSchedule.isActive()
        appDelegate?.applySchedule()
    }

    private func timeBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60,
                    minute: minutes.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    private func screenBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selectedNames.contains(name) },
            set: { isOn in
                var names = selectedNames
                if isOn { names.insert(name) } else { names.remove(name) }
                screenNamesRaw = names.sorted().joined(separator: "\n")
            }
        )
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "设置开机启动失败：\(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchNeedsApproval = status == .requiresApproval
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "选择要轮播的图片文件夹"
        panel.prompt = "选择"
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            errorMessage = nil
        }
    }

    private func togglePlayback() {
        guard let appDelegate else { return }
        if slideshow.isRunning {
            appDelegate.stopSlideshow()
        } else {
            errorMessage = appDelegate.startSlideshow()
        }
    }
}