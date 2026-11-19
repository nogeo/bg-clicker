import Cocoa
import Carbon
import ApplicationServices

// MARK: - 坐标转换与窗口查询辅助
enum ScreenHelper {
    /// 主屏幕高度（AppKit 原点在主屏左下角，CoreGraphics 原点在主屏左上角）
    static var primaryScreenHeight: CGFloat {
        for screen in NSScreen.screens {
            if screen.frame.origin == .zero {
                return screen.frame.height
            }
        }
        return NSScreen.screens.first?.frame.height ?? 1080
    }

    static func cgToAppKit(_ pt: CGPoint) -> NSPoint {
        return NSPoint(x: pt.x, y: primaryScreenHeight - pt.y)
    }

    static func currentMouseCGPoint() -> CGPoint {
        if let ev = CGEvent(source: nil) {
            return ev.location
        }
        let nsPt = NSEvent.mouseLocation
        return CGPoint(x: nsPt.x, y: primaryScreenHeight - nsPt.y)
    }

    struct WindowHit {
        let windowID: CGWindowID
        let pid: pid_t
        let ownerName: String
        let windowTitle: String
        let bounds: CGRect // CG 坐标系（左上角原点）
    }

    static func windowAt(cgPoint: CGPoint, excludingPID: pid_t) -> WindowHit? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != excludingPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            if bounds.width < 10 || bounds.height < 10 { continue }
            if bounds.contains(cgPoint) {
                let owner = (info[kCGWindowOwnerName as String] as? String) ?? "未知应用"
                let title = (info[kCGWindowName as String] as? String) ?? ""
                return WindowHit(windowID: wid, pid: pid, ownerName: owner, windowTitle: title, bounds: bounds)
            }
        }
        return nil
    }

    static func windowBounds(windowID: CGWindowID, pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first(where: {
                  ($0[kCGWindowNumber as String] as? CGWindowID) == windowID &&
                  ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
              }),
              let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return nil
        }
        return bounds
    }
}

private enum BackgroundMouseEvent {
    // 这两个 WindowServer 字段没有公开的 CGEventField 名称。
    private static let windowNumber = unsafeBitCast(UInt32(51), to: CGEventField.self)
    private static let clickGroup = unsafeBitCast(UInt32(58), to: CGEventField.self)

    private typealias SetWindowLocation = @convention(c) (CGEvent, CGPoint) -> Void
    private static let setWindowLocation: SetWindowLocation? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetWindowLocation.self)
    }()

    static func stamp(_ event: CGEvent, pid: pid_t, windowID: CGWindowID, windowPoint: CGPoint, group: Int64) {
        let id = Int64(windowID)
        event.setIntegerValueField(windowNumber, value: id)
        event.setIntegerValueField(clickGroup, value: group)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: id)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: id)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
        event.setIntegerValueField(.mouseEventSubtype, value: Int64(NSEvent.EventSubtype.touch.rawValue))
        event.setIntegerValueField(.mouseEventClickState, value: event.type == .mouseMoved ? 0 : 1)
        setWindowLocation?(event, windowPoint)
    }
}

// MARK: - 透明穿透纯红 1px 细线准星标记
final class MarkerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let cx = bounds.midX
        let cy = bounds.midY
        let red = NSColor(srgbRed: 1.0, green: 32.0 / 255.0, blue: 32.0 / 255.0, alpha: 1.0).cgColor

        ctx.setStrokeColor(red)
        ctx.setLineWidth(1.0)

        // 1px 细线外环
        ctx.strokeEllipse(in: CGRect(x: cx - 7.5, y: cy - 7.5, width: 15.0, height: 15.0))

        // 1px 细线十字准星
        ctx.move(to: CGPoint(x: cx - 12.5, y: cy))
        ctx.addLine(to: CGPoint(x: cx - 4.5, y: cy))
        ctx.move(to: CGPoint(x: cx + 4.5, y: cy))
        ctx.addLine(to: CGPoint(x: cx + 12.5, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - 12.5))
        ctx.addLine(to: CGPoint(x: cx, y: cy - 4.5))
        ctx.move(to: CGPoint(x: cx, y: cy + 4.5))
        ctx.addLine(to: CGPoint(x: cx, y: cy + 12.5))
        ctx.strokePath()

        // 中心小红点
        ctx.setFillColor(red)
        ctx.fillEllipse(in: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3.0, height: 3.0))
    }
}

final class MarkerWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: -10000, y: -10000, width: 29, height: 29),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = MarkerView(frame: NSRect(x: 0, y: 0, width: 29, height: 29))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func moveToCGPoint(_ cgPt: CGPoint) {
        let appKitPt = ScreenHelper.cgToAppKit(cgPt)
        let origin = NSPoint(x: round(appKitPt.x - frame.width / 2.0),
                             y: round(appKitPt.y - frame.height / 2.0))
        if frame.origin != origin {
            setFrameOrigin(origin)
        }
    }
}

// MARK: - 全局热键管理（Carbon RegisterEventHotKey）
final class HotKeyManager {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private let callback: (UInt32) -> Void

    init(callback: @escaping (UInt32) -> Void) {
        self.callback = callback
        installHandler()
    }

    deinit {
        unregisterAll()
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if err == noErr {
                    let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async {
                        mgr.callback(hotKeyID.id)
                    }
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            1,
            &eventSpec,
            selfPtr,
            &handlerRef
        )
        _ = status
    }

    @discardableResult
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32 = 0) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: 0x4247434B, id: id) // 'BGCK'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
            return true
        }
        return false
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            if let r = ref { UnregisterEventHotKey(r) }
        }
        hotKeyRefs.removeAll()
        if let h = handlerRef {
            RemoveEventHandler(h)
            handlerRef = nil
        }
    }
}

// MARK: - 主窗口与连点逻辑
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let hkF8: UInt32  = 1
    private static let hkF9: UInt32  = 2
    private static let hkF10: UInt32 = 3

    private var window: NSWindow!
    private var markerWindow: MarkerWindow!
    private var hotKeys: HotKeyManager!

    // 目标状态
    private let stateLock = NSLock()
    private var targetPID: pid_t = 0
    private var targetWindowID: CGWindowID = 0
    private var relX: CGFloat = 0
    private var relY: CGFloat = 0

    // 运行状态
    private var isRunning = false
    private var isPaused = false
    private var clickCount: Int64 = 0
    private var wakeSem = DispatchSemaphore(value: 0)

    // UI 控件
    private var lblProcess: NSTextField!
    private var lblWindow: NSTextField!
    private var lblCoord: NSTextField!
    private var lblPerm: NSTextField!
    private var btnPerm: NSButton!

    private var txtInterval: NSTextField!
    private var txtJitter: NSTextField!
    private var txtHold: NSTextField!
    private var txtCount: NSTextField!
    private var popButton: NSPopUpButton!
    private var popMode: NSPopUpButton!
    private var chkTopMost: NSButton!
    private var chkShowMarker: NSButton!

    private var btnPick: NSButton!
    private var btnStartPause: NSButton!
    private var btnStop: NSButton!
    private var lblStatus: NSTextField!
    private var lblClicks: NSTextField!

    private var markerTimer: Timer?
    private var pickTimer: Timer?
    private var pickCountdown = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()

        markerWindow = MarkerWindow()
        hotKeys = HotKeyManager { [weak self] id in
            guard let self = self else { return }
            switch id {
            case Self.hkF8:  self.pickTargetAtCursor()
            case Self.hkF9:  self.toggleStartPause()
            case Self.hkF10: self.stopClicking(reason: "收到 F10 已停止")
            default: break
            }
        }
        let ok8  = hotKeys.register(id: Self.hkF8,  keyCode: UInt32(kVK_F8))
        let ok9  = hotKeys.register(id: Self.hkF9,  keyCode: UInt32(kVK_F9))
        let ok10 = hotKeys.register(id: Self.hkF10, keyCode: UInt32(kVK_F10))
        if !(ok8 && ok9 && ok10) {
            setStatus("提示：部分全局热键被占用，可用界面按钮操作", color: .systemOrange)
        }

        checkAccessibilityPermission(prompt: false)

        markerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.syncMarkerAndPermission()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopClicking(reason: "程序退出")
        hotKeys?.unregisterAll()
        markerTimer?.invalidate()
        pickTimer?.invalidate()
        markerWindow?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出后台连点器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }

    private func buildWindow() {
        let width: CGFloat = 450
        let height: CGFloat = 472
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "后台连点器 (macOS)"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        window.contentView = root

        // 顶部权限条
        lblPerm = makeLabel("辅助功能权限：检查中...", frame: NSRect(x: 16, y: 440, width: 310, height: 20), size: 12)
        btnPerm = NSButton(title: "去授权", target: self, action: #selector(openAccessibilitySettings))
        btnPerm.bezelStyle = .rounded
        btnPerm.frame = NSRect(x: 356, y: 436, width: 78, height: 26)
        root.addSubview(lblPerm)
        root.addSubview(btnPerm)

        // 1. 目标窗口卡片
        let targetBox = NSBox(frame: NSRect(x: 14, y: 316, width: 422, height: 114))
        targetBox.title = "目标窗口（鼠标指到目标位置按 F8 锁定）"
        lblProcess = makeLabel("进程：未锁定", frame: NSRect(x: 10, y: 66, width: 396, height: 18), size: 12.5)
        lblWindow  = makeLabel("窗口：-", frame: NSRect(x: 10, y: 42, width: 396, height: 18), size: 12.5)
        lblCoord   = makeLabel("坐标：-", frame: NSRect(x: 10, y: 18, width: 396, height: 18), size: 12.5, color: .systemBlue)
        targetBox.contentView?.addSubview(lblProcess)
        targetBox.contentView?.addSubview(lblWindow)
        targetBox.contentView?.addSubview(lblCoord)
        root.addSubview(targetBox)

        // 2. 参数设置卡片
        let settingsBox = NSBox(frame: NSRect(x: 14, y: 136, width: 422, height: 170))
        settingsBox.title = "连点参数"
        let sc = settingsBox.contentView!

        sc.addSubview(makeLabel("间隔 (ms):", frame: NSRect(x: 10, y: 122, width: 76, height: 20), size: 12.5))
        txtInterval = makeInput("50", frame: NSRect(x: 88, y: 120, width: 90, height: 24))
        sc.addSubview(txtInterval)

        sc.addSubview(makeLabel("随机抖动 (±ms):", frame: NSRect(x: 196, y: 122, width: 106, height: 20), size: 12.5))
        txtJitter = makeInput("0", frame: NSRect(x: 306, y: 120, width: 92, height: 24))
        sc.addSubview(txtJitter)

        sc.addSubview(makeLabel("按住 (ms):", frame: NSRect(x: 10, y: 88, width: 76, height: 20), size: 12.5))
        txtHold = makeInput("10", frame: NSRect(x: 88, y: 86, width: 90, height: 24))
        sc.addSubview(txtHold)

        sc.addSubview(makeLabel("次数 (0=无限):", frame: NSRect(x: 196, y: 88, width: 106, height: 20), size: 12.5))
        txtCount = makeInput("0", frame: NSRect(x: 306, y: 86, width: 92, height: 24))
        sc.addSubview(txtCount)

        sc.addSubview(makeLabel("按键:", frame: NSRect(x: 10, y: 52, width: 76, height: 20), size: 12.5))
        popButton = NSPopUpButton(frame: NSRect(x: 86, y: 48, width: 96, height: 26), pullsDown: false)
        popButton.addItems(withTitles: ["鼠标左键", "鼠标右键"])
        sc.addSubview(popButton)

        sc.addSubview(makeLabel("模式:", frame: NSRect(x: 196, y: 52, width: 42, height: 20), size: 12.5))
        popMode = NSPopUpButton(frame: NSRect(x: 240, y: 48, width: 162, height: 26), pullsDown: false)
        popMode.addItems(withTitles: ["后台定向 (不抢鼠标)", "全局模拟 (兼容模式)"])
        sc.addSubview(popMode)

        chkTopMost = NSButton(checkboxWithTitle: "窗口置顶", target: self, action: #selector(onTopMostChanged))
        chkTopMost.frame = NSRect(x: 10, y: 14, width: 100, height: 22)
        chkTopMost.state = .on
        sc.addSubview(chkTopMost)

        chkShowMarker = NSButton(checkboxWithTitle: "红点标记", target: self, action: #selector(onMarkerChanged))
        chkShowMarker.frame = NSRect(x: 120, y: 14, width: 100, height: 22)
        chkShowMarker.state = .on
        sc.addSubview(chkShowMarker)

        root.addSubview(settingsBox)

        // 3. 三按钮并排（F8 / F9 / F10）
        btnPick = NSButton(title: "锁定位置 (F8)", target: self, action: #selector(onPickClicked))
        btnPick.bezelStyle = .rounded
        btnPick.frame = NSRect(x: 14, y: 84, width: 134, height: 38)
        root.addSubview(btnPick)

        btnStartPause = NSButton(title: "开始 (F9)", target: self, action: #selector(onStartPauseClicked))
        btnStartPause.bezelStyle = .rounded
        btnStartPause.frame = NSRect(x: 158, y: 84, width: 134, height: 38)
        root.addSubview(btnStartPause)

        btnStop = NSButton(title: "停止 (F10)", target: self, action: #selector(onStopClicked))
        btnStop.bezelStyle = .rounded
        btnStop.isEnabled = false
        btnStop.frame = NSRect(x: 302, y: 84, width: 134, height: 38)
        root.addSubview(btnStop)

        // 4. 状态栏
        let statusBox = NSBox(frame: NSRect(x: 14, y: 34, width: 422, height: 40))
        statusBox.titlePosition = .noTitle
        lblStatus = makeLabel("状态：待机（请按 F8 锁定目标）", frame: NSRect(x: 8, y: 8, width: 278, height: 20), size: 12.5, color: .secondaryLabelColor)
        lblClicks = makeLabel("已发送：0 次", frame: NSRect(x: 290, y: 8, width: 118, height: 20), size: 12.5, align: .right)
        lblClicks.font = NSFont.boldSystemFont(ofSize: 12.5)
        statusBox.contentView?.addSubview(lblStatus)
        statusBox.contentView?.addSubview(lblClicks)
        root.addSubview(statusBox)

        let hint = makeLabel("全局热键：F8 锁定位置 | F9 开始/暂停 | F10 停止",
                             frame: NSRect(x: 14, y: 10, width: 422, height: 18),
                             size: 11, color: .tertiaryLabelColor, align: .center)
        root.addSubview(hint)
    }

    private func makeLabel(_ text: String, frame: NSRect, size: CGFloat,
                           color: NSColor = .labelColor, align: NSTextAlignment = .left) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.frame = frame
        lbl.font = NSFont.systemFont(ofSize: size)
        lbl.textColor = color
        lbl.alignment = align
        lbl.lineBreakMode = .byTruncatingTail
        return lbl
    }

    private func makeInput(_ text: String, frame: NSRect) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.frame = frame
        tf.font = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        return tf
    }

    // MARK: - 权限检查
    private func checkAccessibilityPermission(prompt: Bool) {
        let trusted = prompt ? CGRequestPostEventAccess() : CGPreflightPostEventAccess()
        if trusted {
            lblPerm.stringValue = "辅助功能权限：已授权"
            lblPerm.textColor = .systemGreen
            btnPerm.isHidden = true
        } else {
            lblPerm.stringValue = "辅助功能权限：未授权（连点需要开启）"
            lblPerm.textColor = .systemRed
            btnPerm.isHidden = false
        }
    }

    @objc private func openAccessibilitySettings() {
        checkAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 界面交互
    @objc private func onTopMostChanged() {
        window.level = (chkTopMost.state == .on) ? .floating : .normal
    }

    @objc private func onMarkerChanged() {
        syncMarkerAndPermission()
    }

    @objc private func onPickClicked() {
        pickTimer?.invalidate()
        pickCountdown = 2
        btnPick.title = "移到目标 (2s)"
        setStatus("请在 2 秒内把鼠标移到目标位置（或直接按 F8）", color: .systemBlue)
        pickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.pickCountdown -= 1
            if self.pickCountdown <= 0 {
                self.cancelDelayedPick()
                self.pickTargetAtCursor()
            } else {
                self.btnPick.title = "移到目标 (\(self.pickCountdown)s)"
                self.setStatus("请在 \(self.pickCountdown) 秒内把鼠标移到目标位置（或直接按 F8）", color: .systemBlue)
            }
        }
    }

    private func cancelDelayedPick() {
        pickTimer?.invalidate()
        pickTimer = nil
        btnPick.title = "锁定位置 (F8)"
    }

    @objc private func onStartPauseClicked() {
        toggleStartPause()
    }

    @objc private func onStopClicked() {
        stopClicking(reason: "已手动停止")
    }

    // MARK: - 锁定目标与红点同步
    private func pickTargetAtCursor() {
        cancelDelayedPick()
        let cgPt = ScreenHelper.currentMouseCGPoint()
        let myPID = ProcessInfo.processInfo.processIdentifier

        guard let hit = ScreenHelper.windowAt(cgPoint: cgPt, excludingPID: myPID) else {
            setStatus("未检测到目标窗口，请移到其他应用窗口上按 F8", color: .systemOrange)
            return
        }

        let rx = cgPt.x - hit.bounds.origin.x
        let ry = cgPt.y - hit.bounds.origin.y

        stateLock.lock()
        targetPID = hit.pid
        targetWindowID = hit.windowID
        relX = rx
        relY = ry
        stateLock.unlock()

        let titleText = hit.windowTitle.isEmpty ? "(窗口 ID: \(hit.windowID))" : hit.windowTitle
        lblProcess.stringValue = "进程：\(hit.ownerName) (PID: \(hit.pid))"
        lblWindow.stringValue  = "窗口：\(titleText)"
        lblCoord.stringValue   = String(format: "坐标：相对 (%.0f, %.0f) | 屏幕 (%.0f, %.0f)", rx, ry, cgPt.x, cgPt.y)

        syncMarkerAndPermission()

        if !isRunning {
            setStatus("已锁定目标，按 F9 开始连点", color: .systemGreen)
        }
    }

    private func currentTarget() -> (pid: pid_t, windowID: CGWindowID, screenPoint: CGPoint, windowPoint: CGPoint)? {
        stateLock.lock()
        let pid = targetPID
        let wid = targetWindowID
        let rx = relX
        let ry = relY
        stateLock.unlock()

        guard pid != 0, let bounds = ScreenHelper.windowBounds(windowID: wid, pid: pid) else { return nil }
        return (pid, wid,
                CGPoint(x: bounds.minX + rx, y: bounds.minY + ry),
                CGPoint(x: rx, y: ry))
    }

    private func syncMarkerAndPermission() {
        checkAccessibilityPermission(prompt: false)

        guard chkShowMarker.state == .on else {
            markerWindow.orderOut(nil)
            return
        }

        if let target = currentTarget() {
            markerWindow.moveToCGPoint(target.screenPoint)
            if !markerWindow.isVisible {
                markerWindow.orderFrontRegardless()
            }
        } else {
            markerWindow.orderOut(nil)
        }
    }

    // MARK: - 连点启停控制
    private func toggleStartPause() {
        if currentTarget() == nil {
            setStatus("尚未锁定有效目标，请先指到目标按 F8", color: .systemRed)
            return
        }

        if !CGPreflightPostEventAccess() {
            checkAccessibilityPermission(prompt: true)
            setStatus("请先在系统设置中授予「辅助功能」权限", color: .systemRed)
            return
        }

        if !isRunning {
            startClicking()
        } else {
            isPaused.toggle()
            wakeSem.signal()
            if isPaused {
                btnStartPause.title = "继续 (F9)"
                setStatus("已暂停（按 F9 继续）", color: .systemOrange)
            } else {
                btnStartPause.title = "暂停 (F9)"
                setStatus("运行中...", color: .systemGreen)
            }
        }
    }

    private func startClicking() {
        let intervalMs = max(10, Int(txtInterval.stringValue) ?? 50)
        let jitterMs   = max(0, Int(txtJitter.stringValue) ?? 0)
        let holdMs     = max(0, Int(txtHold.stringValue) ?? 10)
        let maxCount   = max(0, Int64(txtCount.stringValue) ?? 0)
        let rightBtn   = (popButton.indexOfSelectedItem == 1)
        let globalMode = (popMode.indexOfSelectedItem == 1)

        isRunning = true
        isPaused = false
        clickCount = 0
        lblClicks.stringValue = "已发送：0 次"
        btnStartPause.title = "暂停 (F9)"
        btnStop.isEnabled = true
        setEditable(false)
        setStatus(globalMode ? "运行中（全局模拟模式）" : "运行中（后台定向，不抢鼠标）", color: .systemGreen)

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            self?.workerLoop(intervalMs: intervalMs, jitterMs: jitterMs, holdMs: holdMs,
                             maxCount: maxCount, rightBtn: rightBtn, globalMode: globalMode)
        }
    }

    private func stopClicking(reason: String) {
        if !isRunning { return }
        isRunning = false
        isPaused = false
        wakeSem.signal()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.btnStartPause.title = "开始 (F9)"
            self.btnStop.isEnabled = false
            self.setEditable(true)
            self.setStatus(reason, color: .secondaryLabelColor)
        }
    }

    private func setEditable(_ enabled: Bool) {
        txtInterval.isEnabled = enabled
        txtJitter.isEnabled   = enabled
        txtHold.isEnabled     = enabled
        txtCount.isEnabled    = enabled
        popButton.isEnabled   = enabled
        popMode.isEnabled     = enabled
    }

    private func setStatus(_ text: String, color: NSColor) {
        lblStatus.stringValue = "状态：" + text
        lblStatus.textColor = color
    }

    private func workerLoop(intervalMs: Int, jitterMs: Int, holdMs: Int,
                            maxCount: Int64, rightBtn: Bool, globalMode: Bool) {
        let downType: CGEventType = rightBtn ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = rightBtn ? .rightMouseUp : .leftMouseUp
        let btn: CGMouseButton = rightBtn ? .right : .left
        let source = globalMode ? CGEventSource(stateID: .hidSystemState) : nil

        while isRunning {
            if isPaused {
                _ = wakeSem.wait(timeout: .now() + .milliseconds(100))
                continue
            }

            guard let target = currentTarget() else {
                stopClicking(reason: "目标窗口已关闭，自动停止")
                break
            }

            func makeEvent(_ type: CGEventType) -> CGEvent? {
                CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target.screenPoint, mouseButton: btn)
            }

            guard let down = makeEvent(downType), let up = makeEvent(upType) else {
                stopClicking(reason: "无法创建鼠标事件，已停止")
                break
            }
            let group = Int64.random(in: 1...Int64(Int32.max))
            func post(_ event: CGEvent) {
                // 抬起事件在按住结束后投递，时间戳应反映实际投递顺序。
                event.timestamp = DispatchTime.now().uptimeNanoseconds
                if globalMode {
                    event.setIntegerValueField(.mouseEventClickState, value: event.type == .mouseMoved ? 0 : 1)
                    event.post(tap: .cghidEventTap)
                } else {
                    BackgroundMouseEvent.stamp(event, pid: target.pid, windowID: target.windowID,
                                               windowPoint: target.windowPoint, group: group)
                    event.postToPid(target.pid)
                }
            }

            if let move = makeEvent(.mouseMoved) { post(move) }
            post(down)
            if holdMs > 0 {
                _ = wakeSem.wait(timeout: .now() + .milliseconds(holdMs))
            }
            post(up)

            if !isRunning { break }

            clickCount += 1
            let currentCount = clickCount
            DispatchQueue.main.async { [weak self] in
                self?.lblClicks.stringValue = "已发送：\(currentCount) 次"
            }

            if maxCount > 0 && currentCount >= maxCount {
                stopClicking(reason: "已完成预定次数 (\(maxCount) 次)")
                break
            }

            var delay = intervalMs - holdMs
            if jitterMs > 0 {
                delay += Int.random(in: -jitterMs...jitterMs)
            }
            if delay < 5 { delay = 5 }

            _ = wakeSem.wait(timeout: .now() + .milliseconds(delay))
        }
    }
}

// MARK: - 入口
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
