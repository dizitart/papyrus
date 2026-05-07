# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "papyrus_windows")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "papyrus_windows_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "papyrus_windows_plugin.cpp"
  "papyrus_windows_plugin.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/papyrus_windows/papyrus_windows_plugin_c_api.h"
  "papyrus_windows_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

set(WEBVIEW2_VERSION "1.0.3124.44")
set(WEBVIEW2_ROOT "${CMAKE_CURRENT_BINARY_DIR}/nuget/Microsoft.Web.WebView2")
if (NOT EXISTS "${WEBVIEW2_ROOT}/build/native/include/WebView2.h")
  find_program(NUGET_EXE nuget)
  if (NUGET_EXE)
    execute_process(
      COMMAND "${NUGET_EXE}" install Microsoft.Web.WebView2
        -Version ${WEBVIEW2_VERSION}
        -OutputDirectory "${CMAKE_CURRENT_BINARY_DIR}/nuget"
        -ExcludeVersion
      RESULT_VARIABLE WEBVIEW2_NUGET_RESULT
    )
    if (NOT WEBVIEW2_NUGET_RESULT EQUAL 0)
      message(FATAL_ERROR "Failed to restore Microsoft.Web.WebView2 ${WEBVIEW2_VERSION}.")
    endif()
  else()
    file(MAKE_DIRECTORY "${WEBVIEW2_ROOT}")
    set(WEBVIEW2_NUPKG "${CMAKE_CURRENT_BINARY_DIR}/nuget/Microsoft.Web.WebView2.${WEBVIEW2_VERSION}.nupkg")
    file(DOWNLOAD
      "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/${WEBVIEW2_VERSION}/microsoft.web.webview2.${WEBVIEW2_VERSION}.nupkg"
      "${WEBVIEW2_NUPKG}"
      STATUS WEBVIEW2_DOWNLOAD_STATUS
      TLS_VERIFY ON
    )
    list(GET WEBVIEW2_DOWNLOAD_STATUS 0 WEBVIEW2_DOWNLOAD_CODE)
    if (NOT WEBVIEW2_DOWNLOAD_CODE EQUAL 0)
      message(FATAL_ERROR "Failed to download Microsoft.Web.WebView2 ${WEBVIEW2_VERSION}. Install nuget.exe or pre-populate ${WEBVIEW2_ROOT}.")
    endif()
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xvf "${WEBVIEW2_NUPKG}"
      WORKING_DIRECTORY "${WEBVIEW2_ROOT}"
      RESULT_VARIABLE WEBVIEW2_EXTRACT_RESULT
    )
    if (NOT WEBVIEW2_EXTRACT_RESULT EQUAL 0)
      message(FATAL_ERROR "Failed to extract ${WEBVIEW2_NUPKG}.")
    endif()
  endif()
endif()

if (DEFINED FLUTTER_TARGET_PLATFORM)
  if (FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
    set(WEBVIEW2_ARCH "arm64")
  elseif (FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64")
    set(WEBVIEW2_ARCH "x64")
  elseif (FLUTTER_TARGET_PLATFORM STREQUAL "windows-x86")
    set(WEBVIEW2_ARCH "x86")
  endif()
endif()

if (NOT DEFINED WEBVIEW2_ARCH)
  if (CMAKE_VS_PLATFORM_NAME STREQUAL "ARM64")
    set(WEBVIEW2_ARCH "arm64")
  elseif (CMAKE_VS_PLATFORM_NAME STREQUAL "x64")
    set(WEBVIEW2_ARCH "x64")
  elseif (CMAKE_VS_PLATFORM_NAME STREQUAL "Win32")
    set(WEBVIEW2_ARCH "x86")
  elseif (CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(WEBVIEW2_ARCH "x64")
  else()
    set(WEBVIEW2_ARCH "x86")
  endif()
endif()

target_include_directories(${PLUGIN_NAME} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(papyrus_windows_bundled_libraries
  ""
  PARENT_SCOPE
)

# === Tests ===
# These unit tests can be run from a terminal after building the example, or
# from Visual Studio after opening the generated solution file.

# Only enable test builds when building the example (which sets this variable)
# so that plugin clients aren't building the tests.
if (${include_${PROJECT_NAME}_tests})
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

# Add the Google Test dependency.
include(FetchContent)
if (NOT DEFINED CMAKE_POLICY_VERSION_MINIMUM)
  set(CMAKE_POLICY_VERSION_MINIMUM 3.10 CACHE STRING "Minimum policy version for bundled test dependencies" FORCE)
endif()
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/release-1.11.0.zip
)
# Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
# Disable install commands for gtest so it doesn't end up in the bundle.
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
FetchContent_MakeAvailable(googletest)

# The plugin's C API is not very useful for unit testing, so build the sources
# directly into the test binary rather than using the DLL.
add_executable(${TEST_RUNNER}
  test/papyrus_windows_plugin_test.cpp
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(${TEST_RUNNER} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/include")
target_link_libraries(${TEST_RUNNER} PRIVATE flutter_wrapper_plugin)
target_link_libraries(${TEST_RUNNER} PRIVATE
  "${WEBVIEW2_ROOT}/build/native/${WEBVIEW2_ARCH}/WebView2LoaderStatic.lib")
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
# flutter_wrapper_plugin has link dependencies on the Flutter DLL.
add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>
)

# Enable automatic test discovery.
include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})
endif()
