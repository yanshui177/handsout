import AppKit
import Carbon.HIToolbox
import Foundation

/// 一个被快捷键绑定的应用
struct LaunchItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var keyCode: UInt32 = 0
    var modifiers: UInt32 = 0

    var isBound: Bool { keyCode != 0 && modifiers != 0 }
    var hotkeyDisplay: String { KeyCodes.display(keyCode: keyCode, modifiers: modifiers) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var icon: NSImage {
        if let cached = IconCache.shared.image(for: path) { return cached }
        let img = NSWorkspace.shared.icon(forFile: path)
        IconCache.shared.set(img, for: path)
        return img
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
    /// 智能开关键：第一次启动/激活；目标已在前台时再按一次 -> 隐藏它并切回上一个应用
    static func toggle(_ item: LaunchItem) {
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

    /// 直接启动（设置界面里的播放按钮用，不做隐藏切换）
    static func launch(_ item: LaunchItem) {
        guard item.exists else {
            DispatchQueue.main.async { Launcher.warnMissing(item) }
            return
        }
        openApplication(url: URL(fileURLWithPath: item.path), name: item.name)
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
        alert.messageText = "找不到应用"
        alert.informativeText = "\(item.name) 已不在原路径：\n\(item.path)"
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
