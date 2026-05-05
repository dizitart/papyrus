import Cocoa
import FlutterMacOS
import WebKit

public class PapyrusMacosPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
  private var channel: FlutterMethodChannel?
  private weak var flutterView: NSView?
  private var overlayContainer: NSView?
  private var webView: WKWebView?
  private var pendingLoad: [String: Any]?
  private var pendingViewport: [String: Any]?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.papyrus.papyrus_macos", binaryMessenger: registrar.messenger)
    let instance = PapyrusMacosPlugin()
    instance.channel = channel
    instance.flutterView = registrar.view
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      PapyrusMacosViewFactory(plugin: instance),
      withId: "dev.papyrus.papyrus_macos/webview"
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "create":
      createWebView(config: call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "setViewport":
      setViewport(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "debugOverlayState":
      result(debugOverlayState())
    case "load":
      load(request: call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "reload":
      webView?.reload()
      result(nil)
    case "stopLoading":
      webView?.stopLoading()
      result(nil)
    case "canGoBack":
      result(webView?.canGoBack ?? false)
    case "canGoForward":
      result(webView?.canGoForward ?? false)
    case "goBack":
      if webView?.canGoBack == true { webView?.goBack() }
      result(nil)
    case "goForward":
      if webView?.canGoForward == true { webView?.goForward() }
      result(nil)
    case "currentUri":
      result(webView?.url?.absoluteString)
    case "title":
      result(webView?.title)
    case "estimatedProgress":
      result(webView?.estimatedProgress ?? 0)
    case "evaluateJavaScript":
      webView?.evaluateJavaScript(call.arguments as? String ?? "") { value, error in
        if let error = error {
          result(FlutterError(code: "papyrus_macos", message: error.localizedDescription, details: nil))
        } else {
          result(value)
        }
      }
    case "getContentSize":
      result(["width": webView?.bounds.width ?? 0, "height": webView?.bounds.height ?? 0])
    case "captureSnapshot":
      captureSnapshot(result: result)
    case "printDocument":
      webView?.printView(nil)
      result(nil)
    case "clearCache", "clearStorage":
      WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {}
      result(nil)
    case "dispose":
      pendingLoad = nil
      pendingViewport = nil
      webView?.removeFromSuperview()
      webView = nil
      overlayContainer?.removeFromSuperview()
      overlayContainer = nil
      result(nil)
    case "getCapabilities":
      result(capabilities())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult
  fileprivate func createWebView(config: [String: Any]) -> WKWebView {
    let webConfig = WKWebViewConfiguration()
    if config["ephemeral"] as? Bool == true {
      webConfig.websiteDataStore = .nonPersistent()
    }
    if #available(macOS 11.0, *) {
      let preferences = WKWebpagePreferences()
      preferences.allowsContentJavaScript = config["allowJavaScript"] as? Bool == true
      webConfig.defaultWebpagePreferences = preferences
    } else {
      webConfig.preferences.javaScriptEnabled = config["allowJavaScript"] as? Bool == true
    }
    let view = PapyrusMacosTrackingWebView(frame: .zero, configuration: webConfig)
    view.onDidMoveToWindow = { [weak self] in
      self?.runPendingLoadIfNeeded()
    }
    view.navigationDelegate = self
    view.uiDelegate = self
    if let existingView = webView, existingView !== view {
      existingView.removeFromSuperview()
    }
    webView = view
    if config["desktopOverlay"] as? Bool == true {
      attachOverlayWebView(view)
    }
    applyPendingViewportIfNeeded()
    runPendingLoadIfNeeded()
    return view
  }

  private func attachOverlayWebView(_ view: WKWebView) {
    guard let flutterView else { return }
    let host = flutterView.superview ?? flutterView
    let container = overlayContainer ?? PapyrusMacosOverlayContainer(frame: flutterView.frame)
    container.autoresizingMask = [.width, .height]
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor
    container.frame = flutterView.frame
    if container.superview !== host {
      container.removeFromSuperview()
      host.addSubview(container, positioned: .above, relativeTo: nil)
    }
    overlayContainer = container
    if view.superview !== container {
      view.removeFromSuperview()
      container.addSubview(view)
    }
    view.isHidden = true
  }

  private func setViewport(_ args: [String: Any]) {
    guard let view = webView, let flutterView else {
      pendingViewport = args
      return
    }
    if overlayContainer == nil || view.superview == nil {
      attachOverlayWebView(view)
    }
    overlayContainer?.frame = flutterView.frame
    let x = cgFloat(args["x"])
    let y = cgFloat(args["y"])
    let width = cgFloat(args["width"])
    let height = cgFloat(args["height"])
    let visible = args["visible"] as? Bool ?? false
    view.frame = CGRect(x: x, y: y, width: width, height: height)
    view.isHidden = !visible || width <= 0 || height <= 0
  }

  private func debugOverlayState() -> [String: Any] {
    let frame = webView?.frame ?? .zero
    return [
      "overlayAttached": overlayContainer?.superview != nil,
      "webViewAttached": webView?.superview != nil,
      "visible": webView?.isHidden == false,
      "x": Double(frame.origin.x),
      "y": Double(frame.origin.y),
      "width": Double(frame.width),
      "height": Double(frame.height),
    ]
  }

  private func load(request: [String: Any]) {
    guard let view = webView else {
      pendingLoad = request
      return
    }
    guard view.window != nil else {
      pendingLoad = request
      return
    }
    load(request, into: view)
  }

  private func applyPendingViewportIfNeeded() {
    guard let args = pendingViewport else { return }
    pendingViewport = nil
    setViewport(args)
  }

  private func runPendingLoadIfNeeded() {
    guard let request = pendingLoad, let view = webView, view.window != nil else { return }
    pendingLoad = nil
    load(request, into: view)
  }

  private func load(_ request: [String: Any], into view: WKWebView) {
    switch request["type"] as? String {
    case "html":
      let base = (request["baseUri"] as? String).flatMap(URL.init(string:))
      let html = request["html"] as? String ?? ""
      if base == nil, let url = htmlDataURL(for: html) {
        view.load(URLRequest(url: url))
      } else {
        view.loadHTMLString(html, baseURL: base)
      }
    case "uri":
      if let value = request["uri"] as? String, let url = URL(string: value) {
        view.load(URLRequest(url: url))
      }
    case "file":
      if let path = request["absolutePath"] as? String {
        let url = URL(fileURLWithPath: path)
        view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      }
    default:
      break
    }
  }

  private func captureSnapshot(result: @escaping FlutterResult) {
    guard let view = webView else {
      result(FlutterStandardTypedData(bytes: Data()))
      return
    }
    let configuration = WKSnapshotConfiguration()
    configuration.rect = view.bounds
    configuration.snapshotWidth = NSNumber(value: Double(view.bounds.width))
    view.takeSnapshot(with: configuration) { [weak self] image, error in
      if let image, let data = self?.pngData(from: image), !data.isEmpty {
        result(FlutterStandardTypedData(bytes: data))
      } else if let data = self?.rasterSnapshotData(from: view), !data.isEmpty {
        result(FlutterStandardTypedData(bytes: data))
      } else if let error = error {
        result(FlutterError(code: "papyrus_macos", message: error.localizedDescription, details: nil))
      } else {
        result(FlutterStandardTypedData(bytes: Data()))
      }
    }
  }

  private func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation else { return nil }
    guard let representation = NSBitmapImageRep(data: tiff) else { return tiff }
    return representation.representation(using: .png, properties: [:])
  }

  private func rasterSnapshotData(from view: NSView) -> Data? {
    guard view.bounds.width > 0, view.bounds.height > 0 else { return nil }
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return nil
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    return representation.representation(using: .png, properties: [:])
  }

  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    channel?.invokeMethod("navigationRequest", arguments: navigationAction.request.url?.absoluteString)
    decisionHandler(.allow)
  }

  private func htmlDataURL(for html: String) -> URL? {
    guard let data = html.data(using: .utf8) else {
      return nil
    }
    let base64 = data.base64EncodedString()
    return URL(string: "data:text/html;charset=utf-8;base64,\(base64)")
  }

  private func capabilities() -> [String: Bool] {
    [
      "supportsResourceInterception": true,
      "supportsVirtualSchemes": true,
      "supportsEphemeralStorage": true,
      "supportsPrint": true,
      "supportsSnapshot": true,
      "supportsAutoHeight": true,
      "supportsDarkMode": true,
      "supportsDownloadInterception": true,
      "supportsPermissionInterception": true,
    ]
  }
}

private func cgFloat(_ value: Any?) -> CGFloat {
  if let value = value as? CGFloat { return value }
  if let value = value as? Double { return CGFloat(value) }
  if let value = value as? Int { return CGFloat(value) }
  if let value = value as? NSNumber { return CGFloat(truncating: value) }
  return 0
}

private class PapyrusMacosTrackingWebView: WKWebView {
  var onDidMoveToWindow: (() -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onDidMoveToWindow?()
  }
}

private class PapyrusMacosOverlayContainer: NSView {
  override var isFlipped: Bool { true }
}

private class PapyrusMacosViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: PapyrusMacosPlugin?

  init(plugin: PapyrusMacosPlugin) {
    self.plugin = plugin
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let config = args as? [String: Any] ?? [:]
    return plugin?.createWebView(config: config) ?? NSView(frame: .zero)
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }
}
