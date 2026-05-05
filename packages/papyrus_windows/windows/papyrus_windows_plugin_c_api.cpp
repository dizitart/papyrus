#include "include/papyrus_windows/papyrus_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "papyrus_windows_plugin.h"

void PapyrusWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  papyrus_windows::PapyrusWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
