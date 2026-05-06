package dev.papyrus.papyrus_android

import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.ConsoleMessage
import android.webkit.DownloadListener
import android.webkit.PermissionRequest
import android.webkit.WebStorage
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
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

private data class PapyrusAndroidInlineResource(
    val bytes: ByteArray,
    val mimeType: String,
    val statusCode: Int = 200,
    val headers: Map<String, String> = emptyMap(),
)

private data class PapyrusAndroidResourcePolicy(
    val remoteResources: String = "block",
    val allowedHosts: Set<String> = emptySet(),
    val allowedSchemes: Set<String> = setOf("https"),
    val enableRequestInterception: Boolean = true,
)

private data class PapyrusAndroidResourceDecision(
    val action: String,
    val response: PapyrusAndroidInlineResource? = null,
)

private data class PapyrusAndroidNavigationPolicy(
    val defaultDecision: String = "block",
    val allowedSchemes: Set<String> = setOf("https"),
    val externalSchemes: Set<String> = setOf("http", "https", "mailto", "tel"),
    val blockedSchemes: Set<String> = setOf("javascript", "data", "file"),
    val requireUserGestureForExternalOpen: Boolean = true,
    val allowMainFrameNavigation: Boolean = false,
    val allowSubFrameNavigation: Boolean = false,
)

class PapyrusAndroidPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    private var webView: WebView? = null
    private var pendingLoad: Map<*, *>? = null
    private var progress: Double = 0.0
    private var navigationResolverEnabled = false
    private var resourceResolverEnabled = false
    private var resourcePolicy = PapyrusAndroidResourcePolicy()
    private var navigationPolicy = PapyrusAndroidNavigationPolicy()
    private var currentConfiguration: Map<*, *> = emptyMap<Any, Any>()
    private val appInitiatedNavigations = mutableSetOf<String>()
    private val virtualResources = mutableMapOf<String, PapyrusAndroidInlineResource>()

    private companion object {
        const val SELECTED_TEXT_SCRIPT =
            "(function(){var selection = window.getSelection ? window.getSelection().toString() : ''; return selection ? encodeURIComponent(selection) : null;})()"
    }

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
        destroyWebView(webView)
        webView = null
        currentConfiguration = emptyMap<Any, Any>()
        appInitiatedNavigations.clear()
        pendingLoad = null
        virtualResources.clear()
        navigationResolverEnabled = false
        resourceResolverEnabled = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> {
                    createWebView(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                    result.success(null)
                }
                "load" -> {
                    val request = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    if (!isLoadAllowed(request)) {
                        result.error(
                            "navigationBlocked",
                            "File loading is disabled by the current Papyrus security policy.",
                            request["absolutePath"] ?: request["uri"],
                        )
                        return
                    }
                    load(request)
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
                "selectedText" -> selectedText(result)
                "getContentSize" -> result.success(contentSize())
                "captureSnapshot" -> captureSnapshot(result)
                "printDocument" -> { printDocument(call.arguments as? Map<*, *>); result.success(null) }
                "clearCache" -> { webView?.clearCache(true); result.success(null) }
                "clearStorage" -> {
                    webView?.clearHistory()
                    WebStorage.getInstance().deleteAllData()
                    val cookieManager = CookieManager.getInstance()
                    cookieManager.removeAllCookies(null)
                    cookieManager.flush()
                    result.success(null)
                }
                "setNavigationResolverEnabled" -> {
                    navigationResolverEnabled = call.arguments == true
                    result.success(null)
                }
                "setResourceResolverEnabled" -> {
                    resourceResolverEnabled = call.arguments == true
                    result.success(null)
                }
                "dispose" -> {
                    currentConfiguration = emptyMap<Any, Any>()
                    appInitiatedNavigations.clear()
                    destroyWebView(webView)
                    webView = null
                    pendingLoad = null
                    virtualResources.clear()
                    resourceResolverEnabled = false
                    result.success(null)
                }
                "getCapabilities" -> result.success(capabilities())
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("papyrus_android", error.message, null)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    internal fun createWebView(config: Map<*, *>): WebView {
        currentConfiguration = config
        navigationResolverEnabled = config["navigationResolverEnabled"] as? Boolean ?: navigationResolverEnabled
        resourceResolverEnabled = config["resourceResolverEnabled"] as? Boolean ?: resourceResolverEnabled
        val view = WebView(appContext)
        resourcePolicy = resourcePolicyFromConfig(config)
        navigationPolicy = navigationPolicyFromConfig(config)
        configureWebView(view, config)
        destroyWebView(webView)
        webView = view
        runPendingLoadIfNeeded()
        return view
    }

    internal fun disposeWebView(view: WebView) {
        if (webView === view) {
            webView = null
        }
        destroyWebView(view)
    }

    private fun destroyWebView(view: WebView?) {
        val target = view ?: return
        try {
            target.stopLoading()
            target.onPause()
            target.pauseTimers()
            target.webChromeClient = null
            target.webViewClient = object : WebViewClient() {}
            (target.parent as? ViewGroup)?.removeView(target)
            target.removeAllViews()
        } finally {
            target.destroy()
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView(view: WebView, config: Map<*, *>) {
        val allowJavaScript = config["allowJavaScript"] == true
        val allowFileAccess = config["allowFileAccess"] == true
        val allowTextSelection = config["allowTextSelection"] != false
        val allowContextMenu = config["allowContextMenu"] != false
        val allowLongPress = config["allowLongPress"] != false
        val localStorageEnabled = config["localStorage"] as? String == "enabled"
        val cacheMode = config["cacheMode"] as? String ?: "defaultMode"
        val cookiePolicy = config["cookiePolicy"] as? String ?: "block"
        val enableLongPress = allowLongPress && allowTextSelection && allowContextMenu
        view.settings.javaScriptEnabled = allowJavaScript
        view.settings.javaScriptCanOpenWindowsAutomatically = config["allowPopups"] == true
        view.settings.allowFileAccess = allowFileAccess
        view.settings.allowContentAccess = allowFileAccess
        view.settings.domStorageEnabled = localStorageEnabled
        @Suppress("DEPRECATION")
        run {
            view.settings.databaseEnabled = localStorageEnabled
        }
        view.settings.setSupportZoom(config["zoomEnabled"] != false)
        view.settings.setSupportMultipleWindows(config["allowPopups"] == true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            val allowUniversalAccess = config["allowUniversalAccessFromFileUrls"] == true
            view.settings.allowFileAccessFromFileURLs = allowUniversalAccess
            view.settings.allowUniversalAccessFromFileURLs = allowUniversalAccess
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            view.settings.mediaPlaybackRequiresUserGesture =
                config["requireMediaUserGesture"] != false
        }
        view.settings.cacheMode = when (cacheMode) {
            "noCache" -> WebSettings.LOAD_NO_CACHE
            "cacheOnly" -> WebSettings.LOAD_CACHE_ONLY
            else -> WebSettings.LOAD_DEFAULT
        }
        view.isLongClickable = enableLongPress
        view.isHapticFeedbackEnabled = enableLongPress
        view.setOnLongClickListener(
            if (enableLongPress) {
                null
            } else {
                View.OnLongClickListener { true }
            }
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            view.settings.mixedContentMode =
                if (config["allowMixedContent"] == true) WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
                else WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            WebView.setWebContentsDebuggingEnabled(config["debuggingEnabled"] == true)
        }
        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(cookiePolicy != "block")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            cookieManager.setAcceptThirdPartyCookies(view, cookiePolicy == "allow")
        }
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (request.isForMainFrame && consumeAppInitiatedNavigation(request.url)) {
                    return false
                }

                val fallbackDecision = navigationDecisionFor(request)
                if (!navigationResolverEnabled) {
                    return applyNavigationDecision(view, request, fallbackDecision)
                }

                channel.invokeMethod(
                    "navigationRequest",
                    navigationArgumentsFor(request),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            applyNavigationDecision(
                                view,
                                request,
                                navigationDecisionFromResult(result, fallbackDecision),
                            )
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            applyNavigationDecision(view, request, fallbackDecision)
                        }

                        override fun notImplemented() {
                            applyNavigationDecision(view, request, fallbackDecision)
                        }
                    }
                )
                return true
            }

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                resolveInlineResource(request.url.toString())?.let {
                    return webResourceResponse(it)
                }

                val hostDecision =
                    if (resourceResolverEnabled && resourcePolicy.enableRequestInterception) {
                        requestResourceDecision(request)
                    } else {
                        null
                    }

                return when (hostDecision?.action) {
                    "respond" -> webResourceResponse(hostDecision.response ?: blockedResource())
                    "block" -> webResourceResponse(blockedResource())
                    "allow" -> fallbackResourceResponse(view, request, allowByHost = true)
                    else -> fallbackResourceResponse(view, request)
                }
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
        updateVirtualResources(request)
        val view = webView ?: run {
            pendingLoad = request
            return
        }
        load(request, view)
    }

    private fun runPendingLoadIfNeeded() {
        val request = pendingLoad ?: return
        val view = webView ?: return
        pendingLoad = null
        load(request, view)
    }

    private fun load(request: Map<*, *>, view: WebView) {
        when (request["type"]) {
            "html" -> {
                val baseUri = request["baseUri"] as? String
                if (!baseUri.isNullOrEmpty()) {
                    markAppInitiatedNavigation(baseUri)
                }
                view.loadDataWithBaseURL(
                    baseUri,
                    request["html"] as? String ?: "",
                    "text/html",
                    "utf-8",
                    null
                )
            }
            "uri" -> {
                val uri = request["uri"] as? String ?: ""
                markAppInitiatedNavigation(uri)
                val headers = stringMap(request["headers"])
                if (headers.isEmpty()) {
                    view.loadUrl(uri)
                } else {
                    view.loadUrl(uri, headers)
                }
            }
            "file" -> {
                val uri = "file://${request["absolutePath"]}"
                markAppInitiatedNavigation(uri)
                view.loadUrl(uri)
            }
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

    private fun selectedText(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.KITKAT) {
            result.error(
                "unsupportedPlatformFeature",
                "Selected-text queries require Android KitKat or newer.",
                null,
            )
            return
        }
        webView?.evaluateJavascript(SELECTED_TEXT_SCRIPT) { value ->
            if (value == null || value == "null") {
                result.success(null)
            } else {
                result.success(value.removeSurrounding("\""))
            }
        } ?: result.success(null)
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

    private fun resourcePolicyFromConfig(config: Map<*, *>): PapyrusAndroidResourcePolicy {
        return PapyrusAndroidResourcePolicy(
            remoteResources = config["remoteResources"] as? String ?: "block",
            allowedHosts = stringSet(config["allowedHosts"]),
            allowedSchemes = stringSet(config["allowedSchemes"]).ifEmpty { setOf("https") },
            enableRequestInterception = config["enableRequestInterception"] as? Boolean ?: true,
        )
    }

    private fun navigationPolicyFromConfig(config: Map<*, *>): PapyrusAndroidNavigationPolicy {
        return PapyrusAndroidNavigationPolicy(
            defaultDecision = config["navigationDefaultDecision"] as? String ?: "block",
            allowedSchemes = stringSet(config["navigationAllowedSchemes"]).ifEmpty { setOf("https") },
            externalSchemes = stringSet(config["navigationExternalSchemes"]).ifEmpty {
                setOf("http", "https", "mailto", "tel")
            },
            blockedSchemes = stringSet(config["navigationBlockedSchemes"]).ifEmpty {
                setOf("javascript", "data", "file")
            },
            requireUserGestureForExternalOpen =
                config["requireUserGestureForExternalOpen"] as? Boolean ?: true,
            allowMainFrameNavigation = config["allowMainFrameNavigation"] as? Boolean ?: false,
            allowSubFrameNavigation = config["allowSubFrameNavigation"] as? Boolean ?: false,
        )
    }

    private fun updateVirtualResources(request: Map<*, *>) {
        virtualResources.clear()
        val resources = request["virtualResources"] as? List<*> ?: return
        for (entry in resources) {
            val map = entry as? Map<*, *> ?: continue
            val uri = map["uri"] as? String ?: continue
            virtualResources[uri] = PapyrusAndroidInlineResource(
                bytes = byteArray(map["bytes"]),
                mimeType = map["mimeType"] as? String ?: "application/octet-stream",
                statusCode = (map["statusCode"] as? Number)?.toInt() ?: 200,
                headers = stringMap(map["headers"]),
            )
        }
    }

    private fun resolveInlineResource(uri: String): PapyrusAndroidInlineResource? =
        virtualResources[uri]

    private fun requestResourceDecision(
        request: WebResourceRequest,
    ): PapyrusAndroidResourceDecision? {
        val latch = CountDownLatch(1)
        val resultRef = AtomicReference<Any?>()

        val arguments = mapOf(
            "uri" to request.url.toString(),
            "method" to request.method,
            "headers" to request.requestHeaders,
            "resourceType" to resourceTypeFor(request),
            "isMainFrame" to request.isForMainFrame,
        )

        mainHandler.post {
            channel.invokeMethod("resourceRequest", arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    resultRef.set(result)
                    latch.countDown()
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    latch.countDown()
                }

                override fun notImplemented() {
                    latch.countDown()
                }
            })
        }

        if (!latch.await(2, TimeUnit.SECONDS)) {
            return PapyrusAndroidResourceDecision(action = "block")
        }

        val map = resultRef.get() as? Map<*, *> ?: return PapyrusAndroidResourceDecision(action = "block")
        return when (map["decision"] as? String) {
            "allow" -> PapyrusAndroidResourceDecision(action = "allow")
            "respond" -> {
                val response = map["response"] as? Map<*, *> ?: return PapyrusAndroidResourceDecision(action = "block")
                PapyrusAndroidResourceDecision(
                    action = "respond",
                    response = PapyrusAndroidInlineResource(
                        bytes = byteArray(response["bytes"]),
                        mimeType = response["mimeType"] as? String ?: "application/octet-stream",
                        statusCode = (response["statusCode"] as? Number)?.toInt() ?: 200,
                        headers = stringMap(response["headers"]),
                    ),
                )
            }
            else -> PapyrusAndroidResourceDecision(action = "block")
        }
    }

    private fun navigationDecisionFor(request: WebResourceRequest): String {
        val scheme = request.url.scheme?.lowercase() ?: ""
        if (navigationPolicy.blockedSchemes.contains(scheme)) {
            return "block"
        }
        if (request.isForMainFrame && !navigationPolicy.allowMainFrameNavigation) {
            return navigationPolicy.defaultDecision
        }
        if (!request.isForMainFrame && !navigationPolicy.allowSubFrameNavigation) {
            return "block"
        }
        if (navigationPolicy.allowedSchemes.contains(scheme)) {
            return "allow"
        }
        if (navigationPolicy.externalSchemes.contains(scheme)) {
            if (navigationPolicy.requireUserGestureForExternalOpen && !requestHasUserGesture(request)) {
                return "block"
            }
            return "openExternally"
        }
        return navigationPolicy.defaultDecision
    }

    private fun navigationArgumentsFor(request: WebResourceRequest): Map<String, Any> {
        return mapOf(
            "uri" to request.url.toString(),
            "isMainFrame" to request.isForMainFrame,
            "navigationType" to navigationTypeFor(request),
            "hasUserGesture" to requestHasUserGesture(request),
        )
    }

    private fun navigationTypeFor(request: WebResourceRequest): String {
        return when {
            requestHasUserGesture(request) -> "linkClicked"
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && request.isRedirect -> "programmatic"
            else -> "other"
        }
    }

    private fun navigationDecisionFromResult(result: Any?, fallback: String): String {
        val map = result as? Map<*, *> ?: return fallback
        return map["decision"] as? String ?: fallback
    }

    private fun applyNavigationDecision(
        view: WebView,
        request: WebResourceRequest,
        decision: String,
    ): Boolean {
        return when (decision) {
            "allow" -> {
                replayNavigation(view, request)
                true
            }
            "openExternally" -> {
                openExternally(request.url)
                true
            }
            else -> true
        }
    }

    private fun replayNavigation(view: WebView, request: WebResourceRequest) {
        val url = request.url.toString()
        markAppInitiatedNavigation(url)
        val headers = request.requestHeaders
        if (headers.isEmpty()) {
            view.loadUrl(url)
        } else {
            view.loadUrl(url, headers)
        }
    }

    private fun requestHasUserGesture(request: WebResourceRequest): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            request.hasGesture()
        } else {
            false
        }
    }

    private fun markAppInitiatedNavigation(uri: String) {
        if (uri.isNotEmpty()) {
            appInitiatedNavigations.add(uri)
        }
    }

    private fun consumeAppInitiatedNavigation(uri: Uri): Boolean {
        return appInitiatedNavigations.remove(uri.toString())
    }

    private fun isLoadAllowed(request: Map<*, *>): Boolean {
        return when (request["type"] as? String) {
            "file" -> currentConfiguration["allowFileAccess"] == true
            "uri" -> {
                val uri = request["uri"] as? String ?: return true
                !(uri.startsWith("file://") && currentConfiguration["allowFileAccess"] != true)
            }
            else -> true
        }
    }

    private fun openExternally(uri: Uri) {
        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            if (intent.resolveActivity(appContext.packageManager) != null) {
                appContext.startActivity(intent)
            }
        } catch (_: ActivityNotFoundException) {
        }
    }

    private fun fallbackResourceResponse(
        view: WebView,
        request: WebResourceRequest,
        allowByHost: Boolean = false,
    ): WebResourceResponse? {
        val scheme = request.url.scheme?.lowercase() ?: return webResourceResponse(blockedResource())
        return when (scheme) {
            "http", "https" -> {
                if (allowByHost || isRemoteRequestAllowed(request.url)) {
                    null
                } else {
                    webResourceResponse(blockedResource())
                }
            }
            "file" -> if (view.settings.allowFileAccess || allowByHost) null else webResourceResponse(blockedResource())
            "about", "data" -> null
            else -> webResourceResponse(notFoundResource())
        }
    }

    private fun isRemoteRequestAllowed(uri: android.net.Uri): Boolean {
        val scheme = uri.scheme?.lowercase() ?: return false
        if (!resourcePolicy.allowedSchemes.contains(scheme)) {
            return false
        }
        return when (resourcePolicy.remoteResources) {
            "allowAll" -> true
            "allowByHost" -> resourcePolicy.allowedHosts.contains(uri.host ?: "")
            else -> false
        }
    }

    private fun resourceTypeFor(request: WebResourceRequest): String {
        val accept = request.requestHeaders["Accept"]?.lowercase()
        val path = request.url.lastPathSegment?.lowercase().orEmpty()
        return when {
            request.isForMainFrame -> "document"
            accept?.contains("text/css") == true || path.endsWith(".css") -> "stylesheet"
            accept?.contains("image/") == true || path.endsWith(".png") || path.endsWith(".jpg") || path.endsWith(".jpeg") || path.endsWith(".gif") || path.endsWith(".svg") || path.endsWith(".webp") -> "image"
            accept?.contains("font/") == true || path.endsWith(".woff") || path.endsWith(".woff2") || path.endsWith(".ttf") -> "font"
            accept?.contains("javascript") == true || path.endsWith(".js") -> "script"
            accept?.contains("video/") == true || accept?.contains("audio/") == true -> "media"
            else -> "other"
        }
    }

    private fun webResourceResponse(resource: PapyrusAndroidInlineResource): WebResourceResponse {
        return WebResourceResponse(
            resource.mimeType,
            responseEncoding(resource.mimeType),
            resource.statusCode,
            reasonPhrase(resource.statusCode),
            resource.headers,
            ByteArrayInputStream(resource.bytes),
        )
    }

    private fun blockedResource() = PapyrusAndroidInlineResource(
        bytes = ByteArray(0),
        mimeType = "text/plain",
        statusCode = 403,
    )

    private fun notFoundResource() = PapyrusAndroidInlineResource(
        bytes = ByteArray(0),
        mimeType = "text/plain",
        statusCode = 404,
    )

    private fun responseEncoding(mimeType: String): String? {
        val lower = mimeType.lowercase()
        return if (
            lower.startsWith("text/") ||
            lower.contains("json") ||
            lower.contains("javascript") ||
            lower.contains("xml") ||
            lower.contains("svg")
        ) {
            "utf-8"
        } else {
            null
        }
    }

    private fun reasonPhrase(statusCode: Int): String {
        return when (statusCode) {
            200 -> "OK"
            403 -> "Blocked"
            404 -> "Not Found"
            else -> "Papyrus"
        }
    }

    private fun stringSet(value: Any?): Set<String> {
        val items = value as? List<*> ?: return emptySet()
        return items.mapNotNull { it?.toString() }.toSet()
    }

    private fun stringMap(value: Any?): Map<String, String> {
        val map = value as? Map<*, *> ?: return emptyMap()
        return map.entries.associate { (key, entry) ->
            (key?.toString() ?: "") to (entry?.toString() ?: "")
        }
    }

    private fun byteArray(value: Any?): ByteArray {
        val items = value as? List<*> ?: return ByteArray(0)
        return items.mapNotNull { (it as? Number)?.toInt() }
            .map { it.toByte() }
            .toByteArray()
    }
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
