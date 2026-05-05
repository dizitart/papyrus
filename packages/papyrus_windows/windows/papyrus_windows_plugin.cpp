#include "papyrus_windows_plugin.h"

#include <windows.h>
#include <WebView2.h>
#include <WebView2EnvironmentOptions.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cmath>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <variant>
#include <vector>
#include <wrl.h>

namespace papyrus_windows {
namespace {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

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

bool BoolFromValue(const flutter::EncodableMap& map,
                   const char* key,
                   bool fallback = false) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

double DoubleFromValue(const flutter::EncodableMap& map,
                       const char* key,
                       double fallback = 0) {
  auto iterator = map.find(flutter::EncodableValue(key));
  if (iterator == map.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), wide.data(), size);
  return wide;
}

std::wstring FileUriFromPath(const std::string& path) {
  std::wstring uri = L"file:///";
  std::wstring wide_path = Utf8ToWide(path);
  for (wchar_t value : wide_path) {
    uri.push_back(value == L'\\' ? L'/' : value);
  }
  return uri;
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
                "Microsoft Edge WebView2 Runtime is not available. Install "
                "the WebView2 Runtime to render Papyrus on Windows.");
}
}  // namespace

void PapyrusWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.papyrus.papyrus_windows",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PapyrusWindowsPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

PapyrusWindowsPlugin::PapyrusWindowsPlugin() {
  webview2_available_ = DetectWebView2Runtime();
}

PapyrusWindowsPlugin::PapyrusWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  auto* view = registrar_->GetView();
  if (view != nullptr) {
    hwnd_ = view->GetNativeWindow();
  }
  webview2_available_ = DetectWebView2Runtime();
  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

PapyrusWindowsPlugin::~PapyrusWindowsPlugin() {
  if (registrar_ != nullptr && window_proc_delegate_id_ != 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }
  if (controller_) {
    controller_->Close();
  }
}

bool PapyrusWindowsPlugin::DetectWebView2Runtime() {
  LPWSTR version = nullptr;
  HRESULT result =
      GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
  if (version != nullptr) {
    CoTaskMemFree(version);
  }
  return SUCCEEDED(result);
}

bool PapyrusWindowsPlugin::RetryWithSoftwareFallback() {
  const std::string hardware_mode =
      StringFromValue(configuration_, "hardwareAcceleration");
  if (hardware_mode == "hardware" || hardware_mode == "software" ||
      software_fallback_attempted_) {
    return false;
  }
  software_fallback_attempted_ = true;
  force_software_rendering_ = true;
  EnsureWebView();
  return true;
}

void PapyrusWindowsPlugin::EnsureWebView() {
  if (!webview2_available_ || webview_ || creating_ || hwnd_ == nullptr) {
    return;
  }
  creating_ = true;
  ICoreWebView2EnvironmentOptions* environment_options_ptr = nullptr;
  environment_options_.Reset();
  if (StringFromValue(configuration_, "hardwareAcceleration") == "software" ||
      force_software_rendering_) {
    environment_options_ =
        Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
    environment_options_->put_AdditionalBrowserArguments(L"--disable-gpu");
    environment_options_ptr = environment_options_.Get();
  }
  HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, nullptr, environment_options_ptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this](HRESULT result, ICoreWebView2Environment* environment)
              -> HRESULT {
            creating_ = false;
            environment_options_.Reset();
            if (FAILED(result) || environment == nullptr) {
              if (RetryWithSoftwareFallback()) {
                return S_OK;
              }
              webview2_available_ = false;
              return S_OK;
            }
            environment_ = environment;
            environment_->CreateCoreWebView2Controller(
                hwnd_,
                Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
                    [this](HRESULT result, ICoreWebView2Controller* controller)
                        -> HRESULT {
                      if (FAILED(result) || controller == nullptr) {
                        environment_.Reset();
                        if (RetryWithSoftwareFallback()) {
                          return S_OK;
                        }
                        webview2_available_ = false;
                        return S_OK;
                      }
                      controller_ = controller;
                      controller_->get_CoreWebView2(&webview_);
                      ApplySettings();
                      ApplyBounds();
                      RunPendingLoad();
                      return S_OK;
                    })
                    .Get());
            return S_OK;
          })
          .Get());
  if (FAILED(result)) {
    creating_ = false;
    environment_options_.Reset();
    if (RetryWithSoftwareFallback()) {
      return;
    }
    webview2_available_ = false;
  }
}

void PapyrusWindowsPlugin::ApplySettings() {
  if (!webview_) {
    return;
  }
  ComPtr<ICoreWebView2Settings> settings;
  if (FAILED(webview_->get_Settings(&settings)) || !settings) {
    return;
  }
  settings->put_IsScriptEnabled(
      BoolFromValue(configuration_, "allowJavaScript") ? TRUE : FALSE);
  settings->put_AreDefaultScriptDialogsEnabled(
      BoolFromValue(configuration_, "allowJavaScript") ? TRUE : FALSE);
  settings->put_AreDevToolsEnabled(
      BoolFromValue(configuration_, "debuggingEnabled") ? TRUE : FALSE);
  settings->put_IsZoomControlEnabled(
      BoolFromValue(configuration_, "zoomEnabled", true) ? TRUE : FALSE);
  settings->put_AreDefaultContextMenusEnabled(FALSE);
  settings->put_IsStatusBarEnabled(FALSE);
}

void PapyrusWindowsPlugin::ApplyBounds() {
  if (!controller_) {
    return;
  }
  controller_->put_Bounds(bounds_);
  controller_->put_IsVisible(visible_ ? TRUE : FALSE);
}

void PapyrusWindowsPlugin::RunPendingLoad() {
  if (pending_load_.empty() || !webview_) {
    return;
  }
  LoadRequest(pending_load_);
  pending_load_.clear();
}

flutter::EncodableValue PapyrusWindowsPlugin::DebugOverlayState() const {
  return flutter::EncodableMap{
      {flutter::EncodableValue("overlayAttached"),
       flutter::EncodableValue(controller_ != nullptr)},
      {flutter::EncodableValue("webViewAttached"),
       flutter::EncodableValue(webview_ != nullptr)},
      {flutter::EncodableValue("visible"), flutter::EncodableValue(visible_)},
      {flutter::EncodableValue("softwareRendering"),
       flutter::EncodableValue(force_software_rendering_)},
      {flutter::EncodableValue("x"),
       flutter::EncodableValue(static_cast<double>(bounds_.left))},
      {flutter::EncodableValue("y"),
       flutter::EncodableValue(static_cast<double>(bounds_.top))},
      {flutter::EncodableValue("width"),
       flutter::EncodableValue(
           static_cast<double>(bounds_.right - bounds_.left))},
      {flutter::EncodableValue("height"),
       flutter::EncodableValue(
           static_cast<double>(bounds_.bottom - bounds_.top))},
  };
}

void PapyrusWindowsPlugin::LoadRequest(
    const flutter::EncodableMap& request) {
  if (!webview_) {
    pending_load_ = request;
    EnsureWebView();
    return;
  }

  const std::string type = StringFromValue(request, "type");
  if (type == "uri") {
    current_uri_ = StringFromValue(request, "uri");
    webview_->Navigate(Utf8ToWide(current_uri_).c_str());
  } else if (type == "file") {
    current_uri_ = StringFromValue(request, "absolutePath");
    webview_->Navigate(FileUriFromPath(current_uri_).c_str());
  } else if (type == "html") {
    current_uri_ = StringFromValue(request, "baseUri");
    webview_->NavigateToString(Utf8ToWide(StringFromValue(request, "html")).c_str());
  }
  title_ = current_uri_.empty() ? "Papyrus Document" : current_uri_;
  progress_ = 1.0;
  created_ = true;
}

void PapyrusWindowsPlugin::SetViewport(
    const flutter::EncodableMap& args) {
  const double device_pixel_ratio =
      DoubleFromValue(args, "devicePixelRatio", 1);
  bounds_.left = static_cast<LONG>(
      std::round(DoubleFromValue(args, "x") * device_pixel_ratio));
  bounds_.top = static_cast<LONG>(
      std::round(DoubleFromValue(args, "y") * device_pixel_ratio));
  bounds_.right = bounds_.left + static_cast<LONG>(
      std::round(DoubleFromValue(args, "width") * device_pixel_ratio));
  bounds_.bottom = bounds_.top + static_cast<LONG>(
      std::round(DoubleFromValue(args, "height") * device_pixel_ratio));
  visible_ = BoolFromValue(args, "visible") &&
             bounds_.right > bounds_.left && bounds_.bottom > bounds_.top;
  ApplyBounds();
  EnsureWebView();
}

std::optional<LRESULT> PapyrusWindowsPlugin::HandleWindowProc(
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == WM_SIZE || message == WM_MOVE) {
    ApplyBounds();
  }
  return std::nullopt;
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
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      configuration_ = *args;
    }
    software_fallback_attempted_ = false;
    force_software_rendering_ =
        StringFromValue(configuration_, "hardwareAcceleration") == "software";
    created_ = true;
    EnsureWebView();
    result->Success();
  } else if (method == "setViewport") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      SetViewport(*args);
    }
    result->Success();
  } else if (method == "load") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args != nullptr) {
      LoadRequest(*args);
    }
    result->Success();
  } else if (method == "reload") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    if (webview_) {
      webview_->Reload();
    }
    result->Success();
  } else if (method == "stopLoading") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    if (webview_) {
      webview_->Stop();
    }
    result->Success();
  } else if (method == "goBack") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    if (webview_) {
      BOOL can_go_back = FALSE;
      webview_->get_CanGoBack(&can_go_back);
      if (can_go_back) {
        webview_->GoBack();
      }
    }
    result->Success();
  } else if (method == "goForward") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    if (webview_) {
      BOOL can_go_forward = FALSE;
      webview_->get_CanGoForward(&can_go_forward);
      if (can_go_forward) {
        webview_->GoForward();
      }
    }
    result->Success();
  } else if (method == "clearCache" || method == "clearStorage" ||
             method == "printDocument") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    result->Success();
  } else if (method == "dispose") {
    if (controller_) {
      controller_->put_IsVisible(FALSE);
      controller_->Close();
      controller_.Reset();
      webview_.Reset();
      environment_.Reset();
    }
    created_ = false;
    visible_ = false;
    force_software_rendering_ = false;
    software_fallback_attempted_ = false;
    current_uri_.clear();
    title_.clear();
    progress_ = 0.0;
    result->Success();
  } else if (method == "canGoBack") {
    BOOL can_go_back = FALSE;
    if (webview_) {
      webview_->get_CanGoBack(&can_go_back);
    }
    result->Success(flutter::EncodableValue(can_go_back == TRUE));
  } else if (method == "canGoForward") {
    BOOL can_go_forward = FALSE;
    if (webview_) {
      webview_->get_CanGoForward(&can_go_forward);
    }
    result->Success(flutter::EncodableValue(can_go_forward == TRUE));
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
  } else if (method == "debugOverlayState") {
    result->Success(DebugOverlayState());
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
