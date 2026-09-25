import AppKit

/// 追踪"上一个活跃应用"：第二次按下同一个快捷键时，用来切回去。
final class AppTracker {
    static let shared = AppTracker()

    private var observer: NSObjectProtocol?
    private var currentApp: NSRunningApplication?
    private var previousApp: NSRunningApplication?

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handleActivated(app)
        }
    }

    private func handleActivated(_ app: NSRunningApplication) {
        let mine = Bundle.main.bundleIdentifier
        guard app.bundleIdentifier != mine else { return } // 忽略 Handsout 自己
        if let current = currentApp, current.bundleIdentifier != app.bundleIdentifier {
            previousApp = current
        }
        currentApp = app
    }

    /// 可以切回去的应用：优先最近激活过的，其次任意可见的普通应用，最后兜底 Finder
    func appToReturnTo(excluding bundleID: String?) -> NSRunningApplication? {
        if let prev = previousApp,
           !prev.isTerminated,
           prev.bundleIdentifier != bundleID {
            return prev
        }
        let mine = Bundle.main.bundleIdentifier
        let fallback = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
            && !$0.isTerminated
            && !$0.isHidden
            && $0.bundleIdentifier != mine
            && $0.bundleIdentifier != bundleID
        }
        return fallback
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    }
}
