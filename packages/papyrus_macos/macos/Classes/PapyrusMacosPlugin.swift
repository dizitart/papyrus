import Cocoa
import FlutterMacOS
import WebKit

public class PapyrusMacosPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
  private var channel: FlutterMethodChannel?
  private var webView: WKWebView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.papyrus.papyrus_macos", binaryMessenger: registrar.messenger)
    let instance = PapyrusMacosPlugin()
    instance.channel = channel
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
      webView = nil
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
    let view = WKWebView(frame: .zero, configuration: webConfig)
    view.navigationDelegate = self
    view.uiDelegate = self
    webView = view
    return view
  }

  private func load(request: [String: Any]) {
    if webView == nil { createWebView(config: [:]) }
    guard let view = webView else { return }
    switch request["type"] as? String {
    case "html":
      let base = (request["baseUri"] as? String).flatMap(URL.init(string:))
      view.loadHTMLString(request["html"] as? String ?? "", baseURL: base)
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
    view.takeSnapshot(with: nil) { image, error in
      if let error = error {
        result(FlutterError(code: "papyrus_macos", message: error.localizedDescription, details: nil))
      } else {
        result(FlutterStandardTypedData(bytes: image?.tiffRepresentation ?? Data()))
      }
    }
  }

  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    channel?.invokeMethod("navigationRequest", arguments: navigationAction.request.url?.absoluteString)
    decisionHandler(.allow)
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
