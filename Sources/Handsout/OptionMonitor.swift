import AppKit
import Carbon.HIToolbox

/// 长按 Option 检测：按住超过阈值显示 HUD，松开隐藏。
/// 需要辅助功能权限（AXIsProcessTrusted），否则收不到其他应用在前台时的按键事件。
final class OptionMonitor {
    static let shared = OptionMonitor()

    /// 本次按住 Option 是否已经触发过热键（避免反复弹面板）
    private var consumed = false
    private var optionDown = false
    private var workItem: DispatchWorkItem?
    private var tokens: [Any] = []

    private init() {}

    func start() {
        guard tokens.isEmpty else { return }
        let flags: NSEvent.EventTypeMask = .flagsChanged
        // 全局监听：其他应用在前台时也能收到
        if let t = NSEvent.addGlobalMonitorForEvents(matching: flags, handler: { [weak self] event in
            self?.handleFlags(event.modifierFlags)
        }) { tokens.append(t) }
        // 本地监听：Handsout 自己的窗口（设置/HUD）处于前台时
        if let t = NSEvent.addLocalMonitorForEvents(matching: flags, handler: { [weak self] event in
            self?.handleFlags(event.modifierFlags)
            return event
        }) { tokens.append(t) }

        // HUD 显示时按 Esc 关闭
        if let t = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape), HUDController.shared.isVisible else { return }
            DispatchQueue.main.async { self?.forceDismiss() }
        }) { tokens.append(t) }
    }

    func stop() {
        for t in tokens { NSEvent.removeMonitor(t) }
        tokens.removeAll()
    }

    /// 热键触发后调用：隐藏面板并标记本次按住已消费
    func markConsumed() {
        consumed = true
        cancelPending()
        HUDController.shared.hide()
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        let down = flags.contains(.option)
        if down && !optionDown {
            optionDown = true
            consumed = false
            scheduleShow()
        } else if !down && optionDown {
            optionDown = false
            cancelPending()
            if !consumed { HUDController.shared.hide() }
            consumed = false
        }
    }

    private func scheduleShow() {
        cancelPending()
        let delay = max(0, AppStore.shared.holdThreshold)
        let work = DispatchWorkItem { [weak self] in
            guard self?.consumed == false,
                  !AppStore.shared.items.isEmpty else { return }
            DispatchQueue.main.async { HUDController.shared.show() }
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPending() {
        workItem?.cancel()
        workItem = nil
    }

    private func forceDismiss() {
        consumed = true
        cancelPending()
        HUDController.shared.hide()
    }
}
