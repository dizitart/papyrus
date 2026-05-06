#include "papyrus_windows_plugin.h"

#include <windows.h>
#include <WebView2.h>
#include <WebView2EnvironmentOptions.h>

#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstring>
#include <map>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>
#include <wrl.h>

namespace papyrus_windows {
namespace {
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

constexpr char kDefaultVirtualResourceScheme[] = "papyrus-resource";

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

const flutter::EncodableMap* MapFromValue(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr
                          : std::get_if<flutter::EncodableMap>(value);
}

const flutter::EncodableList* ListFromValue(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr
                          : std::get_if<flutter::EncodableList>(value);
}

std::string StringFromEncodableValue(const flutter::EncodableValue* value,
                                     const std::string& fallback = "") {
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* string_value = std::get_if<std::string>(value)) {
    return *string_value;
  }
  return fallback;
}

int IntFromEncodableValue(const flutter::EncodableValue* value,
                          int fallback = 0) {
  if (value == nullptr) {
    return fallback;
  }
  if (const auto* int32_value = std::get_if<int32_t>(value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(value)) {
    return static_cast<int>(*int64_value);
  }
  if (const auto* double_value = std::get_if<double>(value)) {
    return static_cast<int>(*double_value);
  }
  return fallback;
}

std::vector<uint8_t> BytesFromValue(const flutter::EncodableValue* value) {
  const auto* list = ListFromValue(value);
  if (list == nullptr) {
    return {};
  }

  std::vector<uint8_t> bytes;
  bytes.reserve(list->size());
  for (const auto& entry : *list) {
    int element = IntFromEncodableValue(&entry, 0);
    bytes.push_back(static_cast<uint8_t>(std::clamp(element, 0, 255)));
  }
  return bytes;
}

std::map<std::string, std::string> StringMapFromValue(
    const flutter::EncodableValue* value) {
  std::map<std::string, std::string> result;
  const auto* map = MapFromValue(value);
  if (map == nullptr) {
    return result;
  }

  for (const auto& entry : *map) {
    const auto* key = std::get_if<std::string>(&entry.first);
    const auto* string_value = std::get_if<std::string>(&entry.second);
    if (key == nullptr || string_value == nullptr) {
      continue;
    }
    result[*key] = *string_value;
  }
  return result;
}

std::optional<PapyrusWindowsInlineResource> InlineResourceFromMap(
    const flutter::EncodableMap* map) {
  if (map == nullptr) {
    return std::nullopt;
  }

  PapyrusWindowsInlineResource resource;
  const auto bytes_iterator = map->find(flutter::EncodableValue("bytes"));
  if (bytes_iterator != map->end()) {
    resource.bytes = BytesFromValue(&bytes_iterator->second);
  }
  const auto mime_iterator = map->find(flutter::EncodableValue("mimeType"));
  if (mime_iterator != map->end()) {
    resource.mime_type =
        StringFromEncodableValue(&mime_iterator->second, resource.mime_type);
  }
  const auto status_iterator =
      map->find(flutter::EncodableValue("statusCode"));
  if (status_iterator != map->end()) {
    resource.status_code = IntFromEncodableValue(&status_iterator->second, 200);
  }
  const auto headers_iterator = map->find(flutter::EncodableValue("headers"));
  if (headers_iterator != map->end()) {
    resource.headers = StringMapFromValue(&headers_iterator->second);
  }
  return resource;
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

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string utf8(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), utf8.data(), size,
                      nullptr, nullptr);
  return utf8;
}

std::wstring FileUriFromPath(const std::string& path) {
  std::wstring uri = L"file:///";
  std::wstring wide_path = Utf8ToWide(path);
  for (wchar_t value : wide_path) {
    uri.push_back(value == L'\\' ? L'/' : value);
  }
  return uri;
}

bool IsBuiltInScheme(const std::string& scheme) {
  return scheme == "http" || scheme == "https" || scheme == "file" ||
         scheme == "about" || scheme == "data" || scheme == "blob";
}

std::string SanitizeCustomScheme(const std::string& scheme) {
  if (scheme.empty()) {
    return kDefaultVirtualResourceScheme;
  }
  std::string trimmed = scheme;
  trimmed.erase(trimmed.begin(),
                std::find_if(trimmed.begin(), trimmed.end(), [](unsigned char c) {
                  return !std::isspace(c);
                }));
  trimmed.erase(
      std::find_if(trimmed.rbegin(), trimmed.rend(), [](unsigned char c) {
        return !std::isspace(c);
      }).base(),
      trimmed.end());
  if (trimmed.empty()) {
    return kDefaultVirtualResourceScheme;
  }
  std::transform(trimmed.begin(), trimmed.end(), trimmed.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return trimmed;
}

std::string ReasonPhrase(int status_code) {
  switch (status_code) {
    case 200:
      return "OK";
    case 403:
      return "Blocked";
    case 404:
      return "Not Found";
    default:
      return "Papyrus";
  }
}

std::string ResourceTypeForUri(const std::string& uri, bool is_main_frame) {
  if (is_main_frame) {
    return "document";
  }

  std::string lower = uri;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  if (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".css") == 0) {
    return "stylesheet";
  }
  if ((lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".png") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".jpg") == 0) ||
      (lower.size() >= 5 && lower.compare(lower.size() - 5, 5, ".jpeg") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".gif") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".svg") == 0) ||
      (lower.size() >= 5 && lower.compare(lower.size() - 5, 5, ".webp") == 0)) {
    return "image";
  }
  if ((lower.size() >= 5 && lower.compare(lower.size() - 5, 5, ".woff") == 0) ||
      (lower.size() >= 6 && lower.compare(lower.size() - 6, 6, ".woff2") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".ttf") == 0)) {
    return "font";
  }
  if (lower.size() >= 3 && lower.compare(lower.size() - 3, 3, ".js") == 0) {
    return "script";
  }
  if ((lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".mp4") == 0) ||
      (lower.size() >= 5 && lower.compare(lower.size() - 5, 5, ".webm") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".mp3") == 0) ||
      (lower.size() >= 4 && lower.compare(lower.size() - 4, 4, ".wav") == 0)) {
    return "media";
  }
  return "other";
}

ComPtr<IStream> CreateMemoryStream(const std::vector<uint8_t>& bytes) {
  const size_t allocation_size = std::max<size_t>(bytes.size(), 1);
  HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, allocation_size);
  if (handle == nullptr) {
    return nullptr;
  }

  void* buffer = GlobalLock(handle);
  if (buffer == nullptr) {
    GlobalFree(handle);
    return nullptr;
  }
  if (!bytes.empty()) {
    std::memcpy(buffer, bytes.data(), bytes.size());
  }
  GlobalUnlock(handle);

  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(handle, TRUE, &stream)) || !stream) {
    GlobalFree(handle);
    return nullptr;
  }

  ULARGE_INTEGER size = {};
  size.QuadPart = bytes.size();
  stream->SetSize(size);
  LARGE_INTEGER start = {};
  stream->Seek(start, STREAM_SEEK_SET, nullptr);
  return stream;
}

std::wstring HeadersStringForResource(const PapyrusWindowsInlineResource& resource) {
  std::wstringstream headers;
  bool has_content_type = false;
  for (const auto& entry : resource.headers) {
    std::string key_lower = entry.first;
    std::transform(key_lower.begin(), key_lower.end(), key_lower.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (key_lower == "content-type") {
      has_content_type = true;
    }
    headers << Utf8ToWide(entry.first) << L": " << Utf8ToWide(entry.second)
            << L"\r\n";
  }
  if (!has_content_type) {
    headers << L"Content-Type: " << Utf8ToWide(resource.mime_type) << L"\r\n";
  }
  return headers.str();
}

ComPtr<ICoreWebView2WebResourceResponse> CreateWebResourceResponse(
    ICoreWebView2Environment* environment,
    const PapyrusWindowsInlineResource& resource) {
  if (environment == nullptr) {
    return nullptr;
  }
  ComPtr<IStream> stream = CreateMemoryStream(resource.bytes);
  ComPtr<ICoreWebView2WebResourceResponse> response;
  const std::wstring reason = Utf8ToWide(ReasonPhrase(resource.status_code));
  const std::wstring headers = HeadersStringForResource(resource);
  if (FAILED(environment->CreateWebResourceResponse(
          stream.Get(), resource.status_code, reason.c_str(), headers.c_str(),
          &response))) {
    return nullptr;
  }
  return response;
}

PapyrusWindowsInlineResource StatusOnlyResource(int status_code) {
  PapyrusWindowsInlineResource resource;
  resource.status_code = status_code;
  resource.mime_type = "text/plain";
  return resource;
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

std::string SelectedTextScript() {
  return "(() => { const selection = window.getSelection ? window.getSelection().toString() : ''; return selection ? encodeURIComponent(selection) : null; })()";
}

std::string DecodeExecuteScriptStringResult(const std::wstring& value) {
  std::string utf8 = WideToUtf8(value);
  if (utf8.empty() || utf8 == "null") {
    return std::string();
  }
  if (utf8.size() >= 2 && utf8.front() == '"' && utf8.back() == '"') {
    return utf8.substr(1, utf8.size() - 2);
  }
  return utf8;
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
  auto plugin = std::make_unique<PapyrusWindowsPlugin>(registrar);
  plugin->channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.papyrus.papyrus_windows",
          &flutter::StandardMethodCodec::GetInstance());

  plugin->channel_->SetMethodCallHandler(
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
  if (webview_ && web_resource_requested_registered_) {
    EventRegistrationToken token = {};
    token.value = web_resource_requested_token_value_;
    webview_->remove_WebResourceRequested(token);
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
  environment_options_.Reset();
  custom_scheme_registration_.Reset();
  environment_options_ = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  if (environment_options_) {
    if (StringFromValue(configuration_, "hardwareAcceleration") == "software" ||
        force_software_rendering_) {
      environment_options_->put_AdditionalBrowserArguments(L"--disable-gpu");
    }
    ComPtr<ICoreWebView2EnvironmentOptions4> environment_options4;
    if (!IsBuiltInScheme(virtual_resource_scheme_) &&
        SUCCEEDED(environment_options_.As(&environment_options4)) &&
        environment_options4) {
      custom_scheme_registration_ =
          Microsoft::WRL::Make<CoreWebView2CustomSchemeRegistration>(
              Utf8ToWide(virtual_resource_scheme_).c_str());
      if (custom_scheme_registration_) {
        custom_scheme_registration_->put_HasAuthorityComponent(TRUE);
        custom_scheme_registration_->put_TreatAsSecure(TRUE);
        ICoreWebView2CustomSchemeRegistration* registrations[] = {
            custom_scheme_registration_.Get()};
        environment_options4->SetCustomSchemeRegistrations(1, registrations);
      }
    }
  }

  ICoreWebView2EnvironmentOptions* environment_options_ptr =
      environment_options_.Get();
  HRESULT result = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, nullptr, environment_options_ptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this](HRESULT result, ICoreWebView2Environment* environment)
              -> HRESULT {
            creating_ = false;
            environment_options_.Reset();
            custom_scheme_registration_.Reset();
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
                      RegisterResourceInterceptor();
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
    custom_scheme_registration_.Reset();
    if (RetryWithSoftwareFallback()) {
      return;
    }
    webview2_available_ = false;
  }
}

void PapyrusWindowsPlugin::RegisterResourceInterceptor() {
  if (!webview_ || web_resource_requested_registered_ ||
      IsBuiltInScheme(virtual_resource_scheme_)) {
    return;
  }

  const std::wstring filter = Utf8ToWide(virtual_resource_scheme_ + "://*");
  if (FAILED(webview_->AddWebResourceRequestedFilter(
          filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL))) {
    return;
  }

  EventRegistrationToken token = {};
  if (FAILED(webview_->add_WebResourceRequested(
          Callback<ICoreWebView2WebResourceRequestedEventHandler>(
              [this](ICoreWebView2* sender,
                     ICoreWebView2WebResourceRequestedEventArgs* args)
                  -> HRESULT { return HandleResourceRequested(args); })
              .Get(),
          &token))) {
    return;
  }

  web_resource_requested_registered_ = true;
  web_resource_requested_token_value_ = token.value;
}

HRESULT PapyrusWindowsPlugin::HandleResourceRequested(
    ICoreWebView2WebResourceRequestedEventArgs* args) {
  if (!args || !environment_) {
    return S_OK;
  }

  ComPtr<ICoreWebView2WebResourceRequest> request;
  if (FAILED(args->get_Request(&request)) || !request) {
    return S_OK;
  }

  LPWSTR raw_uri = nullptr;
  if (FAILED(request->get_Uri(&raw_uri)) || raw_uri == nullptr) {
    return S_OK;
  }
  std::wstring uri_wide(raw_uri);
  CoTaskMemFree(raw_uri);
  const std::string uri = WideToUtf8(uri_wide);

  const auto inline_resource = virtual_resources_.find(uri);
  if (inline_resource != virtual_resources_.end()) {
    ComPtr<ICoreWebView2WebResourceResponse> response =
        CreateWebResourceResponse(environment_.Get(), inline_resource->second);
    if (response) {
      args->put_Response(response.Get());
    }
    return S_OK;
  }

  if (!resource_resolver_enabled_ || !channel_) {
    PapyrusWindowsInlineResource response_resource = StatusOnlyResource(404);
    ComPtr<ICoreWebView2WebResourceResponse> response =
        CreateWebResourceResponse(environment_.Get(), response_resource);
    if (response) {
      args->put_Response(response.Get());
    }
    return S_OK;
  }

  ComPtr<ICoreWebView2Deferral> deferral;
  if (FAILED(args->GetDeferral(&deferral)) || !deferral) {
    PapyrusWindowsInlineResource response_resource = StatusOnlyResource(403);
    ComPtr<ICoreWebView2WebResourceResponse> response =
        CreateWebResourceResponse(environment_.Get(), response_resource);
    if (response) {
      args->put_Response(response.Get());
    }
    return S_OK;
  }

  LPWSTR raw_method = nullptr;
  std::string method = "GET";
  if (SUCCEEDED(request->get_Method(&raw_method)) && raw_method != nullptr) {
    method = WideToUtf8(raw_method);
    CoTaskMemFree(raw_method);
  }

  bool is_main_frame = false;
  if (webview_) {
    LPWSTR raw_source = nullptr;
    if (SUCCEEDED(webview_->get_Source(&raw_source)) && raw_source != nullptr) {
      is_main_frame = uri_wide == raw_source;
      CoTaskMemFree(raw_source);
    }
  }

  flutter::EncodableMap arguments = {
      {flutter::EncodableValue("uri"), flutter::EncodableValue(uri)},
      {flutter::EncodableValue("method"), flutter::EncodableValue(method)},
      {flutter::EncodableValue("headers"),
       flutter::EncodableValue(flutter::EncodableMap{})},
      {flutter::EncodableValue("resourceType"),
       flutter::EncodableValue(ResourceTypeForUri(uri, is_main_frame))},
      {flutter::EncodableValue("isMainFrame"), flutter::EncodableValue(is_main_frame)},
  };

  ComPtr<ICoreWebView2Environment> environment = environment_;
  ComPtr<ICoreWebView2WebResourceRequestedEventArgs> pending_args = args;
  channel_->InvokeMethod(
      "resourceRequest",
      std::make_unique<flutter::EncodableValue>(std::move(arguments)),
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          [environment, pending_args, deferral](const flutter::EncodableValue* result) {
            PapyrusWindowsInlineResource response_resource = StatusOnlyResource(403);
            const auto* map = MapFromValue(result);
            const std::string decision =
                map == nullptr ? std::string() : StringFromValue(*map, "decision");
            if (decision == "respond") {
              const auto response_iterator =
                  map->find(flutter::EncodableValue("response"));
              if (response_iterator != map->end()) {
                if (const auto response_map =
                        MapFromValue(&response_iterator->second)) {
                  auto parsed_resource = InlineResourceFromMap(response_map);
                  if (parsed_resource.has_value()) {
                    response_resource = std::move(parsed_resource.value());
                  }
                }
              }
            } else if (decision == "allow") {
              response_resource = StatusOnlyResource(404);
            }

            ComPtr<ICoreWebView2WebResourceResponse> response =
                CreateWebResourceResponse(environment.Get(), response_resource);
            if (response) {
              pending_args->put_Response(response.Get());
            }
            deferral->Complete();
          },
          [environment, pending_args, deferral](const std::string& error_code,
                                                const std::string& error_message,
                                                const flutter::EncodableValue* error_details) {
            PapyrusWindowsInlineResource response_resource = StatusOnlyResource(403);
            ComPtr<ICoreWebView2WebResourceResponse> response =
                CreateWebResourceResponse(environment.Get(), response_resource);
            if (response) {
              pending_args->put_Response(response.Get());
            }
            deferral->Complete();
          },
          [environment, pending_args, deferral]() {
            PapyrusWindowsInlineResource response_resource = StatusOnlyResource(403);
            ComPtr<ICoreWebView2WebResourceResponse> response =
                CreateWebResourceResponse(environment.Get(), response_resource);
            if (response) {
              pending_args->put_Response(response.Get());
            }
            deferral->Complete();
          }));
  return S_OK;
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
    settings->put_AreDefaultContextMenusEnabled(
      BoolFromValue(configuration_, "allowContextMenu", true) ? TRUE : FALSE);
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
  UpdateVirtualResources(request);
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

bool IsFileLoadAllowed(const flutter::EncodableMap& configuration,
                       const flutter::EncodableMap& request) {
  const bool allow_file_access =
      BoolFromValue(configuration, "allowFileAccess", false);
  const std::string type = StringFromValue(request, "type");
  if (type == "file") {
    return allow_file_access;
  }
  if (type != "uri") {
    return true;
  }
  const std::string uri = StringFromValue(request, "uri");
  return uri.rfind("file://", 0) != 0 || allow_file_access;
}

void PapyrusWindowsPlugin::UpdateVirtualResources(
    const flutter::EncodableMap& request) {
  virtual_resources_.clear();
  const auto iterator = request.find(flutter::EncodableValue("virtualResources"));
  if (iterator == request.end()) {
    return;
  }

  const auto* resources = ListFromValue(&iterator->second);
  if (resources == nullptr) {
    return;
  }

  for (const auto& entry : *resources) {
    const auto* resource_map = MapFromValue(&entry);
    if (resource_map == nullptr) {
      continue;
    }
    const std::string uri = StringFromValue(*resource_map, "uri");
    auto resource = InlineResourceFromMap(resource_map);
    if (uri.empty() || !resource.has_value()) {
      continue;
    }
    virtual_resources_[uri] = std::move(resource.value());
  }
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
    resource_resolver_enabled_ =
        BoolFromValue(configuration_, "resourceResolverEnabled", false);
    virtual_resource_scheme_ =
        SanitizeCustomScheme(StringFromValue(configuration_, "virtualResourceScheme"));
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
      if (!IsFileLoadAllowed(configuration_, *args)) {
        result->Error(
            "navigationBlocked",
            "File loading is disabled by the current Papyrus security policy.");
        return;
      }
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
  } else if (method == "setResourceResolverEnabled") {
    resource_resolver_enabled_ = false;
    if (const auto* enabled = std::get_if<bool>(method_call.arguments())) {
      resource_resolver_enabled_ = *enabled;
    }
    result->Success();
  } else if (method == "setNavigationResolverEnabled") {
    result->Success();
  } else if (method == "dispose") {
    if (webview_ && web_resource_requested_registered_) {
      EventRegistrationToken token = {};
      token.value = web_resource_requested_token_value_;
      webview_->remove_WebResourceRequested(token);
      web_resource_requested_registered_ = false;
      web_resource_requested_token_value_ = 0;
    }
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
    resource_resolver_enabled_ = false;
    virtual_resources_.clear();
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
  } else if (method == "selectedText") {
    if (!webview2_available_) {
      UnsupportedWebView2(std::move(result));
      return;
    }
    if (!webview_) {
      result->Success(flutter::EncodableValue());
      return;
    }
    auto* raw_result = result.release();
    webview_->ExecuteScript(
        Utf8ToWide(SelectedTextScript()).c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [raw_result](HRESULT error_code, LPCWSTR json_result) -> HRESULT {
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                  result(raw_result);
              if (FAILED(error_code)) {
                result->Error(
                    "papyrus_windows",
                    "Failed to query selected text from WebView2.");
                return S_OK;
              }
              const std::wstring raw_value =
                  json_result == nullptr ? std::wstring() : json_result;
              const std::string decoded =
                  DecodeExecuteScriptStringResult(raw_value);
              if (decoded.empty()) {
                result->Success(flutter::EncodableValue());
              } else {
                result->Success(flutter::EncodableValue(decoded));
              }
              return S_OK;
            })
            .Get());
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
