import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private(set) var phoneWindowButtons: [NSButton] = []
  private(set) var phoneGlassView: NSView?
  private(set) var phoneDragView: NSView?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.isOpaque = false
    self.backgroundColor = .clear
    flutterViewController.backgroundColor = .clear
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.hasShadow = false
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let clipboardChannel = FlutterMethodChannel(
      name: "tronclass/clipboard_image",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    clipboardChannel.setMethodCallHandler { call, result in
      guard call.method == "readImage" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let data = try Self.readClipboardImage(from: .general)
        result(data.map { FlutterStandardTypedData(bytes: $0) })
      } catch {
        result(FlutterError(code: "clipboard_read_failed",
                            message: "无法读取复制的图片，请只复制一张图片，或使用选择图片入口。",
                            details: nil))
      }
    }

    super.awakeFromNib()

    let ratio = NSSize(width: 446 * 1.56, height: 938 * 1.44)
    let available = (screen ?? NSScreen.main)?.visibleFrame.size ?? ratio
    contentAspectRatio = ratio
    contentMinSize = NSSize(width: 656 * 0.81 * ratio.width / ratio.height, height: 656 * 0.81)
    setContentSize(Self.phoneWindowSize(available: available))
    center()

    if #available(macOS 26.0, *), let content = contentView {
      let glass = PhoneGlassView()
      glass.style = .clear
      glass.tintColor = nil
      content.superview?.addSubview(glass, positioned: .below, relativeTo: content)
      phoneGlassView = glass
    }

    let dragView = PhoneWindowDragView()
    dragView.setAccessibilityElement(true)
    dragView.setAccessibilityRole(.group)
    dragView.setAccessibilityLabel("拖动窗口")
    contentView?.superview?.addSubview(dragView, positioned: .above, relativeTo: contentView)
    phoneDragView = dragView

    let controls: [(NSWindow.ButtonType, Selector, String)] = [
      (.closeButton, #selector(NSWindow.performClose(_:)), "关闭窗口"),
      (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:)), "最小化窗口"),
      (.zoomButton, #selector(NSWindow.toggleFullScreen(_:)), "切换全屏"),
    ]
    for (type, action, label) in controls {
      standardWindowButton(type)?.isHidden = true
      guard let button = NSWindow.standardWindowButton(type, for: styleMask) else { continue }
      button.target = self
      button.action = action
      button.setAccessibilityElement(true)
      button.setAccessibilityRole(.button)
      button.setAccessibilityLabel(label)
      phoneWindowButtons.append(button)
      // Keep native controls outside Flutter's custom accessibility subtree.
      contentView?.superview?.addSubview(button)
    }
    layoutPhoneChrome()
    NotificationCenter.default.addObserver(self, selector: #selector(layoutPhoneChrome),
      name: NSWindow.didResizeNotification, object: self)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(layoutPhoneChrome),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }

  @objc private func layoutPhoneChrome() {
    guard let content = contentView else { return }
    let scale = min(content.bounds.width / (446 * 1.56 / 1.44), content.bounds.height / 938)
    let left = (content.bounds.width - (446 * 1.56 / 1.44) * scale) / 2 + 51 * scale
    let top = (content.bounds.height - 938 * scale) / 2 + 70 * scale
    if let dragView = phoneDragView {
      let height = 138 * scale
      let inset = (content.bounds.height - 938 * scale) / 2
      let y = content.isFlipped ? inset : content.bounds.height - inset - height
      dragView.frame = content.convert(
        NSRect(x: 0, y: y, width: content.bounds.width, height: height), to: dragView.superview)
    }
    if #available(macOS 26.0, *), let glass = phoneGlassView as? PhoneGlassView {
      let width = (446 * 1.56 / 1.44 - 24) * scale
      let height = 894 * scale
      let x = (content.bounds.width - width) / 2
      let topInset = (content.bounds.height - 938 * scale) / 2 + 32 * scale
      let y = content.isFlipped ? topInset : content.bounds.height - topInset - height
      glass.frame = content.convert(NSRect(x: x, y: y, width: width, height: height), to: glass.superview)
      glass.cornerRadius = 62 * scale
      glass.updateRipples(scale: scale)
    }
    for (index, button) in phoneWindowButtons.enumerated() {
      let origin = NSPoint(x: left + CGFloat(index) * 20,
        y: content.isFlipped ? top - button.frame.height / 2 : content.bounds.height - top - button.frame.height / 2)
      button.setFrameOrigin(content.convert(origin, to: button.superview))
    }
  }

  static func phoneWindowSize(available: NSSize) -> NSSize {
    // Preserve the current width and grow height by 20%; 0.81 * 1.2 still fits the screen.
    let target = NSSize(width: 446 * 1.56, height: 938 * 1.2)
    let scale = min(1, (available.width - 16) / target.width, (available.height - 16) / target.height)
    return NSSize(width: target.width * scale * 0.81, height: target.height * scale * 0.81 * 1.2)
  }

  static func readClipboardImage(from pasteboard: NSPasteboard) throws -> Data? {
    // Finder also supplies a file preview; decode the original file, not its icon.
    let files = pasteboard.readObjects(forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    if !files.isEmpty {
      guard files.count == 1 else {
        throw CocoaError(.fileReadUnsupportedScheme)
      }
      let file = files[0]
      let scoped = file.startAccessingSecurityScopedResource()
      defer { if scoped { file.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: file)
      guard NSBitmapImageRep(data: data) != nil else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return data
    }
    if let png = pasteboard.data(forType: .png) {
      return png
    }
    if let tiff = pasteboard.data(forType: .tiff),
       let bitmap = NSBitmapImageRep(data: tiff) {
      return bitmap.representation(using: .png, properties: [:])
    }
    return nil
  }

}

// Decorative glass must never compete with Flutter or WebView for mouse events.
@available(macOS 26.0, *)
private class PhoneGlassView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func updateRipples(scale: CGFloat) {
    if contentView == nil {
      let surface = NSView(frame: bounds)
      surface.wantsLayer = true
      contentView = surface
    }
    guard let surface = contentView, let root = surface.layer else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    surface.frame = bounds
    root.sublayers?.forEach { $0.removeFromSuperlayer() }
    defer { CATransaction.commit() }
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    // Core Animation keeps the ripple off Flutter's platform-view composition loop.
    for index in 0..<3 {
      let ripple = CAShapeLayer()
      ripple.name = "phone-ripple"
      ripple.fillColor = nil
      ripple.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
      ripple.lineWidth = 0.8 * scale
      ripple.opacity = 0
      let path = CABasicAnimation(keyPath: "path")
      path.fromValue = CGPath(roundedRect: bounds.insetBy(dx: 9 * scale, dy: 9 * scale),
        cornerWidth: 53 * scale, cornerHeight: 53 * scale, transform: nil)
      path.toValue = CGPath(roundedRect: bounds.insetBy(dx: scale, dy: scale),
        cornerWidth: 61 * scale, cornerHeight: 61 * scale, transform: nil)
      let fade = CAKeyframeAnimation(keyPath: "opacity")
      fade.values = [0, 1, 0]
      fade.keyTimes = [0, 0.5, 1]
      path.duration = 8
      fade.duration = 8
      let wave = CAAnimationGroup()
      wave.animations = [path, fade]
      wave.duration = 8
      wave.repeatCount = .infinity
      wave.timeOffset = Double(index) * 8 / 3
      root.addSublayer(ripple)
      ripple.add(wave, forKey: "ripple")
    }
  }
}

private class PhoneWindowDragView: NSView {
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    // Preserve the actual mouse-down event instead of looking it up after a Dart round trip.
    window?.performDrag(with: event)
  }
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }
}
