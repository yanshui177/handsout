import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate!

    private var settingsWindow: NSWindow?
    private var hotKeyBinding: AnyCancellable?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 菜单栏常驻，不显示 Dock 图标

        let store = AppStore.shared
        store.load()

        HotKeyCenter.shared.install()
        HotKeyCenter.shared.onHotKey = { [weak self] itemID in
            self?.trigger(itemID: itemID)
        }
        rebindHotKeys()
        hotKeyBinding = store.$items.sink { [weak self] _ in self?.rebindHotKeys() }

        AppTracker.shared.start()

        OptionMonitor.shared.start()

        NSLog("[Handsout] 启动参数: \(CommandLine.arguments)")

        let args = CommandLine.arguments
        if args.contains("--settings") {
            openSettings()
        } else if args.contains("--hud") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { HUDController.shared.show() }
        } else if !Accessibility.isTrusted() {
            // 首次运行引导授权，否则长按 ⌥ 收不到全局事件
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openSettings() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unbindAll()
        OptionMonitor.shared.stop()
        AppStore.shared.save()
    }

    private func rebindHotKeys() {
        HotKeyCenter.shared.bind(AppStore.shared.items)
    }

    private func trigger(itemID: UUID) {
        guard let item = AppStore.shared.items.first(where: { $0.id == itemID }) else { return }
        OptionMonitor.shared.markConsumed() // 热键已生效，本次按住 ⌥ 不再弹面板
        Launcher.toggle(item)
    }

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "Handsout 设置"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(AppStore.shared))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
