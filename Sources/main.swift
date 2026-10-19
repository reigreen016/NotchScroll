import AppKit
import ApplicationServices
import ScreenCaptureKit

final class NamePanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The caption is anchored explicitly to the actual bar, including near screen edges.
        frameRect
    }
}

// AX coordinates use a top-left origin; AppKit uses a bottom-left origin.
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

struct Entry {
    let element: AXUIElement
    let name: String
    let app: NSRunningApplication
    let frame: CGRect
    var x: CGFloat { frame.minX }
    var key: String { "\(app.processIdentifier):\(Int(frame.minX)):\(Int(frame.minY))" }
}

final class App: NSObject, NSApplicationDelegate {
    var status: NSStatusItem!
    var panel: NSPanel!
    var scroll: NSScrollView!
    var entries: [Entry] = []
    var globalMonitor: Any?
    var clickMonitor: Any?
    var localMonitor: Any?
    var lastGesture: TimeInterval = 0
    var opening = false
    var pointerTimer: Timer?
    var pointerLeftAt: TimeInterval?
    let hideDelay: TimeInterval = 1.0
    var overlayFrame = NSRect.zero
    var savedOffset: CGFloat?
    var namePanel: NSPanel!
    var itemButtons: [NSButton] = []
    var originalIcons: [String: NSImage] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let glyph = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let bar = NSBezierPath(roundedRect: NSRect(x: 1, y: 3, width: 18, height: 12), xRadius: 3, yRadius: 3)
            bar.lineWidth = 1.5
            bar.stroke()
            let arrows = NSBezierPath()
            arrows.lineWidth = 1.5
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round
            arrows.move(to: NSPoint(x: 5, y: 9)); arrows.line(to: NSPoint(x: 15, y: 9))
            arrows.move(to: NSPoint(x: 7, y: 11)); arrows.line(to: NSPoint(x: 5, y: 9)); arrows.line(to: NSPoint(x: 7, y: 7))
            arrows.move(to: NSPoint(x: 13, y: 11)); arrows.line(to: NSPoint(x: 15, y: 9)); arrows.line(to: NSPoint(x: 13, y: 7))
            arrows.stroke()
            return true
        }
        glyph.isTemplate = true
        status.button?.image = glyph
        status.button?.toolTip = "NotchScroll"
        let menu = NSMenu()
        menu.addItem(withTitle: "バーを表示", action: #selector(show), keyEquivalent: "")
        menu.addItem(withTitle: "アクセシビリティを許可…", action: #selector(permission), keyEquivalent: "")
        menu.addItem(withTitle: "表示中の元アイコンを取得…", action: #selector(captureIcons), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        status.menu = menu
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 86), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Keep the temporary interactive bar above notification banners. Reserve
        // the next level for its name caption; hide() still removes both panels.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 2)
        panel.isFloatingPanel = true
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        namePanel = NamePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        namePanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        namePanel.backgroundColor = .clear
        namePanel.isOpaque = false
        namePanel.hasShadow = true
        namePanel.ignoresMouseEvents = true
        namePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        namePanel.isReleasedWhenClosed = false
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in self?.handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.hide(); return nil }
            if event.type == .scrollWheel {
                let consumed = self.handle(event)
                return consumed ? nil : event
            }
            return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.hide() }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.updateHoverName()
            let retentionArea = NSRect(
                x: self.overlayFrame.minX - 20,
                y: self.overlayFrame.minY - 40,
                width: self.overlayFrame.width + 40,
                height: self.overlayFrame.height + 40
            )
            if retentionArea.contains(NSEvent.mouseLocation) {
                self.pointerLeftAt = nil
            } else {
                let now = ProcessInfo.processInfo.systemUptime
                if let leftAt = self.pointerLeftAt {
                    if now - leftAt >= self.hideDelay { self.hide() }
                } else {
                    self.pointerLeftAt = now
                }
            }
        }
        if !AXIsProcessTrusted() { permission() }
    }

    @objc func quit() { NSApp.terminate(nil) }
    @objc func permission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func screenUnderMouse() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    @objc func hide() {
        pointerLeftAt = nil
        namePanel.orderOut(nil)
        if panel.isVisible { savedOffset = scroll?.contentView.bounds.minX }
        panel.orderOut(nil)
        lastGesture = Date.timeIntervalSinceReferenceDate
    }

    @discardableResult func handle(_ event: NSEvent) -> Bool {
        guard let screen = screenUnderMouse() else { return false }
        let mouse = NSEvent.mouseLocation
        let leftEdge = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
        let barHeight = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        guard mouse.x >= leftEdge, mouse.y >= screen.frame.maxY - barHeight else { return false }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard abs(delta) > 0.1 else { return false }
        if !panel.isVisible {
            guard Date.timeIntervalSinceReferenceDate - lastGesture > 0.7,
                  event.momentumPhase.isEmpty else { return false }
            show()
        }
        guard panel.isVisible, let scroll else { return false }
        let clip = scroll.contentView
        let maxX = max(0, (scroll.documentView?.frame.width ?? 0) - clip.bounds.width)
        let amount = event.hasPreciseScrollingDeltas ? delta : delta * 10
        clip.scroll(to: NSPoint(x: min(maxX, max(0, clip.bounds.minX - amount)), y: 0))
        scroll.reflectScrolledClipView(clip)
        updateHoverName()
        return true
    }

    func discover() -> [Entry] {
        var result: [Entry] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            guard let extras = attribute(root, "AXExtrasMenuBar"), CFGetTypeID(extras) == AXUIElementGetTypeID() else { continue }
            let bar = unsafeBitCast(extras, to: AXUIElement.self)
            guard let children = attribute(bar, kAXChildrenAttribute) as? [AXUIElement] else { continue }
            for child in children {
                let title = attribute(child, kAXTitleAttribute) as? String
                let description = attribute(child, kAXDescriptionAttribute) as? String
                let name = [title, description].compactMap { $0 }.first { !$0.isEmpty } ?? app.localizedName ?? "項目"
                var point = CGPoint.zero
                if let value = attribute(child, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgPoint, &point)
                }
                var size = CGSize.zero
                if let value = attribute(child, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                    AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size)
                }
                result.append(Entry(element: child, name: name, app: app, frame: CGRect(origin: point, size: size)))
            }
        }
        return result.sorted { $0.x < $1.x }
    }

    @objc func show() {
        guard !opening else { return }
        guard AXIsProcessTrusted() else { permission(); return }
        opening = true
        defer { opening = false }
        entries = discover()
        guard let screen = screenUnderMouse() ?? NSScreen.main else { return }
        let left = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
        let width = screen.frame.maxX - left
        let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        overlayFrame = NSRect(x: left, y: screen.frame.maxY - height, width: width, height: height)
        panel.setFrame(overlayFrame, display: false)
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        content.material = .menu
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = height / 2
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "標準メニューバーに戻る")!, target: self, action: #selector(hide))
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.frame = NSRect(x: width - 24, y: (height - 20) / 2, width: 20, height: 20)
        close.toolTip = "標準メニューバーに戻る"
        content.addSubview(close)
        let quitButton = NSButton(title: "終了", target: self, action: #selector(quit))
        quitButton.isBordered = false
        quitButton.font = .systemFont(ofSize: 11, weight: .medium)
        quitButton.frame = NSRect(x: width - 72, y: (height - 24) / 2, width: 44, height: 24)
        quitButton.toolTip = "NotchScrollを終了"
        quitButton.setAccessibilityLabel("NotchScrollを終了")
        content.addSubview(quitButton)
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width - 78, height: height))
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        let itemWidth: CGFloat = 32
        let document = NSView(frame: NSRect(x: 0, y: 0, width: max(width - 78, CGFloat(entries.count) * itemWidth), height: height))
        itemButtons.removeAll()
        for (index, entry) in entries.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(activate(_:)))
            button.tag = index
            button.image = (originalIcons[entry.key] ?? entry.app.icon)?.copy() as? NSImage
            button.image?.size = NSSize(width: 18, height: 18)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.setAccessibilityLabel(entry.name)
            // Names are shown immediately by the hover panel, without the system tooltip delay.
            button.frame = NSRect(x: CGFloat(index) * itemWidth, y: 0, width: itemWidth, height: height)
            document.addSubview(button)
            itemButtons.append(button)
        }
        if entries.isEmpty {
            let label = NSTextField(labelWithString: "項目なし · 権限を確認してください")
            label.font = .systemFont(ofSize: 11)
            label.frame = NSRect(x: 8, y: (height - 16) / 2, width: max(0, width - 90), height: 16)
            document.addSubview(label)
        }
        scroll.documentView = document
        content.addSubview(scroll)
        panel.contentView = content
        let maximum = max(0, document.frame.width - scroll.contentView.bounds.width)
        scroll.contentView.scroll(to: NSPoint(x: min(maximum, savedOffset ?? maximum), y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        panel.orderFrontRegardless()
        pointerLeftAt = nil
        updateHoverName()
    }

    func updateHoverName() {
        guard panel.isVisible, let document = scroll.documentView else { namePanel.orderOut(nil); return }
        let mouse = NSEvent.mouseLocation
        let clipFrame = panel.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        guard clipFrame.contains(mouse),
              let button = itemButtons.first(where: {
                  panel.convertToScreen(document.convert($0.frame, to: nil)).contains(mouse)
              }), entries.indices.contains(button.tag) else { namePanel.orderOut(nil); return }
        let entry = entries[button.tag]
        let appName = entry.app.localizedName ?? entry.name
        let text = appName == entry.name ? appName : "\(appName) — \(entry.name)"
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        let screen = panel.screen ?? NSScreen.main
        let width = min(label.frame.width + 24, min(420, (screen?.frame.width ?? 440) - 20))
        let itemFrame = panel.convertToScreen(document.convert(button.frame, to: nil))
        let minX = screen?.frame.minX ?? overlayFrame.minX
        let maxX = screen?.frame.maxX ?? overlayFrame.maxX
        let x = max(minX + 6, min(maxX - width - 6, itemFrame.midX - width / 2))
        // AppKit may adjust the main panel's requested frame. Anchor to its displayed
        // content instead of overlayFrame, which only records the requested position.
        let displayedBar = panel.convertToScreen(panel.contentView?.bounds ?? panel.contentRect(forFrameRect: panel.frame))
        let captionHeight: CGFloat = 26
        let gap: CGFloat = 6
        namePanel.setFrame(NSRect(x: x, y: displayedBar.minY - gap - captionHeight, width: width, height: captionHeight), display: false)
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        label.frame = NSRect(x: 12, y: 5, width: width - 24, height: 16)
        background.addSubview(label)
        namePanel.contentView = background
        namePanel.orderFrontRegardless()
    }

    @objc func captureIcons() {
        guard AXIsProcessTrusted() else { permission(); return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = "画面収録の許可後、もう一度お試しください"
            alert.informativeText = "表示中のメニューバーからアイコン画像を取得します。画像はメモリ内でのみ使用します。必要ならアプリを再起動してください。"
            alert.runModal()
            return
        }
        hide()
        guard let screen = screenUnderMouse() ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let frame = screen.frame
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        let axScreen = CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
        let items = discover()
        Task { @MainActor in
            do {
                // Let the status menu disappear before sampling the original menu bar.
                try await Task.sleep(nanoseconds: 250_000_000)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                config.showsCursor = false
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let sx = CGFloat(image.width) / frame.width
                let sy = CGFloat(image.height) / frame.height
                let safeLeft = screen.auxiliaryTopRightArea?.minX ?? frame.midX
                var icons: [String: NSImage] = [:]
                for entry in items {
                    let rect = entry.frame
                    guard rect.width > 0, rect.height > 0,
                          rect.minX >= safeLeft, rect.maxX <= axScreen.maxX,
                          rect.minY >= axScreen.minY,
                          rect.maxY <= axScreen.minY + max(40, screen.safeAreaInsets.top) else { continue }
                    let crop = CGRect(x: (rect.minX - axScreen.minX) * sx, y: (rect.minY - axScreen.minY) * sy, width: rect.width * sx, height: rect.height * sy)
                    if let part = image.cropping(to: crop) {
                        icons[entry.key] = NSImage(cgImage: part, size: rect.size)
                    }
                }
                self.originalIcons = icons
                self.show()
            } catch {
                let alert = NSAlert()
                alert.messageText = "元アイコンを取得できませんでした"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @objc func activate(_ sender: NSButton) {
        guard entries.indices.contains(sender.tag) else { return }
        let entry = entries[sender.tag]
        hide()
        let result = AXUIElementPerformAction(entry.element, kAXPressAction as CFString)
        if result != .success && result != .cannotComplete {
            let alert = NSAlert()
            alert.messageText = "この項目のメニューを開けませんでした"
            alert.informativeText = "\(entry.name) はアクセシビリティ経由の操作に対応していない可能性があります（\(result.rawValue)）。"
            alert.runModal()
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
