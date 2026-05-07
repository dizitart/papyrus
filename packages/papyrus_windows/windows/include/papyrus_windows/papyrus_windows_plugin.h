#ifndef FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PUBLIC_PLUGIN_H_
#define FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PUBLIC_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

FLUTTER_PLUGIN_EXPORT void PapyrusWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // FLUTTER_PLUGIN_PAPYRUS_WINDOWS_PUBLIC_PLUGIN_H_