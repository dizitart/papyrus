#ifndef FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <string>

namespace papyrus_windows {

class PapyrusWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  PapyrusWindowsPlugin();

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
  std::string current_uri_;
  std::string title_;
  double progress_ = 0.0;

  bool DetectWebView2Runtime();
};

}  // namespace papyrus_windows

#endif  // FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PLUGIN_H_
