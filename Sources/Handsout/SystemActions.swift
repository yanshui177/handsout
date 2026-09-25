import AppKit
import Foundation

/// 一个可以被快捷键绑定的"系统功能"。
/// 它可能是系统设置的某个面板（URL scheme）、一个文件夹，或者一个系统自带应用。
struct SystemAction: Identifiable, Hashable {
    let id: String
    let name: String
    /// .url -> 完整的 URL scheme；.folder -> 目录路径；.app -> .app 包路径
    let target: String
    let kind: ItemKind
    /// SF Symbol 名（图标展示用）
    let symbol: String
    /// 自动分配快捷键时优先使用的字母
    let hint: String?
    /// 搜索关键字（中文别名 / 英文）
    let keywords: String

    init(id: String,
         name: String,
         target: String,
         kind: ItemKind,
         symbol: String,
         hint: String? = nil,
         keywords: String = "") {
        self.id = id
        self.name = name
        self.target = target
        self.kind = kind
        self.symbol = symbol
        self.hint = hint
        self.keywords = keywords
    }

    /// 系统设置面板
    init(paneID: String, name: String, symbol: String, hint: String, keywords: String = "") {
        self.init(id: "pane." + paneID,
                  name: name,
                  target: SystemAction.prefix + paneID,
                  kind: .url,
                  symbol: symbol,
                  hint: hint,
                  keywords: keywords)
    }

    static let prefix = "x-apple.systempreferences:"

    func makeItem() -> LaunchItem {
        LaunchItem(name: name, path: target, kind: kind, symbol: symbol)
    }
}

/// 设置界面里按类别分组展示
struct SystemGroup: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let actions: [SystemAction]
}

enum SystemCatalog {
    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    // MARK: 系统设置面板
    // 面板 ID 取自本机的 /System/Library/ExtensionKit/Extensions/*.appex 与
    // System Settings.app/Contents/PlugIns/*.appex 的真实 CFBundleIdentifier，
    // 不要用网上流传的旧版 com.apple.preference.*（新系统上未必还能解析）。

    // 面板 ID 和中文名都用 `Handsout --dump-panes` / `--probe-pane` 在本机实测过；
    // 别照抄网上流传的 com.apple.preference.*，新版 macOS 上很多已经解析不了。
    private static let panes: [SystemAction] = [
        SystemAction(paneID: "", name: "系统设置", symbol: "gearshape", hint: "S", keywords: "设置 system settings preferences 总览"),
        SystemAction(paneID: "com.apple.systempreferences.GeneralSettings", name: "通用", symbol: "gearshape.2", hint: "G", keywords: "general 通用 关于 about"),
        SystemAction(paneID: "com.apple.Network-Settings.extension", name: "网络", symbol: "network", hint: "N", keywords: "network 网络 以太网 ethernet"),
        SystemAction(paneID: "com.apple.wifi-settings-extension", name: "Wi-Fi", symbol: "wifi", hint: "W", keywords: "wifi 无线 无线网络"),
        SystemAction(paneID: "com.apple.BluetoothSettings", name: "蓝牙", symbol: "dot.radiowaves.left.and.right", hint: "B", keywords: "bluetooth 蓝牙"),
        SystemAction(paneID: "com.apple.Appearance-Settings.extension", name: "外观", symbol: "circle.lefthalf.filled", hint: "A", keywords: "appearance 深色 浅色 主题 外观"),
        SystemAction(paneID: "com.apple.Wallpaper-Settings.extension", name: "墙纸", symbol: "photo.on.rectangle", hint: "P", keywords: "wallpaper 壁纸 桌面图片"),
        SystemAction(paneID: "com.apple.Desktop-Settings.extension", name: "桌面与程序坞", symbol: "square.stack", hint: "D", keywords: "dock 程序坞 desktop 台前调度"),
        SystemAction(paneID: "com.apple.Displays-Settings.extension", name: "显示器", symbol: "display.2", hint: "M", keywords: "display 显示器 分辨率 屏幕"),
        SystemAction(paneID: "com.apple.Sound-Settings.extension", name: "声音", symbol: "speaker.wave.2", hint: "O", keywords: "sound 声音 音量 输出"),
        SystemAction(paneID: "com.apple.Battery-Settings.extension", name: "能耗", symbol: "battery.100percent", hint: "E", keywords: "battery 电池 电量 能耗 省电"),
        SystemAction(paneID: "com.apple.settings.PrivacySecurity.extension", name: "隐私与安全性", symbol: "hand.raised.fill", hint: "R", keywords: "privacy security 隐私 安全 权限"),
        SystemAction(paneID: "com.apple.Lock-Screen-Settings.extension", name: "锁定屏幕", symbol: "lock.fill", hint: "L", keywords: "lock screen 锁屏 屏保"),
        SystemAction(paneID: "com.apple.Touch-ID-Settings.extension", name: "登录密码", symbol: "lock.rotation", hint: "T", keywords: "touch id password 密码 指纹 触控id"),
        SystemAction(paneID: "com.apple.Users-Groups-Settings.extension", name: "用户与群组", symbol: "person.2.fill", hint: "U", keywords: "users groups 用户 群组 账户"),
        SystemAction(paneID: "com.apple.Keyboard-Settings.extension", name: "键盘", symbol: "keyboard", hint: "K", keywords: "keyboard 键盘 输入法"),
        SystemAction(paneID: "com.apple.Mouse-Settings.extension", name: "鼠标", symbol: "computermouse", hint: "H", keywords: "mouse 鼠标"),
        SystemAction(paneID: "com.apple.settings.Storage", name: "储存空间", symbol: "internaldrive", hint: "V", keywords: "storage 存储 磁盘 空间"),
        SystemAction(paneID: "com.apple.Software-Update-Settings.extension", name: "软件更新", symbol: "arrow.down.circle", hint: "Z", keywords: "software update 更新 升级"),
        SystemAction(paneID: "com.apple.Notifications-Settings.extension", name: "通知", symbol: "bell.badge", hint: "I", keywords: "notification 通知"),
        SystemAction(paneID: "com.apple.Focus-Settings.extension", name: "专注模式", symbol: "moon.fill", hint: "F", keywords: "focus 专注 免打扰 dnd"),
        SystemAction(paneID: "com.apple.Accessibility-Settings.extension", name: "辅助功能", symbol: "accessibility", hint: "X", keywords: "accessibility 辅助 无障碍"),
        SystemAction(paneID: "com.apple.Print-Scan-Settings.extension", name: "打印机与扫描仪", symbol: "printer.fill", hint: "1", keywords: "printer scanner 打印 扫描"),
        SystemAction(paneID: "com.apple.Date-Time-Settings.extension", name: "日期与时间", symbol: "clock.fill", hint: "2", keywords: "date time 时间 日期 时区"),
        SystemAction(paneID: "com.apple.Sharing-Settings.extension", name: "共享", symbol: "square.and.arrow.up.fill", hint: "3", keywords: "sharing 共享"),
        SystemAction(paneID: "com.apple.Spotlight-Settings.extension", name: "聚焦", symbol: "magnifyingglass.circle.fill", hint: "4", keywords: "spotlight 聚焦 搜索"),
        SystemAction(paneID: "com.apple.Siri-Settings.extension", name: "Siri", symbol: "sparkle", hint: "5", keywords: "siri 语音助手"),
        SystemAction(paneID: "com.apple.Time-Machine-Settings.extension", name: "时间机器", symbol: "clock.arrow.2.circlepath", hint: "6", keywords: "time machine 备份"),
        SystemAction(paneID: "com.apple.Screen-Time-Settings.extension", name: "屏幕时间", symbol: "hourglass", hint: "7", keywords: "screen time 使用时间"),
        SystemAction(paneID: "com.apple.LoginItems-Settings.extension", name: "登录项与扩展", symbol: "power", hint: "8", keywords: "login items 登录项 开机启动 扩展"),
        SystemAction(paneID: "com.apple.ControlCenter-Settings.extension", name: "菜单栏", symbol: "switch.2", hint: "9", keywords: "control center 控制中心 菜单栏"),
        SystemAction(paneID: "com.apple.Internet-Accounts-Settings.extension", name: "互联网账户", symbol: "globe", hint: "0", keywords: "internet accounts 互联网账户 邮箱 日历"),
        SystemAction(paneID: "com.apple.systempreferences.AppleIDSettings", name: "Apple 账户", symbol: "apple.logo", hint: "Q", keywords: "apple id 苹果账户 icloud"),
        SystemAction(paneID: "com.apple.Family-Settings.extension", name: "家人共享", symbol: "person.3.fill", hint: "J", keywords: "family 家人共享"),
        SystemAction(paneID: "com.apple.WalletSettingsExtension", name: "钱包与 Apple Pay", symbol: "wallet.pass.fill", hint: "Y", keywords: "wallet apple pay 钱包 支付"),
    ]

    // MARK: 常用文件夹

    private static var folders: [SystemAction] {
        let h = home
        return [
            SystemAction(id: "folder.applications", name: "应用程序", target: "/Applications", kind: .folder, symbol: "folder.fill", hint: "A", keywords: "applications 应用 app 列表 应用程序列表 启动台 launchpad"),
            SystemAction(id: "folder.downloads", name: "下载", target: h + "/Downloads", kind: .folder, symbol: "arrow.down.circle.fill", hint: "D", keywords: "downloads 下载"),
            SystemAction(id: "folder.documents", name: "文稿", target: h + "/Documents", kind: .folder, symbol: "doc.fill", hint: "O", keywords: "documents 文稿 文档"),
            SystemAction(id: "folder.desktop", name: "桌面", target: h + "/Desktop", kind: .folder, symbol: "macwindow", hint: "E", keywords: "desktop 桌面"),
            SystemAction(id: "folder.home", name: "用户目录", target: h, kind: .folder, symbol: "house.fill", hint: "H", keywords: "home 用户 家目录"),
            SystemAction(id: "folder.movies", name: "影片", target: h + "/Movies", kind: .folder, symbol: "film", hint: "M", keywords: "movies 影片 视频"),
            SystemAction(id: "folder.pictures", name: "图片", target: h + "/Pictures", kind: .folder, symbol: "photo", hint: "P", keywords: "pictures 图片 照片"),
            SystemAction(id: "folder.utilities", name: "实用工具", target: "/System/Applications/Utilities", kind: .folder, symbol: "wrench.and.screwdriver.fill", hint: "U", keywords: "utilities 实用工具"),
        ]
    }

    // MARK: 系统自带应用

    // 注意：macOS 26 的 /System/Applications/Apps.app 无法被程序化唤起（实测 open / openApplication
    // / 直接跑二进制都不起进程），所以"应用程序列表"走 /Applications 文件夹。
    private static let systemApps: [SystemAction] = [
        SystemAction(id: "app.systemsettings", name: "系统设置.app", target: "/System/Applications/System Settings.app", kind: .app, symbol: "gearshape", hint: "S", keywords: "system settings 系统设置 偏好设置"),
        SystemAction(id: "app.finder", name: "访达", target: "/System/Library/CoreServices/Finder.app", kind: .app, symbol: "folder", hint: "F", keywords: "finder 访达"),
        SystemAction(id: "app.terminal", name: "终端", target: "/System/Applications/Utilities/Terminal.app", kind: .app, symbol: "apple.terminal", hint: "T", keywords: "terminal 终端 shell 命令行"),
        SystemAction(id: "app.activitymonitor", name: "活动监视器", target: "/System/Applications/Utilities/Activity Monitor.app", kind: .app, symbol: "cpu", hint: "C", keywords: "activity monitor 活动监视器 任务管理器 cpu"),
        SystemAction(id: "app.diskutility", name: "磁盘工具", target: "/System/Applications/Utilities/Disk Utility.app", kind: .app, symbol: "internaldrive", hint: "K", keywords: "disk utility 磁盘工具 急救"),
        SystemAction(id: "app.systeminfo", name: "系统信息", target: "/System/Applications/Utilities/System Information.app", kind: .app, symbol: "info.circle.fill", hint: "I", keywords: "system information 系统信息 硬件 序列号"),
        SystemAction(id: "app.console", name: "控制台", target: "/System/Applications/Utilities/Console.app", kind: .app, symbol: "terminal.fill", hint: "O", keywords: "console 控制台 日志 log"),
    ]

    static var groups: [SystemGroup] {
        [
            SystemGroup(id: "pane", title: "系统设置面板", symbol: "gearshape", actions: panes),
            SystemGroup(id: "folder", title: "文件夹", symbol: "folder", actions: folders),
            SystemGroup(id: "sysapp", title: "系统应用", symbol: "apple.logo", actions: systemApps),
        ]
    }

    /// 按关键字过滤；空关键字返回全部分组
    static func search(_ query: String) -> [SystemGroup] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let hit = group.actions.filter {
                $0.name.localizedCaseInsensitiveContains(q) || $0.keywords.localizedCaseInsensitiveContains(q)
            }
            return hit.isEmpty ? nil : SystemGroup(id: group.id, title: group.title, symbol: group.symbol, actions: hit)
        }
    }

    static func action(id: String) -> SystemAction? {
        groups.flatMap(\.actions).first { $0.id == id }
    }
}

// MARK: - 开发用探针

/// `Handsout --probe-pane <id1,id2,...>`：依次打开面板，读取系统设置窗口标题，
/// 用来确认面板 ID 在当前系统版本上是否仍然有效（新 macOS 上 ID 会变）。
enum SystemPaneProbe {
    static func run(_ paneIDs: [String]) {
        var index = 0
        func step() {
            guard index < paneIDs.count else {
                print("PROBE DONE")
                fflush(stdout)
                exit(0)
            }
            let paneID = paneIDs[index]
            index += 1
            guard let url = URL(string: SystemAction.prefix + paneID) else {
                print("PROBE bad-url \(paneID)")
                step()
                return
            }
            let opened = NSWorkspace.shared.open(url)
            // 目标应用是菜单栏常驻的 accessory 时，导航是异步的，等久一点再读窗口标题
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                report(paneID: paneID, opened: opened)
                step()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { step() }
    }

    /// `Handsout --dump-panes`：遍历系统设置的 AX 树，把带 com.apple.* 标识的元素打出来，
    /// 用来拿到当前系统版本真实可用的面板 ID 列表。
    static func dumpPanes() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _ = NSWorkspace.shared.open(URL(string: SystemAction.prefix)!)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
                    print("DUMP 系统设置未运行")
                    fflush(stdout)
                    exit(0)
                }
                var seen = Set<String>()
                walk(AXUIElementCreateApplication(app.processIdentifier), depth: 0, seen: &seen)
                print("DUMP DONE")
                fflush(stdout)
                exit(0)
            }
        }
    }

    private static func walk(_ element: AXUIElement, depth: Int, seen: inout Set<String>) {
        guard depth < 16, seen.count < 3000 else { return }
        func attr(_ key: String) -> String {
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(element, key as CFString, &raw)
            return raw as? String ?? ""
        }
        let identifier = attr(kAXIdentifierAttribute)
        if identifier.contains("com.apple.") {
            let line = "\(identifier) | \(attr(kAXTitleAttribute)) | \(attr(kAXRoleAttribute))"
            if !seen.contains(line) {
                seen.insert(line)
                print("DUMP " + line)
            }
        }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
              let children = raw as? [AXUIElement] else { return }
        for child in children { walk(child, depth: depth + 1, seen: &seen) }
    }

    private static func report(paneID: String, opened: Bool) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            print("PROBE \(paneID) | opened=\(opened) | 系统设置未运行")
            fflush(stdout)
            return
        }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value)
        guard err == .success, let windows = value as? [AXUIElement] else {
            print("PROBE \(paneID) | opened=\(opened) | AX 错误 \(err.rawValue)")
            fflush(stdout)
            return
        }
        let titles = windows.compactMap { window -> String? in
            var raw: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &raw)
            return raw as? String
        }
        print("PROBE \(paneID) | opened=\(opened) | win=\(windows.count) | \(titles.joined(separator: " / "))")
        fflush(stdout)
    }
}
