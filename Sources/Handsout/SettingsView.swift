import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 快捷键录制控件

final class RecorderView: NSView {
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0
    var isRecording = false
    var onCapture: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            needsDisplay = true
            onCancel?()
            return
        }
        let mods = KeyCodes.carbonModifiers(event.modifierFlags)
        guard mods != 0 else { NSSound.beep(); return } // 必须有修饰键，避免单键误触
        onCapture?(UInt32(event.keyCode), mods)
        isRecording = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isRecording {
            NSColor.controlAccentColor.setFill()
            path.fill()
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let text = isRecording ? "按下新快捷键…" : KeyCodes.display(keyCode: keyCode, modifiers: modifiers)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: isRecording ? NSColor.white : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attrs)
    }
}

struct KeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { kc, mods in onCapture(kc, mods) }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.keyCode = keyCode
        nsView.modifiers = modifiers
        nsView.needsDisplay = true
    }
}

// MARK: - 设置主界面

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var notice: String?
    @State private var trusted = Accessibility.isTrusted()
    @State private var showInstalled = false
    @State private var showSystemActions = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.items) { item in
                            ItemRow(item: item, notice: $notice)
                            Divider().padding(.leading, 52)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180)
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 520)
        .sheet(isPresented: $showInstalled) { InstalledAppsSheet() }
        .sheet(isPresented: $showSystemActions) { SystemActionsSheet() }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Text("Handsout")
                .font(.system(size: 15, weight: .semibold))
            Text("按住 ⌥ 显示面板，⌥+字母/数字 直接启动，再按一次收回")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showSystemActions = true
            } label: {
                Label("添加系统功能", systemImage: "gearshape")
            }
            Button {
                showInstalled = true
            } label: {
                Label("已安装应用", systemImage: "magnifyingglass")
            }
            Button {
                pickApp()
            } label: {
                Label("添加应用", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "command.square")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("还没有添加任何应用")
                .font(.system(size: 13))
            Text("点击右上角「添加应用」或「添加系统功能」，也可以从已安装列表里挑。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("系统功能包括：系统设置的各个面板（网络、蓝牙、声音…）、常用文件夹、系统自带应用。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 底部设置

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("长按 ⌥ 触发延迟")
                    .frame(width: 120, alignment: .leading)
                Slider(value: Binding(
                    get: { store.holdThreshold },
                    set: { store.holdThreshold = $0; store.save() }
                ), in: 0...1.2, step: 0.05)
                Text(store.holdThreshold < 0.02 ? "立即显示" : String(format: "%.2f 秒", store.holdThreshold))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("再按一次隐藏")
                    .frame(width: 120, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { store.toggleBack },
                    set: { store.toggleBack = $0; store.save() }
                ))
                .labelsHidden()
                Text("（再按同一个键：已在前台则隐藏它，并切回上一个应用）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("开机启动")
                    .frame(width: 120, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { newValue in
                        store.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))
                .labelsHidden()
                Text("（建议把 Handsout.app 放到 /Applications 后再开启）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("辅助功能权限")
                    .frame(width: 120, alignment: .leading)
                HStack(spacing: 6) {
                    Circle()
                        .fill(trusted ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(trusted ? "已授权，长按 ⌥ 生效" : "未授权，长按 ⌥ 无法监听全局按键")
                        .font(.system(size: 11))
                        .foregroundStyle(trusted ? Color.primary : Color.orange)
                }
                if !trusted {
                    Button("请求权限") { Accessibility.request() }
                    Button("打开系统设置") { Accessibility.openSettingsPane() }
                }
                Spacer()
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    // MARK: 行为

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择要用快捷键打开的应用"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if store.add(path: url.path) == nil {
                notice = "\(url.lastPathComponent) 已添加过或不是应用"
            }
        }
    }

    private func applyLaunchAtLogin(_ on: Bool) {
        store.save()
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            notice = "设置登录项失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 单行

private struct ItemRow: View {
    @EnvironmentObject var store: AppStore
    let item: LaunchItem
    @Binding var notice: String?

    var body: some View {
        HStack(spacing: 12) {
            ItemIconView(item: item, size: 32)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13))
                    if item.kind != .app {
                        Text(item.kind.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    if !item.exists {
                        Text("路径失效").font(.system(size: 10)).foregroundStyle(.red)
                    }
                }
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            KeyRecorder(keyCode: binding(\.keyCode), modifiers: binding(\.modifiers)) { kc, mods in
                assign(keyCode: kc, modifiers: mods)
            }
            .frame(width: 150, height: 26)
            Button {
                Launcher.launch(item)
            } label: {
                Image(systemName: "play.fill")
            }
            .help("启动 \(item.name)")
            Button(role: .destructive) {
                store.remove(id: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .help("移除")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 把 item 的某个属性包装成 Binding，交给录制控件
    private func binding(_ path: WritableKeyPath<LaunchItem, UInt32>) -> Binding<UInt32> {
        Binding(
            get: { item[keyPath: path] },
            set: { newValue in
                var updated = item
                updated[keyPath: path] = newValue
                store.update(updated)
            }
        )
    }

    private func assign(keyCode: UInt32, modifiers: UInt32) {
        if let conflict = store.items.first(where: {
            $0.id != item.id && $0.keyCode == keyCode && $0.modifiers == modifiers
        }) {
            var cleared = conflict
            cleared.keyCode = 0
            cleared.modifiers = 0
            store.update(cleared)
            notice = "已接管 \(conflict.name) 的 \(KeyCodes.display(keyCode: keyCode, modifiers: modifiers))"
        } else {
            notice = nil
        }
        var updated = item
        updated.keyCode = keyCode
        updated.modifiers = modifiers
        store.update(updated)
    }
}

// MARK: - 系统功能列表

private struct SystemActionsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var added: String?

    private var groups: [SystemGroup] { SystemCatalog.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("系统功能").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding(12)

            TextField("搜索，比如「网络」「蓝牙」「下载」", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.actions) { action in
                                SystemActionRow(action: action, highlight: added == action.id) {
                                    if store.add(action) != nil { added = action.id }
                                }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: group.symbol)
                                    .foregroundStyle(.secondary)
                                Text(group.title)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            if let added, let action = SystemCatalog.action(id: added) {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("已添加「\(action.name)」，快捷键 \(store.items.first { $0.path == action.target }?.hotkeyDisplay ?? "未分配")")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(10)
            }
        }
        .frame(width: 560, height: 600)
    }
}

private struct SystemActionRow: View {
    @EnvironmentObject var store: AppStore
    let action: SystemAction
    var highlight: Bool = false
    var onAdd: () -> Void = {}

    private var existing: LaunchItem? {
        store.items.first { $0.kind == action.kind && $0.path == action.target }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.name).font(.system(size: 13))
                Text(action.kind == .url
                     ? "系统设置面板"
                     : (action.target as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let item = existing {
                Text(item.hotkeyDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Button("添加", action: onAdd)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(highlight ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { if existing == nil { onAdd() } }
        Divider().padding(.leading, 46)
    }
}

// MARK: - 已安装应用列表

private struct InstalledAppsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps = AppScanner.installedApps()

    private var filtered: [ScannedApp] {
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("已安装应用").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("完成") { dismiss() }
            }
            .padding(12)

            TextField("搜索", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { app in
                        HStack(spacing: 10) {
                            AppIconView(path: app.path, size: 24).frame(width: 24, height: 24)
                            Text(app.name)
                            Spacer()
                            if let item = store.items.first(where: { $0.path == app.path }) {
                                Text(item.hotkeyDisplay)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("添加") { _ = store.add(path: app.path) }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .frame(width: 520, height: 560)
    }
}
