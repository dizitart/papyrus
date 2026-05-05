package dev.papyrus.papyrus_android

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.webkit.ConsoleMessage
import android.webkit.DownloadListener
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream

class PapyrusAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var webView: WebView? = null
    private var progress: Double = 0.0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.papyrus.papyrus_android")
        channel.setMethodCallHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            "dev.papyrus.papyrus_android/webview",
            PapyrusWebViewFactory(this)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        webView?.destroy()
        webView = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    createWebView(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                }
                "load" -> {
                    load(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                }
                "reload" -> { webView?.reload(); result.success(null) }
                "stopLoading" -> { webView?.stopLoading(); result.success(null) }
                "canGoBack" -> result.success(webView?.canGoBack() ?: false)
                "canGoForward" -> result.success(webView?.canGoForward() ?: false)
                "goBack" -> { if (webView?.canGoBack() == true) webView?.goBack(); result.success(null) }
                "goForward" -> { if (webView?.canGoForward() == true) webView?.goForward(); result.success(null) }
                "currentUri" -> result.success(webView?.url)
                "title" -> result.success(webView?.title)
                "estimatedProgress" -> result.success(progress)
                "evaluateJavaScript" -> evaluate(call.arguments as? String ?: "", result)
                "getContentSize" -> result.success(contentSize())
                "captureSnapshot" -> captureSnapshot(result)
                "printDocument" -> { printDocument(call.arguments as? Map<*, *>); result.success(null) }
                "clearCache" -> { webView?.clearCache(true); result.success(null) }
                "clearStorage" -> { webView?.clearHistory(); result.success(null) }
                "dispose" -> { webView?.destroy(); webView = null; result.success(null) }
                "getCapabilities" -> result.success(capabilities())
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("papyrus_android", error.message, null)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    internal fun createWebView(config: Map<*, *>): WebView {
        val view = WebView(appContext)
        configureWebView(view, config)
        webView?.destroy()
        webView = view
        return view
    }

    internal fun disposeWebView(view: WebView) {
        if (webView === view) {
            webView = null
        }
        view.destroy()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(view: WebView, config: Map<*, *>) {
        val allowJavaScript = config["allowJavaScript"] == true
        view.settings.javaScriptEnabled = allowJavaScript
        view.settings.javaScriptCanOpenWindowsAutomatically = config["allowPopups"] == true
        view.settings.allowFileAccess = config["allowFileAccess"] == true
        view.settings.allowContentAccess = config["allowFileAccess"] == true
        view.settings.domStorageEnabled = config["ephemeral"] != true
        view.settings.setSupportZoom(config["zoomEnabled"] != false)
        view.settings.cacheMode = WebSettings.LOAD_DEFAULT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            view.settings.mixedContentMode =
                if (config["allowMixedContent"] == true) WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                else WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                channel.invokeMethod("navigationRequest", request.url.toString())
                return false
            }

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                channel.invokeMethod("resourceRequest", request.url.toString())
                return null
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                channel.invokeMethod("pageStarted", url)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                channel.invokeMethod("pageFinished", url)
            }
        }
        view.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) {
                progress = newProgress.toDouble() / 100.0
                channel.invokeMethod("progress", progress)
            }

            override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                channel.invokeMethod("consoleMessage", consoleMessage.message())
                return true
            }

            override fun onPermissionRequest(request: PermissionRequest) {
                request.deny()
                channel.invokeMethod("permissionRequest", request.origin.toString())
            }
        }
        view.setDownloadListener(DownloadListener { url, _, _, mimeType, contentLength ->
            channel.invokeMethod("downloadRequest", mapOf("uri" to url, "mimeType" to mimeType, "contentLength" to contentLength))
        })
    }

    private fun load(request: Map<*, *>) {
        val view = webView ?: run {
            createWebView(emptyMap<Any, Any>())
            webView!!
        }
        when (request["type"]) {
            "html" -> view.loadDataWithBaseURL(
                request["baseUri"] as? String,
                request["html"] as? String ?: "",
                "text/html",
                "utf-8",
                null
            )
            "uri" -> view.loadUrl(request["uri"] as? String ?: "")
            "file" -> view.loadUrl("file://${request["absolutePath"]}")
            "data" -> view.loadData(request["bytes"].toString(), request["mimeType"] as? String ?: "text/plain", "utf-8")
        }
    }

    private fun evaluate(source: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            webView?.evaluateJavascript(source) { value -> result.success(value) } ?: result.success(null)
        } else {
            result.error("unsupportedPlatformFeature", "JavaScript evaluation requires Android KitKat or newer.", null)
        }
    }

    private fun contentSize(): Map<String, Double> {
        val view = webView ?: return mapOf("width" to 0.0, "height" to 0.0)
        return mapOf("width" to view.width.toDouble(), "height" to (view.contentHeight * view.scale).toDouble())
    }

    private fun captureSnapshot(result: MethodChannel.Result) {
        val view = webView ?: return result.success(ByteArray(0))
        val bitmap = Bitmap.createBitmap(maxOf(view.width, 1), maxOf(view.height, 1), Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        view.draw(canvas)
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        result.success(out.toByteArray())
    }

    private fun printDocument(args: Map<*, *>?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val name = args?.get("jobName") as? String ?: "Papyrus Document"
            webView?.createPrintDocumentAdapter(name)
        }
    }

    private fun capabilities() = mapOf(
        "supportsResourceInterception" to true,
        "supportsVirtualSchemes" to true,
        "supportsEphemeralStorage" to true,
        "supportsPrint" to true,
        "supportsSnapshot" to true,
        "supportsAutoHeight" to true,
        "supportsDarkMode" to true,
        "supportsDownloadInterception" to true,
        "supportsPermissionInterception" to true,
    )
}

private class PapyrusWebViewFactory(
    private val plugin: PapyrusAndroidPlugin,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val config = args as? Map<*, *> ?: emptyMap<Any, Any>()
        return PapyrusPlatformWebView(plugin, plugin.createWebView(config))
    }
}

private class PapyrusPlatformWebView(
    private val plugin: PapyrusAndroidPlugin,
    private val webView: WebView,
) : PlatformView {
    override fun getView() = webView

    override fun dispose() {
        plugin.disposeWebView(webView)
    }
}
