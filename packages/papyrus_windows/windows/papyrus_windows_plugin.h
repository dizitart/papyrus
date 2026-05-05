#ifndef FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <wrl.h>

#include <memory>
#include <optional>
#include <string>

struct ICoreWebView2;
struct ICoreWebView2Controller;
struct ICoreWebView2Environment;
struct ICoreWebView2EnvironmentOptions;

namespace papyrus_windows {

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
  bool force_software_rendering_ = false;
  bool software_fallback_attempted_ = false;
  RECT bounds_ = {};
  HWND hwnd_ = nullptr;
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  int window_proc_delegate_id_ = 0;
  flutter::EncodableMap configuration_;
  flutter::EncodableMap pending_load_;
  std::string current_uri_;
  std::string title_;
  double progress_ = 0.0;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  Microsoft::WRL::ComPtr<ICoreWebView2EnvironmentOptions> environment_options_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> webview_;

  bool DetectWebView2Runtime();
  void EnsureWebView();
  void ApplySettings();
  void ApplyBounds();
  void RunPendingLoad();
  bool RetryWithSoftwareFallback();
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
