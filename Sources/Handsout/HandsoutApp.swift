import SwiftUI

@main
struct HandsoutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
        } label: {
            Image(systemName: "hands.clap.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Button("打开设置…") { AppDelegate.shared.openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        if store.items.isEmpty {
            Text("还没有添加应用")
                .foregroundStyle(.secondary)
        } else {
            ForEach(store.items) { item in
                Button {
                    Launcher.toggle(item)
                } label: {
                    HStack(spacing: 8) {
                        Text(item.name)
                        Spacer(minLength: 16)
                        Text(item.hotkeyDisplay)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Divider()

        Button("显示快捷键面板") { HUDController.shared.show() }

        if !Accessibility.isTrusted() {
            Divider()
            Button("授予辅助功能权限…") { Accessibility.request() }
        }

        Divider()
        Button("退出 Handsout") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
