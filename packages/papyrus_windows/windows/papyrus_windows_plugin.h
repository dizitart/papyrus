#ifndef FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <wrl.h>

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

struct ICoreWebView2;
struct ICoreWebView2Controller;
struct ICoreWebView2CustomSchemeRegistration;
struct ICoreWebView2Deferral;
struct ICoreWebView2Environment;
struct ICoreWebView2EnvironmentOptions;
struct ICoreWebView2NavigationStartingEventArgs;
struct ICoreWebView2NewWindowRequestedEventArgs;
struct ICoreWebView2WebResourceRequestedEventArgs;

namespace papyrus_windows {

struct PapyrusWindowsInlineResource {
  std::vector<uint8_t> bytes;
  std::string mime_type = "application/octet-stream";
  int status_code = 200;
  std::map<std::string, std::string> headers;
};

class PapyrusWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  PapyrusWindowsPlugin();

  explicit PapyrusWindowsPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~PapyrusWindowsPlugin();

  // Disallow copy and assign.
  PapyrusWindowsPlugin(const PapyrusWindowsPlugin&) = delete;
  PapyrusWindowsPlugin& operator=(const PapyrusWindowsPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  bool webview2_available_ = false;
  bool created_ = false;
  bool creating_ = false;
  bool visible_ = false;
  bool navigation_resolver_enabled_ = false;
  bool resource_resolver_enabled_ = false;
  bool navigation_starting_registered_ = false;
  bool new_window_requested_registered_ = false;
  bool web_resource_requested_registered_ = false;
  bool force_software_rendering_ = false;
  bool software_fallback_attempted_ = false;
  RECT bounds_ = {};
  HWND hwnd_ = nullptr;
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  int window_proc_delegate_id_ = 0;
  int64_t navigation_starting_token_value_ = 0;
  int64_t new_window_requested_token_value_ = 0;
  int64_t web_resource_requested_token_value_ = 0;
  flutter::EncodableMap configuration_;
  flutter::EncodableMap pending_load_;
  std::vector<std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>>
      pending_create_results_;
  std::string current_uri_;
  std::string title_;
  std::string virtual_resource_scheme_ = "papyrus-resource";
  double progress_ = 0.0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unordered_set<std::string> app_initiated_navigations_;
  std::unordered_map<std::string, PapyrusWindowsInlineResource>
      virtual_resources_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2EnvironmentOptions> environment_options_;
  Microsoft::WRL::ComPtr<ICoreWebView2CustomSchemeRegistration>
      custom_scheme_registration_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;

  bool DetectWebView2Runtime();
  void EnsureWebView();
  void ApplySettings();
  void ApplyBounds();
  void CompletePendingCreateResults();
  void FailPendingCreateResults(const std::string& code,
                                const std::string& message);
  void RunPendingLoad();
  void SchedulePendingLoad();
  void RegisterNavigationInterceptor();
  void UpdateVirtualResources(const flutter::EncodableMap& request);
  void RegisterResourceInterceptor();
  HRESULT HandleNavigationStarting(
      ICoreWebView2NavigationStartingEventArgs* args);
  HRESULT HandleNewWindowRequested(
      ICoreWebView2NewWindowRequestedEventArgs* args);
  HRESULT HandleResourceRequested(
      ICoreWebView2WebResourceRequestedEventArgs* args);
  void MarkAppInitiatedNavigation(const std::string& uri);
  bool ConsumeAppInitiatedNavigation(const std::string& uri);
  bool RetryWithSoftwareFallback();

 public:
  std::string AppInitiatedUriForRequest(
      const flutter::EncodableMap& request) const;
  std::string EffectiveCurrentUriForSource(const std::string& source) const;
  bool CanPresentContent() const;

 private:
  flutter::EncodableValue DebugOverlayState() const;
  void LoadRequest(const flutter::EncodableMap& request);
  void SetViewport(const flutter::EncodableMap& args);
  std::optional<LRESULT> HandleWindowProc(HWND hwnd,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam);
};

}  // namespace papyrus_windows

#endif  // FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_
