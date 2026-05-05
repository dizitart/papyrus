import Flutter
import UIKit
import WebKit

public class PapyrusIosPlugin: NSObject, FlutterPlugin, WKNavigationDelegate, WKUIDelegate {
  private var channel: FlutterMethodChannel?
  private var webView: WKWebView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "dev.papyrus.papyrus_ios", binaryMessenger: registrar.messenger())
    let instance = PapyrusIosPlugin()
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
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
          result(FlutterError(code: "papyrus_ios", message: error.localizedDescription, details: nil))
        } else {
          result(value)
        }
      }
    case "getContentSize":
      result(["width": webView?.scrollView.contentSize.width ?? 0, "height": webView?.scrollView.contentSize.height ?? 0])
    case "captureSnapshot":
      captureSnapshot(result: result)
    case "printDocument":
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

  private func createWebView(config: [String: Any]) {
    let webConfig = WKWebViewConfiguration()
    if config["ephemeral"] as? Bool == true {
      webConfig.websiteDataStore = .nonPersistent()
    }
    if #available(iOS 14.0, *) {
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
        result(FlutterError(code: "papyrus_ios", message: error.localizedDescription, details: nil))
      } else {
        result(FlutterStandardTypedData(bytes: image?.pngData() ?? Data()))
      }
    }
  }

  public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    channel?.invokeMethod("navigationRequest", arguments: navigationAction.request.url?.absoluteString)
    decisionHandler(.cancel)
  }

  public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    channel?.invokeMethod("pageStarted", arguments: webView.url?.absoluteString)
  }

  public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    channel?.invokeMethod("pageFinished", arguments: webView.url?.absoluteString)
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
