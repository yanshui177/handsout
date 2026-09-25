import AppKit
import Carbon.HIToolbox
import Foundation

/// 快捷键目标的类型
enum ItemKind: String, Codable, CaseIterable {
    /// 一个 .app
    case app
    /// 一个 URL scheme（比如系统设置面板）
    case url
    /// 一个文件夹（用访达打开）
    case folder

    var label: String {
        switch self {
        case .app: return "应用"
        case .url: return "系统面板"
        case .folder: return "文件夹"
        }
    }
}

/// 一个被快捷键绑定的目标（应用 / 系统面板 / 文件夹）
struct LaunchItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// .app / .folder -> 文件系统路径；.url -> 完整的 URL scheme
    var path: String
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0
    var kind: ItemKind = .app
    /// SF Symbol 名；有值时用符号图标，否则用文件/应用图标
    var symbol: String? = nil

    var isBound: Bool { keyCode != 0 && modifiers != 0 }
    var hotkeyDisplay: String { KeyCodes.display(keyCode: keyCode, modifiers: modifiers) }

    var exists: Bool {
        switch kind {
        case .app, .folder: return FileManager.default.fileExists(atPath: path)
        case .url: return URL(string: path) != nil
        }
    }

    /// 设置列表里第二行显示的说明
    var detail: String {
        switch kind {
        case .url: return "\(kind.label) · \(path.replacingOccurrences(of: "x-apple.systempreferences:", with: ""))"
        case .app, .folder: return path
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, keyCode, modifiers, kind, symbol
    }

    init(id: UUID = UUID(),
         name: String,
         path: String,
         keyCode: UInt32 = 0,
         modifiers: UInt32 = 0,
         kind: ItemKind = .app,
         symbol: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.kind = kind
        self.symbol = symbol
    }

    /// 1.0.x 的配置里没有 kind / symbol，用默认值兜底，别把老配置读崩
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        keyCode = try c.decodeIfPresent(UInt32.self, forKey: .keyCode) ?? 0
        modifiers = try c.decodeIfPresent(UInt32.self, forKey: .modifiers) ?? 0
        kind = try c.decodeIfPresent(ItemKind.self, forKey: .kind) ?? .app
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
    }
}

private final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    func image(for path: String) -> NSImage? { cache.object(forKey: path as NSString) }
    func set(_ img: NSImage, for path: String) { cache.setObject(img, forKey: path as NSString) }
}

// MARK: - 配置持久化

struct Config: Codable {
    var items: [LaunchItem] = []
    var holdThreshold: Double = 0.35
    var launchAtLogin: Bool = false
    /// 目标已在前台时，再按一次是否隐藏它并切回上一个应用
    var toggleBack: Bool = true

    enum CodingKeys: String, CodingKey {
        case items, holdThreshold, launchAtLogin, toggleBack
    }

    init(items: [LaunchItem] = [],
         holdThreshold: Double = 0.35,
         launchAtLogin: Bool = false,
         toggleBack: Bool = true) {
        self.items = items
        self.holdThreshold = holdThreshold
        self.launchAtLogin = launchAtLogin
        self.toggleBack = toggleBack
    }

    /// 旧版本配置没有 toggleBack 字段，用默认值兜底，别把用户配置读崩了
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([LaunchItem].self, forKey: .items) ?? []
        holdThreshold = try c.decodeIfPresent(Double.self, forKey: .holdThreshold) ?? 0.35
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        toggleBack = try c.decodeIfPresent(Bool.self, forKey: .toggleBack) ?? true
    }
}

final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var items: [LaunchItem] = []
    @Published var holdThreshold: Double = 0.35
    @Published var launchAtLogin: Bool = false
    @Published var toggleBack: Bool = true

    private var configURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Handsout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    private init() {}

    func load() {
        guard let data = try? Data(contentsOf: configURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return }
        let valid = cfg.items.filter { $0.exists }
        items = valid
        holdThreshold = cfg.holdThreshold
        launchAtLogin = cfg.launchAtLogin
        toggleBack = cfg.toggleBack
        if valid.count != cfg.items.count { save() }
    }

    func save() {
        let cfg = Config(items: items,
                         holdThreshold: holdThreshold,
                         launchAtLogin: launchAtLogin,
                         toggleBack: toggleBack)
        guard let data = try? JSONEncoder().encode(cfg) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    // MARK: 增删改

    @discardableResult
    func add(path: String) -> LaunchItem? {
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension == "app", FileManager.default.fileExists(atPath: path) else { return nil }
        if items.contains(where: { $0.path == path }) { return nil }

        let name = (url.deletingPathExtension().lastPathComponent)
        var item = LaunchItem(name: name, path: path)
        if let hot = nextAvailableHotKey(preferring: name) {
            item.keyCode = hot.keyCode
            item.modifiers = hot.modifiers
        }
        items.append(item)
        save()
        return item
    }

    /// 添加一个系统功能（系统设置面板 / 文件夹 / 系统应用）
    @discardableResult
    func add(_ action: SystemAction) -> LaunchItem? {
        if items.contains(where: { $0.kind == action.kind && $0.path == action.target }) { return nil }
        var item = action.makeItem()
        if let hot = nextAvailableHotKey(preferring: action.hint ?? action.name) {
            item.keyCode = hot.keyCode
            item.modifiers = hot.modifiers
        }
        items.append(item)
        save()
        return item
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func update(_ item: LaunchItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        save()
    }

    /// 指定快捷键是否已被占用
    func isOccupied(keyCode: UInt32, modifiers: UInt32, except id: UUID? = nil) -> Bool {
        items.contains { $0.id != id && $0.keyCode == keyCode && $0.modifiers == modifiers }
    }

    /// 自动分配下一个可用的 ⌥+字母/数字
    func nextAvailableHotKey(preferring name: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let mods = UInt32(optionKey)
        var candidates: [UInt32] = []
        if let first = name.uppercased().first, let kc = KeyCodes.keyCode(forCharacter: first) {
            candidates.append(kc)
        }
        candidates.append(contentsOf: KeyCodes.preferredOrder)
        for kc in candidates where !isOccupied(keyCode: kc, modifiers: mods) {
            return (kc, mods)
        }
        return nil
    }
}

// MARK: - 启动 / 激活应用

enum Launcher {
    /// 按类型分发：应用走"开关"逻辑，系统面板/文件夹走"打开并置前"
    static func toggle(_ item: LaunchItem) {
        switch item.kind {
        case .app: toggleApp(item)
        case .url: openURLItem(item)
        case .folder: toggleFolder(item)
        }
    }

    /// 打开一个 URL scheme（主要是系统设置面板）。
    /// 注意：目标应用已经在后台运行时，open() 只会切换面板、不会把它带到前台，
    /// 所以这里补一次 activate（先来一次快的，冷启动再来一次兜底）。
    private static func openURLItem(_ item: LaunchItem) {
        guard let url = URL(string: item.path) else {
            NSLog("[Handsout] 无效的 URL：\(item.path)")
            return
        }
        let ok = NSWorkspace.shared.open(url)
        NSLog("[Handsout] 打开 \(item.name)：\(item.path) -> \(ok)")

        guard let bid = hostBundleID(forScheme: url.scheme) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
                _ = activate(app)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
                  !app.isActive else { return }
            NSLog("[Handsout] \(item.name) 冷启动后仍未到前台，补一次 activate")
            _ = activate(app)
        }
    }

    /// 已知 scheme 对应的宿主 App；未知返回 nil（比如 https 交给默认浏览器）
    private static func hostBundleID(forScheme scheme: String?) -> String? {
        switch scheme {
        case "x-apple.systempreferences": return "com.apple.systempreferences"
        default: return nil
        }
    }

    /// 用访达打开一个文件夹；访达已在前台时按"再按一次收起"处理
    private static func toggleFolder(_ item: LaunchItem) {
        guard item.exists else {
            DispatchQueue.main.async { Launcher.warnMissing(item) }
            return
        }
        let fid = "com.apple.finder"
        let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == fid
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: fid).first
        if AppStore.shared.toggleBack, isFront, let finder,
           WindowProbe.hasWindow(pid: finder.processIdentifier) {
            NSLog("[Handsout] 访达已在前台，收起并切回上一个应用")
            finder.hide()
            if let previous = AppTracker.shared.appToReturnTo(excluding: fid) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { activate(previous) }
            }
            return
        }
        NSLog("[Handsout] 用访达打开 \(item.path)")
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
    }

    /// 智能开关键：第一次启动/激活；目标已在前台时再按一次 -> 隐藏它并切回上一个应用
    private static func toggleApp(_ item: LaunchItem) {
        guard item.exists else {
            DispatchQueue.main.async { Launcher.warnMissing(item) }
            return
        }
        let url = URL(fileURLWithPath: item.path)
        let bundleID = Bundle(url: url)?.bundleIdentifier
        let running = bundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        }

        if let app = running, let bid = app.bundleIdentifier {
            let isFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bid
            let hasWindow = WindowProbe.hasWindow(pid: app.processIdentifier)
            NSLog("[Handsout] \(item.name): front=\(isFront) hidden=\(app.isHidden) 有窗口=\(hasWindow)")

            // 第二次按：在前台 + 真的有窗口 -> 收起来，回到上一个应用
            if AppStore.shared.toggleBack, isFront, !app.isHidden, hasWindow {
                NSLog("[Handsout] \(item.name) 已在前台且有窗口，隐藏并切回上一个应用")
                // 注意：hide() 返回 false 但隐藏是异步生效的（实测 ~0.5s 后 isHidden=true），
                // 所以切回上一个应用要稍等一下，否则焦点会被隐藏动作带走。
                let hidden = app.hide()
                NSLog("[Handsout] hide(\(item.name)) 立即返回 \(hidden)")
                if let previous = AppTracker.shared.appToReturnTo(excluding: bid) {
                    NSLog("[Handsout] 准备切回 \(previous.bundleIdentifier ?? "?")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activate(previous)
                        NSLog("[Handsout] 已切回 \(previous.bundleIdentifier ?? "?")，\(item.name).isHidden = \(app.isHidden)")
                    }
                }
                return
            }

            // 进程在、但一个窗口都没有（Finder 关掉窗口就是这种）：走真正的"打开"
            if !hasWindow && !app.isHidden {
                reveal(app: app, url: url, name: item.name)
                return
            }

            // 已运行但在后台 / 被隐藏过 -> 唤起（activateAllWindows 会顺带取消隐藏）
            let activated = activate(app)
            NSLog("[Handsout] \(item.name) 已运行（hidden=\(app.isHidden)），activate = \(activated)")
            // 保险：activate 是异步生效的（实测可能要 1s 才真正切换焦点），
            // 1s 后还没到前台就补一次（取消隐藏时常出现"窗口出来了但焦点没跟过来"）
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard !app.isActive || app.isHidden else { return }
                NSLog("[Handsout] \(item.name) 未真正到前台，补一次")
                if app.isHidden || !WindowProbe.hasWindow(pid: app.processIdentifier) {
                    reveal(app: app, url: url, name: item.name)
                } else {
                    _ = activate(app)
                }
            }
            return
        }

        NSLog("[Handsout] 启动 \(item.name)")
        openApplication(url: url, name: item.name)
    }

    /// 把某个应用带到前台。
    /// Handsout 是菜单栏应用（accessory），自己不是 active 时系统常常无视 activate 请求，
    /// 所以先把自己短暂激活一下，再把焦点转交出去。
    @discardableResult
    private static func activate(_ app: NSRunningApplication) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return app.activate(options: [.activateAllWindows])
    }

    /// 让"进程在但看不见"的应用真正露出窗口。
    /// Finder 关掉窗口后进程永远在，activate 不会开窗，必须显式让它显示一个目录。
    private static func reveal(app: NSRunningApplication, url: URL, name: String) {
        if app.bundleIdentifier == "com.apple.finder" {
            NSLog("[Handsout] Finder 无窗口，打开访达窗口")
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: NSHomeDirectory())])
        } else {
            NSLog("[Handsout] \(name) 无窗口，走 openApplication（多数 app 会重新开一个窗口）")
            openApplication(url: url, name: name)
        }
    }

    /// 直接打开（设置界面里的播放按钮用，不做隐藏切换）
    static func launch(_ item: LaunchItem) {
        guard item.exists else {
            DispatchQueue.main.async { Launcher.warnMissing(item) }
            return
        }
        switch item.kind {
        case .app: openApplication(url: URL(fileURLWithPath: item.path), name: item.name)
        case .url: openURLItem(item)
        case .folder: NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        }
    }

    private static func openApplication(url: URL, name: String) {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error { NSLog("[Handsout] 启动 \(name) 失败: \(error.localizedDescription)") }
        }
    }

    private static func warnMissing(_ item: LaunchItem) {
        let alert = NSAlert()
        alert.messageText = item.kind == .app ? "找不到应用" : "找不到\(item.kind.label)"
        alert.informativeText = "\(item.name) 已不在原位置：\n\(item.path)"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - 应用扫描

struct ScannedApp: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

enum AppScanner {
    static func installedApps() -> [ScannedApp] {
        let fm = FileManager.default
        let dirs = ["/Applications",
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                    "/System/Applications"]
        var result: [ScannedApp] = []
        var seen = Set<String>()
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = (dir as NSString).appendingPathComponent(entry)
                let name = (entry as NSString).deletingPathExtension
                if name.hasPrefix(".") || seen.contains(name) { continue }
                seen.insert(name)
                result.append(ScannedApp(name: name, path: path))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - 辅助功能权限

enum Accessibility {
    static func isTrusted() -> Bool { AXIsProcessTrusted() }

    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
