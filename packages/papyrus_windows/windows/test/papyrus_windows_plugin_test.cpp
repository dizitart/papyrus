#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#define private public
#include "papyrus_windows_plugin.h"
#undef private

namespace papyrus_windows {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(PapyrusWindowsPlugin, GetPlatformVersion) {
  PapyrusWindowsPlugin plugin;
  // Save the reply value from the success callback.
  std::string result_string;
  plugin.HandleMethodCall(
      MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_string](const EncodableValue* result) {
            result_string = std::get<std::string>(*result);
          },
          nullptr, nullptr));

  // Since the exact string varies by host, just ensure that it's a string
  // with the expected format.
  EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
}

TEST(PapyrusWindowsPlugin, HtmlRequestUsesAboutBlankForAppInitiatedUri) {
  PapyrusWindowsPlugin plugin;

  EncodableMap request = {
      {EncodableValue("type"), EncodableValue("html")},
      {EncodableValue("html"), EncodableValue("<p>Hello</p>")},
  };

  EXPECT_EQ(plugin.AppInitiatedUriForRequest(request), "about:blank");
}

TEST(PapyrusWindowsPlugin, EffectiveCurrentUriHidesInternalAboutBlankSource) {
  PapyrusWindowsPlugin plugin;
  plugin.current_uri_ = "https://viewer.example/document";

  EXPECT_EQ(plugin.EffectiveCurrentUriForSource("about:blank"),
            "https://viewer.example/document");
  EXPECT_EQ(plugin.EffectiveCurrentUriForSource(""),
            "https://viewer.example/document");
  EXPECT_EQ(plugin.EffectiveCurrentUriForSource("https://example.com"),
            "https://example.com");
}

TEST(PapyrusWindowsPlugin, CanPresentContentRequiresVisibleViewport) {
  PapyrusWindowsPlugin plugin;

  plugin.visible_ = true;
  EXPECT_TRUE(plugin.CanPresentContent());

  plugin.visible_ = false;
  EXPECT_FALSE(plugin.CanPresentContent());
}

}  // namespace test
}  // namespace papyrus_windows
