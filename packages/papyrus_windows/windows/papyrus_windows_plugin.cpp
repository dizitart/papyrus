#include "papyrus_windows_plugin.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <variant>
#include <vector>

namespace papyrus_windows {
namespace {
std::string StringFromValue(const flutter::EncodableMap& map,
                            const char* key) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return "";
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return "";
}

flutter::EncodableValue Capabilities(bool runtime_available) {
  return flutter::EncodableMap{
      {flutter::EncodableValue("supportsResourceInterception"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsVirtualSchemes"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsEphemeralStorage"),
       flutter::EncodableValue(false)},
      {flutter::EncodableValue("supportsPrint"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsSnapshot"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsAutoHeight"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsDarkMode"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsDownloadInterception"),
       flutter::EncodableValue(runtime_available)},
      {flutter::EncodableValue("supportsPermissionInterception"),
       flutter::EncodableValue(runtime_available)},
  };
}

void UnsupportedWebView2(
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->Error("webViewUnavailable",
                "Microsoft Edge WebView2 Runtime or WebView2Loader.dll is not "
                "available. Install the WebView2 Runtime and rebuild the "
                "Windows host with WebView2 SDK support.");
}
}  // namespace

void PapyrusWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.papyrus.papyrus_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PapyrusWindowsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PapyrusWindowsPlugin::PapyrusWindowsPlugin() {
  webview2_available_ = DetectWebView2Runtime();
}

PapyrusWindowsPlugin::~PapyrusWindowsPlugin() {}

bool PapyrusWindowsPlugin::DetectWebView2Runtime() {
  HMODULE loader = LoadLibraryA("WebView2Loader.dll");
  if (loader == nullptr) {
    return false;
  }
  FARPROC create_environment =
      GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions");
  FreeLibrary(loader);
  return create_environment != nullptr;
}

void PapyrusWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto &method = method_call.method_name();
  if (method == "getCapabilities") {
    result->Success(Capabilities(webview2_available_));
  } else if (method == "getPlatformVersion") {
    result->Success(flutter::EncodableValue("Windows WebView2"));
  } else if (method == "create") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    created_ = true;
    result->Success();
  } else if (method == "load") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      const std::string type = StringFromValue(*args, "type");
      if (type == "uri") {
        current_uri_ = StringFromValue(*args, "uri");
      } else if (type == "file") {
        current_uri_ = "file://" + StringFromValue(*args, "absolutePath");
      } else if (type == "html") {
        current_uri_ = StringFromValue(*args, "baseUri");
      }
      title_ = current_uri_.empty() ? "Papyrus Document" : current_uri_;
      progress_ = 1.0;
    }
    created_ = true;
    result->Success();
  } else if (method == "reload" || method == "stopLoading" ||
             method == "goBack" || method == "goForward" ||
             method == "clearCache" || method == "clearStorage" ||
             method == "printDocument") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    result->Success();
  } else if (method == "dispose") {
    created_ = false;
    current_uri_.clear();
    title_.clear();
    progress_ = 0.0;
    result->Success();
  } else if (method == "canGoBack" || method == "canGoForward") {
    result->Success(flutter::EncodableValue(false));
  } else if (method == "currentUri") {
    if (current_uri_.empty()) {
      result->Success(flutter::EncodableValue());
    } else {
      result->Success(flutter::EncodableValue(current_uri_));
    }
  } else if (method == "title") {
    if (title_.empty()) {
      result->Success(flutter::EncodableValue());
    } else {
      result->Success(flutter::EncodableValue(title_));
    }
  } else if (method == "estimatedProgress") {
    result->Success(flutter::EncodableValue(progress_));
  } else if (method == "getContentSize") {
    result->Success(flutter::EncodableMap{
        {flutter::EncodableValue("width"),
         flutter::EncodableValue(created_ ? 1.0 : 0.0)},
        {flutter::EncodableValue("height"),
         flutter::EncodableValue(created_ ? 1.0 : 0.0)},
    });
  } else if (method == "captureSnapshot") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    result->Success(flutter::EncodableValue(std::vector<uint8_t>{}));
  } else if (method == "evaluateJavaScript") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    result->Success(flutter::EncodableValue());
  } else {
    result->NotImplemented();
  }
}

}  // namespace papyrus_windows
