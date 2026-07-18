import Flutter
import UIKit
import WebKit

private struct PapyrusIosInlineResource {
  let data: Data
  let mimeType: String
  let statusCode: Int
  let headers: [String: String]
}

private enum PapyrusIosResourceDecision {
  case allow
  case block
  case respond(PapyrusIosInlineResource)
}

private let papyrusSelectedTextScript = "(function(){var selection = window.getSelection ? window.getSelection().toString() : ''; return selection ? encodeURIComponent(selection) : null;})()"

public class PapyrusIosPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
  private var channel: FlutterMethodChannel?
  private var webView: WKWebView?
  private var currentConfiguration: [String: Any] = [:]
  private var appInitiatedNavigationURLs = Set<String>()
  private var navigationResolverEnabled = false
  private var pendingLoad: [String: Any]?
  private var resourceResolverEnabled = false
  private var virtualResources: [String: PapyrusIosInlineResource] = [:]
  private var virtualResourceScheme = "papyrus-resource"
  private var cancelledResourceTasks = Set<ObjectIdentifier>()
  private lazy var schemeHandler = PapyrusIosSchemeHandler(plugin: self)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.papyrus.papyrus_ios", binaryMessenger: registrar.messenger())
    let instance = PapyrusIosPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      PapyrusIosViewFactory(plugin: instance),
      withId: "dev.papyrus.papyrus_ios/webview"
    )
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "create":
      createWebView(config: call.arguments as? [String: Any] ?? [:])
      result(nil)
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
          result(FlutterError(code: "papyrus_ios", message: error.localizedDescription, details: nil))
        } else {
          result(value)
        }
      }
    case "selectedText":
      webView?.evaluateJavaScript(papyrusSelectedTextScript) { value, error in
        if let error = error {
          result(FlutterError(code: "papyrus_ios", message: error.localizedDescription, details: nil))
        } else {
          result((value as? String)?.isEmpty == true ? nil : value)
        }
      } ?? result(nil)
    case "getContentSize":
      result(["width": webView?.scrollView.contentSize.width ?? 0, "height": webView?.scrollView.contentSize.height ?? 0])
    case "captureSnapshot":
      captureSnapshot(result: result)
    case "printDocument":
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
      webView = nil
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
    if #available(iOS 14.0, *) {
      let preferences = WKWebpagePreferences()
      preferences.allowsContentJavaScript = config["allowJavaScript"] as? Bool == true
      webConfig.defaultWebpagePreferences = preferences
    } else {
      webConfig.preferences.javaScriptEnabled = config["allowJavaScript"] as? Bool == true
    }
    webConfig.preferences.javaScriptCanOpenWindowsAutomatically = config["allowPopups"] as? Bool == true
    webConfig.allowsInlineMediaPlayback =
      config["allowInlineMediaPlayback"] as? Bool == true ||
      config["inlinePlayback"] as? Bool == true
    if #available(iOS 10.0, *) {
      webConfig.mediaTypesRequiringUserActionForPlayback =
        config["requireMediaUserGesture"] as? Bool != false ? .all : []
    }
    let view = WKWebView(frame: .zero, configuration: webConfig)
    view.navigationDelegate = self
    view.uiDelegate = self
    if let userAgent = config["userAgent"] as? String, !userAgent.isEmpty {
      view.customUserAgent = userAgent
    }
    webView = view
    runPendingLoadIfNeeded()
    return view
  }

  private func load(request: [String: Any]) {
    updateVirtualResources(from: request)
    guard let view = webView else {
      pendingLoad = request
      return
    }
    load(request, into: view)
  }

  private func runPendingLoadIfNeeded() {
    guard let request = pendingLoad, let view = webView else { return }
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
    view.takeSnapshot(with: nil) { image, error in
      if let error = error {
        result(FlutterError(code: "papyrus_ios", message: error.localizedDescription, details: nil))
      } else {
        result(FlutterStandardTypedData(bytes: image?.pngData() ?? Data()))
      }
    }
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

  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    channel?.invokeMethod("pageStarted", arguments: webView.url?.absoluteString)
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    channel?.invokeMethod("pageFinished", arguments: webView.url?.absoluteString)
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

  private func respond(to task: WKURLSchemeTask, with resource: PapyrusIosInlineResource, url: URL) {
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

    let code = notFound ? NSURLErrorFileDoesNotExist : NSURLErrorNoPermissionsToReadFile
    task.didFailWithError(
      NSError(
        domain: NSURLErrorDomain,
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

  private func resourceDecision(from result: Any?) -> PapyrusIosResourceDecision {
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

  private func inlineResource(from map: [String: Any]?) -> PapyrusIosInlineResource? {
    guard let map else { return nil }
    let bytes = (map["bytes"] as? [Int] ?? []).compactMap(UInt8.init(exactly:))
    return PapyrusIosInlineResource(
      data: Data(bytes),
      mimeType: map["mimeType"] as? String ?? "application/octet-stream",
      statusCode: map["statusCode"] as? Int ?? 200,
      headers: map["headers"] as? [String: String] ?? [:]
    )
  }

  private func httpResponse(for url: URL, resource: PapyrusIosInlineResource) -> HTTPURLResponse? {
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
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
      decisionHandler(.cancel)
    case "download":
      if #available(iOS 14.5, *) {
        decisionHandler(.download)
      } else {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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

  private enum PapyrusIosNavigationType: String {
    case linkClicked
    case formSubmitted
    case backForward
    case reload
    case programmatic
    case other
  }

  private func navigationType(for navigationAction: WKNavigationAction) -> PapyrusIosNavigationType {
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

private class PapyrusIosSchemeHandler: NSObject, WKURLSchemeHandler {
  weak var plugin: PapyrusIosPlugin?

  init(plugin: PapyrusIosPlugin) {
    self.plugin = plugin
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    plugin?.startSchemeTask(urlSchemeTask)
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    plugin?.stopSchemeTask(urlSchemeTask)
  }
}

private class PapyrusIosViewFactory: NSObject, FlutterPlatformViewFactory {
  private weak var plugin: PapyrusIosPlugin?

  init(plugin: PapyrusIosPlugin) {
    self.plugin = plugin
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let config = args as? [String: Any] ?? [:]
    let webView = plugin?.createWebView(config: config) ?? WKWebView(frame: frame)
    webView.frame = frame
    return PapyrusIosPlatformView(webView: webView)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private class PapyrusIosPlatformView: NSObject, FlutterPlatformView {
  private let webView: WKWebView

  init(webView: WKWebView) {
    self.webView = webView
  }

  func view() -> UIView {
    webView
  }
}
