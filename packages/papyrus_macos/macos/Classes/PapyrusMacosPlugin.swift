import Cocoa
import FlutterMacOS
import WebKit

private struct PapyrusMacosInlineResource {
  let data: Data
  let mimeType: String
  let statusCode: Int
  let headers: [String: String]
}

private enum PapyrusMacosResourceDecision {
  case allow
  case block
  case respond(PapyrusMacosInlineResource)
}

private let papyrusSelectedTextScript = "(function(){var selection = window.getSelection ? window.getSelection().toString() : ''; return selection ? encodeURIComponent(selection) : null;})()"

public class PapyrusMacosPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
  private var channel: FlutterMethodChannel?
  private weak var flutterView: NSView?
  private var overlayContainer: NSView?
  private var webView: WKWebView?
  private var currentConfiguration: [String: Any] = [:]
  private var appInitiatedNavigationURLs = Set<String>()
  private var navigationResolverEnabled = false
  private var pendingLoad: [String: Any]?
  private var pendingViewport: [String: Any]?
  private var resourceResolverEnabled = false
  private var virtualResources: [String: PapyrusMacosInlineResource] = [:]
  private var virtualResourceScheme = "papyrus-resource"
  private var cancelledResourceTasks = Set<ObjectIdentifier>()
  private lazy var schemeHandler = PapyrusMacosSchemeHandler(plugin: self)

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
      let request = call.arguments as? [String: Any] ?? [:]
      guard isLoadAllowed(request) else {
        result(
          FlutterError(
            code: "navigationBlocked",
            message: "File loading is disabled by the current Papyrus security policy.",
            details: request["absolutePath"] ?? request["uri"]
          )
        )
        return
      }
      load(request: request)
      result(nil)
    case "setNavigationResolverEnabled":
      navigationResolverEnabled = call.arguments as? Bool ?? false
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
    case "selectedText":
      webView?.evaluateJavaScript(papyrusSelectedTextScript) { value, error in
        if let error = error {
          result(FlutterError(code: "papyrus_macos", message: error.localizedDescription, details: nil))
        } else {
          result((value as? String)?.isEmpty == true ? nil : value)
        }
      } ?? result(nil)
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
    case "setResourceResolverEnabled":
      resourceResolverEnabled = call.arguments as? Bool ?? false
      result(nil)
    case "dispose":
      currentConfiguration.removeAll()
      appInitiatedNavigationURLs.removeAll()
      pendingLoad = nil
      pendingViewport = nil
      webView?.removeFromSuperview()
      webView = nil
      overlayContainer?.removeFromSuperview()
      overlayContainer = nil
      virtualResources.removeAll()
      cancelledResourceTasks.removeAll()
      resourceResolverEnabled = false
      result(nil)
    case "getCapabilities":
      result(capabilities())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @discardableResult
  fileprivate func createWebView(config: [String: Any]) -> WKWebView {
    currentConfiguration = config
    virtualResourceScheme = sanitizeCustomScheme(config["virtualResourceScheme"] as? String)
    navigationResolverEnabled = config["navigationResolverEnabled"] as? Bool ?? navigationResolverEnabled
    resourceResolverEnabled = config["resourceResolverEnabled"] as? Bool ?? resourceResolverEnabled
    let webConfig = WKWebViewConfiguration()
    if config["ephemeral"] as? Bool == true {
      webConfig.websiteDataStore = .nonPersistent()
    }
    if let scheme = registeredVirtualResourceScheme {
      webConfig.setURLSchemeHandler(schemeHandler, forURLScheme: scheme)
    }
    if #available(macOS 11.0, *) {
      let preferences = WKWebpagePreferences()
      preferences.allowsContentJavaScript = config["allowJavaScript"] as? Bool == true
      webConfig.defaultWebpagePreferences = preferences
    } else {
      webConfig.preferences.javaScriptEnabled = config["allowJavaScript"] as? Bool == true
    }
    webConfig.preferences.javaScriptCanOpenWindowsAutomatically = config["allowPopups"] as? Bool == true
    if #available(macOS 10.12.4, *) {
      webConfig.mediaTypesRequiringUserActionForPlayback =
        config["requireMediaUserGesture"] as? Bool != false ? .all : []
    }
    let view = PapyrusMacosTrackingWebView(frame: .zero, configuration: webConfig)
    view.onDidMoveToWindow = { [weak self] in
      self?.runPendingLoadIfNeeded()
    }
    view.navigationDelegate = self
    view.uiDelegate = self
    if let userAgent = config["userAgent"] as? String, !userAgent.isEmpty {
      view.customUserAgent = userAgent
    }
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
    updateVirtualResources(from: request)
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
        markAppInitiatedNavigation(url)
        view.load(URLRequest(url: url))
      } else {
        if let base {
          markAppInitiatedNavigation(base)
        }
        view.loadHTMLString(html, baseURL: base)
      }
    case "uri":
      if let value = request["uri"] as? String, let url = URL(string: value) {
        markAppInitiatedNavigation(url)
        view.load(URLRequest(url: url))
      }
    case "file":
      if let path = request["absolutePath"] as? String {
        let url = URL(fileURLWithPath: path)
        markAppInitiatedNavigation(url)
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
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }

    if navigationAction.targetFrame?.isMainFrame != false,
      consumeAppInitiatedNavigation(url)
    {
      decisionHandler(.allow)
      return
    }

    let fallbackDecision = navigationDecision(
      for: url,
      isMainFrame: navigationAction.targetFrame?.isMainFrame ?? false,
      hasUserGesture: navigationHasUserGesture(navigationAction)
    )

    guard navigationResolverEnabled, let channel else {
      applyNavigationDecision(fallbackDecision, for: url, decisionHandler: decisionHandler)
      return
    }

    channel.invokeMethod(
      "navigationRequest",
      arguments: navigationArguments(for: navigationAction)
    ) { [weak self] result in
      let decision = self?.navigationDecision(from: result, fallback: fallbackDecision) ?? fallbackDecision
      self?.applyNavigationDecision(decision, for: url, decisionHandler: decisionHandler)
    }
  }

  public func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard currentConfiguration["allowPopups"] as? Bool == true else {
      return nil
    }
    guard let url = navigationAction.request.url else {
      return nil
    }
    webView.load(URLRequest(url: url))
    return nil
  }

  fileprivate func startSchemeTask(_ task: WKURLSchemeTask) {
    let identifier = ObjectIdentifier(task as AnyObject)
    cancelledResourceTasks.remove(identifier)

    guard let url = task.request.url else {
      fail(task: task, description: "Missing resource URL.")
      return
    }

    if let resource = virtualResources[url.absoluteString] {
      respond(to: task, with: resource, url: url)
      return
    }

    guard resourceResolverEnabled, let channel else {
      fail(task: task, description: "Papyrus resource not found.", notFound: true)
      return
    }

    channel.invokeMethod("resourceRequest", arguments: resourceArguments(for: task)) { [weak self] result in
      self?.complete(task: task, url: url, result: result)
    }
  }

  fileprivate func stopSchemeTask(_ task: WKURLSchemeTask) {
    cancelledResourceTasks.insert(ObjectIdentifier(task as AnyObject))
  }

  private func complete(task: WKURLSchemeTask, url: URL, result: Any?) {
    let identifier = ObjectIdentifier(task as AnyObject)
    guard cancelledResourceTasks.remove(identifier) == nil else { return }

    switch resourceDecision(from: result) {
    case .respond(let resource):
      respond(to: task, with: resource, url: url)
    case .allow:
      fail(task: task, description: "Papyrus resource not found.", notFound: true)
    case .block:
      fail(task: task, description: "Papyrus resource blocked.")
    }
  }

  private func respond(to task: WKURLSchemeTask, with resource: PapyrusMacosInlineResource, url: URL) {
    let identifier = ObjectIdentifier(task as AnyObject)
    guard !cancelledResourceTasks.contains(identifier) else { return }

    let response = httpResponse(for: url, resource: resource) ?? URLResponse(
      url: url,
      mimeType: resource.mimeType,
      expectedContentLength: resource.data.count,
      textEncodingName: textEncodingName(for: resource.mimeType)
    )
    task.didReceive(response)
    task.didReceive(resource.data)
    task.didFinish()
  }

  private func fail(task: WKURLSchemeTask, description: String, notFound: Bool = false) {
    let identifier = ObjectIdentifier(task as AnyObject)
    guard cancelledResourceTasks.remove(identifier) == nil else { return }

    let code = notFound ? NSFileReadUnknownError : NSFileReadNoPermissionError
    task.didFailWithError(
      NSError(
        domain: NSCocoaErrorDomain,
        code: code,
        userInfo: [NSLocalizedDescriptionKey: description]
      )
    )
  }

  private func resourceArguments(for task: WKURLSchemeTask) -> [String: Any] {
    let request = task.request
    let url = request.url?.absoluteString ?? ""
    let headers = request.allHTTPHeaderFields ?? [:]
    return [
      "uri": url,
      "method": request.httpMethod ?? "GET",
      "headers": headers,
      "resourceType": resourceType(for: request),
      "isMainFrame": request.mainDocumentURL == request.url,
    ]
  }

  private func resourceType(for request: URLRequest) -> String {
    let accept = request.allHTTPHeaderFields?["Accept"]?.lowercased() ?? ""
    let path = request.url?.path.lowercased() ?? ""
    switch true {
    case request.mainDocumentURL == request.url:
      return "document"
    case accept.contains("text/css") || path.hasSuffix(".css"):
      return "stylesheet"
    case accept.contains("image/") || path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") || path.hasSuffix(".gif") || path.hasSuffix(".svg") || path.hasSuffix(".webp"):
      return "image"
    case accept.contains("font/") || path.hasSuffix(".woff") || path.hasSuffix(".woff2") || path.hasSuffix(".ttf"):
      return "font"
    case accept.contains("javascript") || path.hasSuffix(".js"):
      return "script"
    case accept.contains("video/") || accept.contains("audio/"):
      return "media"
    default:
      return "other"
    }
  }

  private func resourceDecision(from result: Any?) -> PapyrusMacosResourceDecision {
    guard
      let map = result as? [String: Any],
      let decision = map["decision"] as? String
    else {
      return .block
    }

    switch decision {
    case "allow":
      return .allow
    case "respond":
      guard let response = inlineResource(from: map["response"] as? [String: Any]) else {
        return .block
      }
      return .respond(response)
    default:
      return .block
    }
  }

  private func updateVirtualResources(from request: [String: Any]) {
    virtualResources.removeAll()
    guard let resources = request["virtualResources"] as? [[String: Any]] else {
      return
    }

    for resource in resources {
      guard let uri = resource["uri"] as? String, let inline = inlineResource(from: resource) else {
        continue
      }
      virtualResources[uri] = inline
    }
  }

  private func inlineResource(from map: [String: Any]?) -> PapyrusMacosInlineResource? {
    guard let map else { return nil }
    let bytes = (map["bytes"] as? [Int] ?? []).compactMap(UInt8.init(exactly:))
    return PapyrusMacosInlineResource(
      data: Data(bytes),
      mimeType: map["mimeType"] as? String ?? "application/octet-stream",
      statusCode: map["statusCode"] as? Int ?? 200,
      headers: map["headers"] as? [String: String] ?? [:]
    )
  }

  private func httpResponse(for url: URL, resource: PapyrusMacosInlineResource) -> HTTPURLResponse? {
    var headers = resource.headers
    if headers["Content-Type"] == nil {
      headers["Content-Type"] = resource.mimeType
    }
    return HTTPURLResponse(
      url: url,
      statusCode: resource.statusCode,
      httpVersion: "HTTP/1.1",
      headerFields: headers
    )
  }

  private func textEncodingName(for mimeType: String) -> String? {
    let lower = mimeType.lowercased()
    if lower.hasPrefix("text/") || lower.contains("json") || lower.contains("javascript") || lower.contains("xml") || lower.contains("svg") {
      return "utf-8"
    }
    return nil
  }

  private var registeredVirtualResourceScheme: String? {
    switch virtualResourceScheme {
    case "http", "https", "file", "about", "data", "blob":
      return nil
    default:
      return virtualResourceScheme
    }
  }

  private func sanitizeCustomScheme(_ scheme: String?) -> String {
    let trimmed = scheme?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed!.lowercased() : "papyrus-resource"
  }

  private func htmlDataURL(for html: String) -> URL? {
    guard let data = html.data(using: .utf8) else {
      return nil
    }
    let base64 = data.base64EncodedString()
    return URL(string: "data:text/html;charset=utf-8;base64,\(base64)")
  }

  private func navigationDecision(
    for url: URL,
    isMainFrame: Bool,
    hasUserGesture: Bool
  ) -> String {
    let scheme = url.scheme?.lowercased() ?? ""
    let blockedSchemes = stringSet(currentConfiguration["navigationBlockedSchemes"])
    if blockedSchemes.contains(scheme) {
      return "block"
    }

    let defaultDecision = currentConfiguration["navigationDefaultDecision"] as? String ?? "block"
    let allowMainFrameNavigation = currentConfiguration["allowMainFrameNavigation"] as? Bool ?? false
    let allowSubFrameNavigation = currentConfiguration["allowSubFrameNavigation"] as? Bool ?? false
    if isMainFrame && !allowMainFrameNavigation {
      return defaultDecision
    }
    if !isMainFrame && !allowSubFrameNavigation {
      return "block"
    }

    let allowedSchemes = stringSet(currentConfiguration["navigationAllowedSchemes"])
    if allowedSchemes.contains(scheme) {
      return "allow"
    }

    let externalSchemes = stringSet(currentConfiguration["navigationExternalSchemes"])
    if externalSchemes.contains(scheme) {
      let requireUserGesture = currentConfiguration["requireUserGestureForExternalOpen"] as? Bool ?? true
      if requireUserGesture && !hasUserGesture {
        return "block"
      }
      return "openExternally"
    }

    return defaultDecision
  }

  private func navigationDecision(from result: Any?, fallback: String) -> String {
    guard let map = result as? [String: Any], let decision = map["decision"] as? String else {
      return fallback
    }
    return decision
  }

  private func applyNavigationDecision(
    _ decision: String,
    for url: URL,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    switch decision {
    case "allow":
      decisionHandler(.allow)
    case "openExternally":
      NSWorkspace.shared.open(url)
      decisionHandler(.cancel)
    case "download":
      if #available(macOS 11.3, *) {
        decisionHandler(.download)
      } else {
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
      }
    default:
      decisionHandler(.cancel)
    }
  }

  private func navigationArguments(for navigationAction: WKNavigationAction) -> [String: Any] {
    return [
      "uri": navigationAction.request.url?.absoluteString ?? "",
      "isMainFrame": navigationAction.targetFrame?.isMainFrame ?? false,
      "navigationType": navigationType(for: navigationAction).rawValue,
      "hasUserGesture": navigationHasUserGesture(navigationAction),
    ]
  }

  private func navigationHasUserGesture(_ navigationAction: WKNavigationAction) -> Bool {
    switch navigationAction.navigationType {
    case .linkActivated, .formSubmitted, .formResubmitted, .backForward:
      return true
    case .reload, .other:
      return false
    @unknown default:
      return false
    }
  }

  private enum PapyrusMacosNavigationType: String {
    case linkClicked
    case formSubmitted
    case backForward
    case reload
    case programmatic
    case other
  }

  private func navigationType(for navigationAction: WKNavigationAction) -> PapyrusMacosNavigationType {
    switch navigationAction.navigationType {
    case .linkActivated:
      return .linkClicked
    case .formSubmitted, .formResubmitted:
      return .formSubmitted
    case .backForward:
      return .backForward
    case .reload:
      return .reload
    case .other:
      return navigationHasUserGesture(navigationAction) ? .other : .programmatic
    @unknown default:
      return .other
    }
  }

  private func isLoadAllowed(_ request: [String: Any]) -> Bool {
    guard let type = request["type"] as? String else {
      return true
    }
    switch type {
    case "file":
      return currentConfiguration["allowFileAccess"] as? Bool == true
    case "uri":
      guard
        let value = request["uri"] as? String,
        let url = URL(string: value),
        url.isFileURL
      else {
        return true
      }
      return currentConfiguration["allowFileAccess"] as? Bool == true
    default:
      return true
    }
  }

  private func stringSet(_ value: Any?) -> Set<String> {
    guard let values = value as? [String] else {
      return []
    }
    return Set(values.map { $0.lowercased() })
  }

  private func markAppInitiatedNavigation(_ url: URL) {
    appInitiatedNavigationURLs.insert(url.absoluteString)
  }

  private func consumeAppInitiatedNavigation(_ url: URL) -> Bool {
    appInitiatedNavigationURLs.remove(url.absoluteString) != nil
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

private class PapyrusMacosSchemeHandler: NSObject, WKURLSchemeHandler {
  weak var plugin: PapyrusMacosPlugin?

  init(plugin: PapyrusMacosPlugin) {
    self.plugin = plugin
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    plugin?.startSchemeTask(urlSchemeTask)
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    plugin?.stopSchemeTask(urlSchemeTask)
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
