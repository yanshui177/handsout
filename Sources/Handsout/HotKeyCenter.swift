import AppKit
import Carbon.HIToolbox

/// 全局热键中心：用 Carbon 的 RegisterEventHotKey，不需要辅助功能权限。
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// 热键触发回调（参数是 LaunchItem.id）
    var onHotKey: ((UUID) -> Void)?

    private let signature: OSType = 0x484F_5554 // 'HOUT'
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var itemIDs: [UInt32: UUID] = [:]
    private var installed = false

    private init() {}

    func install() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            guard err == noErr else { return err }
            HotKeyCenter.shared.handle(id: hotKeyID.id)
            return noErr
        }, 1, &spec, nil, &handler)
        if status != noErr {
            NSLog("[Handsout] 安装热键事件处理器失败: \(status)")
        }
        installed = true
    }

    fileprivate func handle(id: UInt32) {
        guard let itemID = itemIDs[id] else { return }
        DispatchQueue.main.async { self.onHotKey?(itemID) }
    }

    /// 重新绑定所有热键（items 变化时调用）
    func bind(_ items: [LaunchItem]) {
        unbindAll()
        for (index, item) in items.enumerated() where item.isBound {
            let hotID = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let keyID = EventHotKeyID(signature: signature, id: hotID)
            let status = RegisterEventHotKey(item.keyCode,
                                             item.modifiers,
                                             keyID,
                                             GetApplicationEventTarget(),
                                             0,
                                             &ref)
            if status == noErr, let ref {
                refs[hotID] = ref
                itemIDs[hotID] = item.id
            } else {
                NSLog("[Handsout] 注册热键失败 \(item.name) \(item.hotkeyDisplay): \(status)")
            }
        }
    }

    func unbindAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        itemIDs.removeAll()
    }

    /// 试注册一次，用来检测冲突（比如系统已占用的 ⌘Space）
    func isAvailable(keyCode: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let probe = EventHotKeyID(signature: signature, id: UInt32(0xEEEE))
        let status = RegisterEventHotKey(keyCode, modifiers, probe, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { UnregisterEventHotKey(ref) }
        return status == noErr
    }
}
