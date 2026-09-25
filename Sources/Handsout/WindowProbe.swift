import AppKit
import CoreGraphics

/// 探测一个应用当前是否真的有可见窗口。
///
/// 关键场景：Finder / Chrome 关掉全部窗口后进程仍在，
/// 此时"已运行"不等于"看得见"，单纯 activate 是没反应的。
///
/// 用 CGWindowList 而不是 AX：`AXUIElementCopyAttributeValue(kAXWindowsAttribute)`
/// 会把 Finder 的"桌面"也当成窗口，导致永远返回 true。
enum WindowProbe {
    /// 是否有尺寸正常的可见窗口（按 PID 匹配，排除桌面元素）
    static func hasWindow(pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            guard let owner = window[kCGWindowOwnerPID as String] as? Int32,
                  owner == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: Double] else { continue }
            if (bounds["Width"] ?? 0) > 80 && (bounds["Height"] ?? 0) > 80 { return true }
        }
        return false
    }
}
