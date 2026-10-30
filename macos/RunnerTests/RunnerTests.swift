import Cocoa
import FlutterMacOS
import XCTest
import WebKit
@testable import tronclass

class RunnerTests: XCTestCase {

  // Run with WEBVIEW_PROBE and FLUTTER_TARGET=test/support/webview_interaction_probe.dart.
  @MainActor
  func testPhoneFrameAllowsNativeWebViewInteraction() async throws {
#if WEBVIEW_PROBE
    func findWebView(_ view: NSView) -> WKWebView? {
      if let web = view as? WKWebView { return web }
      return view.subviews.lazy.compactMap { findWebView($0) }.first
    }
    let window = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow })
    let content = try XCTUnwrap(window.contentView)
    var webView: WKWebView?
    for _ in 0..<100 {
      if let web = findWebView(content),
         (try? await web.evaluateJavaScript("window.probeReady")) as? Bool == true {
        webView = web
        break
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
    let web = try XCTUnwrap(webView, "Local HTML fixture must finish loading")
    let flutter = try XCTUnwrap(window.contentViewController as? FlutterViewController)
    let probe = FlutterMethodChannel(name: "tronclass/probe", binaryMessenger: flutter.engine.binaryMessenger)
    func frameCount() async -> Int {
      await withCheckedContinuation { continuation in
        probe.invokeMethod("frameCount", arguments: nil) { value in
          continuation.resume(returning: (value as? NSNumber)?.intValue ?? -1)
        }
      }
    }
    let original = window.frame
    defer { window.setFrame(original, display: true) }
    for height in [content.bounds.height, 656] {
      window.setContentSize(NSSize(width: height * (446 * 1.56) / (938 * 1.44), height: height))
      try await Task.sleep(nanoseconds: 700_000_000)
      let before = await frameCount()
      try await Task.sleep(nanoseconds: 1_000_000_000)
      let after = await frameCount()
      XCTAssertGreaterThanOrEqual(before, 0)
      XCTAssertLessThanOrEqual(after - before, 2,
        "Native ripple animation must not continuously recompose WKWebView tracking layers")
      let origin = web.convert(NSPoint.zero, to: content)
      let unit = web.convert(NSPoint(x: 100, y: 100), to: content)
      XCTAssertEqual(abs(unit.x - origin.x), 100, accuracy: 0.01,
        "Web content and window must use the same horizontal coordinate scale")
      XCTAssertEqual(abs(unit.y - origin.y), 100, accuracy: 0.01,
        "Web content and window must use the same vertical coordinate scale")
      let webLayer = try XCTUnwrap(web.layer)
      let paintedOrigin = webLayer.convert(CGPoint.zero, to: content.layer)
      let paintedUnit = webLayer.convert(CGPoint(x: 100, y: 100), to: content.layer)
      XCTAssertEqual(abs(paintedUnit.x - paintedOrigin.x), abs(unit.x - origin.x), accuracy: 0.01,
        "Painted horizontal distance must match native mouse coordinates")
      XCTAssertEqual(abs(paintedUnit.y - paintedOrigin.y), abs(unit.y - origin.y), accuracy: 0.01,
        "Painted vertical distance must match native mouse coordinates")
      for element in ["tap", "input"] {
        let point = try await web.evaluateJavaScript("""
          (() => { const r=document.getElementById('\(element)').getBoundingClientRect();
          return {x:r.x+r.width/2,y:r.y+r.height/2}; })()
          """) as! [String: Double]
        let y = web.isFlipped ? point["y"]! : web.bounds.height - point["y"]!
        let target = web.convert(NSPoint(x: point["x"]!, y: y), to: content.superview)
        let hit = content.hitTest(target)
        XCTAssertTrue(hit === web || hit?.isDescendant(of: web) == true,
          "\(element) at window height \(height) hit \(String(describing: hit)) instead of WKWebView")
      }
    }
#else
    throw XCTSkip("Run the isolated local HTML probe variant to test native hit routing")
#endif
  }

  func testGlassIsClearBehindFlutterAndDoesNotCaptureMouse() throws {
    guard #available(macOS 26.0, *) else { throw XCTSkip("Native glass requires macOS 26") }
    let window = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)
    let content = try XCTUnwrap(window.contentView)
    let glass = try XCTUnwrap(window.phoneGlassView as? NSGlassEffectView)
    XCTAssertEqual(glass.style, .clear)
    XCTAssertNil(glass.tintColor)
    let ripples = glass.contentView?.layer?.sublayers ?? []
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      XCTAssertTrue(ripples.isEmpty)
    } else {
      XCTAssertEqual(ripples.count, 3)
      for ripple in ripples {
        let animation = try XCTUnwrap(ripple.animation(forKey: "ripple") as? CAAnimationGroup)
        XCTAssertEqual(animation.duration, 8)
        XCTAssertEqual(animation.animations?.count, 2)
      }
    }
    XCTAssertNil(glass.hitTest(NSPoint(x: glass.bounds.midX, y: glass.bounds.midY)))
    let siblings = try XCTUnwrap(content.superview?.subviews)
    XCTAssertLessThan(try XCTUnwrap(siblings.firstIndex(of: glass)), try XCTUnwrap(siblings.firstIndex(of: content)))
    let scale = min(content.bounds.width / (446 * 1.56 / 1.44), content.bounds.height / 938)
    XCTAssertEqual(glass.frame.width, (446 * 1.56 / 1.44 - 24) * scale, accuracy: 0.01)
    XCTAssertEqual(glass.frame.height, 894 * scale, accuracy: 0.01)
  }

  func testDynamicIslandAndExpandedHeaderReceiveNativeDragEvents() throws {
    let window = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)
    let content = try XCTUnwrap(window.contentView)
    let parent = try XCTUnwrap(content.superview)
    let drag = try XCTUnwrap(window.phoneDragView)
    let scale = min(content.bounds.width / (446 * 1.56 / 1.44), content.bounds.height / 938)
    // Island top = display inset 42 + status inset 12; island size = 98 x 30.
    for dx in [-40.0, 0, 40.0] {
      for top in [56.0, 69.0, 82.0, 125.0] {
        let y = content.isFlipped ? top * scale : content.bounds.height - top * scale
        let point = content.convert(NSPoint(x: content.bounds.midX + dx * scale, y: y), to: parent)
        XCTAssertTrue(parent.hitTest(point) === drag, "Island and header must receive native mouse-down directly")
      }
    }
    XCTAssertTrue(drag.acceptsFirstMouse(for: nil))
    XCTAssertFalse(drag.mouseDownCanMoveWindow)
    XCTAssertEqual(drag.frame.height, 138 * scale, accuracy: 0.01)
    let bodyY = content.isFlipped ? 150 * scale : content.bounds.height - 150 * scale
    let bodyPoint = content.convert(NSPoint(x: content.bounds.midX, y: bodyY), to: parent)
    XCTAssertFalse(parent.hitTest(bodyPoint) === drag, "Native drag region must not cover page controls")
  }

  func testTrafficLightsOccupyFormerClockAreaAndReceiveClicks() throws {
    let window = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow } as? MainFlutterWindow)
    let content = try XCTUnwrap(window.contentView)
    XCTAssertEqual(window.phoneWindowButtons.count, 3)
    let scale = min(content.bounds.width / (446 * 1.56 / 1.44), content.bounds.height / 938)
    for (index, button) in window.phoneWindowButtons.enumerated() {
      XCTAssertTrue(button.superview === content.superview)
      XCTAssertFalse(button.isHidden)
      XCTAssertTrue(button.isEnabled)
      XCTAssertNotNil(button.action)
      let frame = content.convert(button.frame, from: button.superview)
      XCTAssertEqual(frame.minX, 51 * scale + CGFloat(index) * 20, accuracy: 1)
      let top = content.isFlipped ? frame.midY : content.bounds.height - frame.midY
      XCTAssertEqual(top, 70 * scale, accuracy: 1)
      XCTAssertTrue(button.superview?.hitTest(NSPoint(x: button.frame.midX, y: button.frame.midY)) === button)
      XCTAssertTrue(button.isAccessibilityElement())
    }
  }

  func testLaunchedWindowAndFlutterViewMatchPhoneSize() throws {
    let window = try XCTUnwrap(NSApp.windows.first { $0 is MainFlutterWindow })
    let screen = try XCTUnwrap(window.screen)
    let expected = MainFlutterWindow.phoneWindowSize(available: screen.visibleFrame.size)
    let content = try XCTUnwrap(window.contentView)
    let flutter = try XCTUnwrap(window.contentViewController?.view)
    XCTAssertEqual(content.bounds.width, expected.width, accuracy: 1)
    XCTAssertEqual(content.bounds.height, expected.height, accuracy: 1)
    XCTAssertEqual(flutter.bounds.width, content.bounds.width, accuracy: 1)
    XCTAssertEqual(flutter.bounds.height, content.bounds.height, accuracy: 1)
  }

  func testPhoneWindowUsesRequestedScaleOnLargeScreen() {
    let size = MainFlutterWindow.phoneWindowSize(available: NSSize(width: 2000, height: 1600))
    XCTAssertEqual(size.width, 446 * 1.56 * 0.81, accuracy: 0.001)
    XCTAssertEqual(size.height, 938 * 1.44 * 0.81, accuracy: 0.001)
  }

  func testPhoneWindowFitsSmallScreenWithoutDistortion() {
    for available in [NSSize(width: 1470, height: 837), NSSize(width: 350, height: 900)] {
      let size = MainFlutterWindow.phoneWindowSize(available: available)
      XCTAssertLessThanOrEqual(size.width, available.width - 16 + 0.001)
      XCTAssertLessThanOrEqual(size.height, available.height - 16 + 0.001)
      XCTAssertEqual(size.width / size.height, (446 * 1.56) / (938 * 1.44), accuracy: 0.000001)
      let previousHeight = min(938 * 1.2, available.height - 16,
        (available.width - 16) * (938 * 1.2) / (446 * 1.56))
      XCTAssertEqual(size.height, previousHeight * 0.81 * 1.2, accuracy: 0.001)
      XCTAssertEqual(size.width, previousHeight * (446 * 1.56) / (938 * 1.2) * 0.81, accuracy: 0.001)
    }
  }

  private func png(gray: UInt8) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24,
      pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.bitmapData!.initialize(repeating: gray, count: bitmap.bytesPerRow * 24)
    return bitmap.representation(using: .png, properties: [:])!
  }

  func testCopiedFileTakesPrecedenceOverFinderPreview() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    defer { try? FileManager.default.removeItem(at: file) }
    let original = png(gray: 255)
    try original.write(to: file)
    let item = NSPasteboardItem()
    item.setString(file.absoluteString, forType: .fileURL)
    item.setData(png(gray: 0), forType: .png)
    board.writeObjects([item])
    XCTAssertEqual(try MainFlutterWindow.readClipboardImage(from: board), original)
  }

  func testScreenshotPNGIsPreserved() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let original = png(gray: 128)
    board.setData(original, forType: .png)
    XCTAssertEqual(try MainFlutterWindow.readClipboardImage(from: board), original)
  }

  func testTIFFIsConvertedWithoutResizing() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let bitmap = NSBitmapImageRep(data: png(gray: 128))!
    board.setData(bitmap.tiffRepresentation!, forType: .tiff)
    let output = try XCTUnwrap(MainFlutterWindow.readClipboardImage(from: board))
    let decoded = try XCTUnwrap(NSBitmapImageRep(data: output))
    XCTAssertEqual(decoded.pixelsWide, 24)
    XCTAssertEqual(decoded.pixelsHigh, 24)
    XCTAssertEqual(decoded.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)?.redComponent,
                   bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)?.redComponent)
  }

  func testTextDoesNotBecomeAnImage() throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("not an image", forType: .string)
    XCTAssertNil(try MainFlutterWindow.readClipboardImage(from: board))
  }

  func testUnreadableFileDoesNotFallBackToIcon() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let item = NSPasteboardItem()
    item.setString("file:///nonexistent/\(UUID().uuidString).png", forType: .fileURL)
    item.setData(png(gray: 0), forType: .png)
    board.writeObjects([item])
    XCTAssertThrowsError(try MainFlutterWindow.readClipboardImage(from: board))
  }

  func testMultipleFilesAreRejected() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.writeObjects([URL(fileURLWithPath: "/tmp/one.png") as NSURL,
                        URL(fileURLWithPath: "/tmp/two.png") as NSURL])
    XCTAssertThrowsError(try MainFlutterWindow.readClipboardImage(from: board))
  }

}
