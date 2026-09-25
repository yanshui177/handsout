import AppKit
import SwiftUI

private let kCellW: CGFloat = 108
private let kCellH: CGFloat = 108
private let kPadding: CGFloat = 20
private let kFooter: CGFloat = 26
private let kMaxCols = 6

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 长按 Option 时弹出的快捷键面板（不抢键盘焦点，可点击启动）
final class HUDController {
    static let shared = HUDController()

    private var panel: HUDPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    func show() {
        let items = AppStore.shared.items
        guard !items.isEmpty else { return }

        let cols = min(max(1, items.count), kMaxCols)
        let rows = Int(ceil(Double(items.count) / Double(cols)))
        let size = NSSize(width: CGFloat(cols) * kCellW + kPadding * 2,
                          height: CGFloat(rows) * kCellH + kPadding * 2 + kFooter)

        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        let hosting = NSHostingView(rootView: HUDView(items: items, columns: cols, size: size)
            .environmentObject(AppStore.shared))
        hosting.frame = NSRect(origin: .zero, size: size)

        let container = NSVisualEffectView(frame: hosting.frame)
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.addSubview(hosting)
        panel.contentView = container
        panel.setFrame(NSRect(origin: origin(for: size), size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        return NSPoint(x: vf.midX - size.width / 2,
                       y: vf.midY - size.height / 2 + 30)
    }
}

// MARK: - SwiftUI 内容

private struct HUDView: View {
    let items: [LaunchItem]
    let columns: Int
    let size: NSSize

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(kCellW), spacing: 0), count: columns)
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: gridColumns, spacing: 4) {
                ForEach(items) { HUDCell(item: $0) }
            }
            .padding(kPadding)
            .padding(.bottom, 2)

            Text("按住 ⌥ 继续按键，松开关闭 · 也可直接点击图标")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .frame(height: kFooter - 6)
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct HUDCell: View {
    let item: LaunchItem
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                AppIconView(path: item.path, size: 52)
                    .shadow(radius: 2)
                if item.isBound {
                    Text(KeyCodes.hudBadge(keyCode: item.keyCode, modifiers: item.modifiers))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: 60, height: 60)

            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.exists ? .white.opacity(0.92) : .red)
                .frame(width: kCellW - 12)
        }
        .frame(width: kCellW, height: kCellH)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? Color.white.opacity(0.14) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            OptionMonitor.shared.markConsumed()
            Launcher.toggle(item)
        }
        .help(item.exists ? "\(item.name)  \(item.hotkeyDisplay)" : "路径已失效：\(item.path)")
    }
}
