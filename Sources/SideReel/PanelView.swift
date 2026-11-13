import AppKit
import SlideshowKit
import SwiftUI

struct PanelView: View {
    @AppStorage(ConfigKeys.folderPath) private var folderPath = ""
    @AppStorage(ConfigKeys.screenNames) private var screenNamesRaw = ""
    @AppStorage(ConfigKeys.interval) private var interval = 10.0
    @AppStorage(ConfigKeys.shuffle) private var shuffle = true
    @AppStorage(ConfigKeys.idleEnabled) private var idleEnabled = false
    @AppStorage(ConfigKeys.idleMinutes) private var idleMinutes = 5
    @AppStorage(ConfigKeys.keepAwake) private var keepAwake = true

    @EnvironmentObject private var slideshow: SlideshowController
    @StateObject private var counter = FolderImageCounter()
    @State private var displays: [DisplayInfo] = []
    @State private var errorMessage: String?
    @State private var quitHovering = false

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
                    Picker("", selection: $shuffle) {
                        Text("随机不重复").tag(true)
                        Text("按顺序").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

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

                    Toggle("播放时防止息屏", isOn: $keepAwake)
                        .onChange(of: keepAwake) { _, on in
                            slideshow.setKeepAwake(on)
                        }
                }
                .padding(.vertical, 2)
            }

            GroupBox("自动开始") {
                VStack(alignment: .leading, spacing: 8) {
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
            .disabled(folderPath.isEmpty && !slideshow.isRunning)

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