#include "include/papyrus_linux/papyrus_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>
#include <webkit2/webkit2.h>

#include <cstring>

#include "papyrus_linux_plugin_private.h"

#define PAPYRUS_LINUX_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), papyrus_linux_plugin_get_type(), \
                              PapyrusLinuxPlugin))

struct _PapyrusLinuxPlugin {
  GObject parent_instance;
  WebKitWebView* web_view;
};

G_DEFINE_TYPE(PapyrusLinuxPlugin, papyrus_linux_plugin, g_object_get_type())

static gboolean fl_value_lookup_bool(FlValue* map, const gchar* key,
                                     gboolean fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return fallback;
  }
  return fl_value_get_bool(value);
}

static const gchar* fl_value_lookup_string_or_null(FlValue* map,
                                                   const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static void ensure_web_view(PapyrusLinuxPlugin* self, FlValue* config) {
  if (self->web_view != nullptr) {
    return;
  }
  WebKitSettings* settings = webkit_settings_new();
  webkit_settings_set_enable_javascript(
      settings, fl_value_lookup_bool(config, "allowJavaScript", FALSE));
  webkit_settings_set_javascript_can_open_windows_automatically(
      settings, FALSE);
  webkit_settings_set_enable_write_console_messages_to_stdout(settings, FALSE);
  webkit_settings_set_enable_developer_extras(
      settings, fl_value_lookup_bool(config, "debuggingEnabled", FALSE));

  WebKitUserContentManager* content_manager = webkit_user_content_manager_new();
  self->web_view = WEBKIT_WEB_VIEW(g_object_new(
      WEBKIT_TYPE_WEB_VIEW, "settings", settings, "user-content-manager",
      content_manager, nullptr));
  g_object_unref(settings);
  g_object_unref(content_manager);
}

static FlMethodResponse* success_null() {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse* error_response(const gchar* code,
                                        const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static FlMethodResponse* capabilities_response() {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "supportsResourceInterception",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsVirtualSchemes",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsEphemeralStorage",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsPrint", fl_value_new_bool(FALSE));
  fl_value_set_string_take(result, "supportsSnapshot", fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsAutoHeight",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsDarkMode", fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsDownloadInterception",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(result, "supportsPermissionInterception",
                           fl_value_new_bool(TRUE));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void load_request(PapyrusLinuxPlugin* self, FlValue* request) {
  ensure_web_view(self, nullptr);
  const gchar* type = fl_value_lookup_string_or_null(request, "type");
  if (type == nullptr) {
    return;
  }
  if (strcmp(type, "html") == 0) {
    const gchar* html = fl_value_lookup_string_or_null(request, "html");
    const gchar* base_uri = fl_value_lookup_string_or_null(request, "baseUri");
    webkit_web_view_load_html(self->web_view, html == nullptr ? "" : html,
                              base_uri);
  } else if (strcmp(type, "uri") == 0) {
    const gchar* uri = fl_value_lookup_string_or_null(request, "uri");
    if (uri != nullptr) {
      webkit_web_view_load_uri(self->web_view, uri);
    }
  } else if (strcmp(type, "file") == 0) {
    const gchar* path = fl_value_lookup_string_or_null(request, "absolutePath");
    if (path != nullptr) {
      g_autofree gchar* uri = g_filename_to_uri(path, nullptr, nullptr);
      if (uri != nullptr) {
        webkit_web_view_load_uri(self->web_view, uri);
      }
    }
  }
}

static FlMethodResponse* content_size_response(PapyrusLinuxPlugin* self) {
  g_autoptr(FlValue) result = fl_value_new_map();
  GtkAllocation allocation = {};
  if (self->web_view != nullptr) {
    gtk_widget_get_allocation(GTK_WIDGET(self->web_view), &allocation);
  }
  fl_value_set_string_take(result, "width",
                           fl_value_new_float(allocation.width));
  fl_value_set_string_take(result, "height",
                           fl_value_new_float(allocation.height));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* string_or_null_response(const gchar* value) {
  if (value == nullptr) {
    return success_null();
  }
  g_autoptr(FlValue) result = fl_value_new_string(value);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void papyrus_linux_plugin_handle_method_call(
    PapyrusLinuxPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "create") == 0) {
    ensure_web_view(self, args);
    response = success_null();
  } else if (strcmp(method, "load") == 0) {
    load_request(self, args);
    response = success_null();
  } else if (strcmp(method, "reload") == 0) {
    if (self->web_view != nullptr) webkit_web_view_reload(self->web_view);
    response = success_null();
  } else if (strcmp(method, "stopLoading") == 0) {
    if (self->web_view != nullptr) webkit_web_view_stop_loading(self->web_view);
    response = success_null();
  } else if (strcmp(method, "canGoBack") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(self->web_view != nullptr &&
                          webkit_web_view_can_go_back(self->web_view));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "canGoForward") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(self->web_view != nullptr &&
                          webkit_web_view_can_go_forward(self->web_view));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "goBack") == 0) {
    if (self->web_view != nullptr && webkit_web_view_can_go_back(self->web_view)) {
      webkit_web_view_go_back(self->web_view);
    }
    response = success_null();
  } else if (strcmp(method, "goForward") == 0) {
    if (self->web_view != nullptr &&
        webkit_web_view_can_go_forward(self->web_view)) {
      webkit_web_view_go_forward(self->web_view);
    }
    response = success_null();
  } else if (strcmp(method, "currentUri") == 0) {
    response = string_or_null_response(
        self->web_view == nullptr ? nullptr
                                  : webkit_web_view_get_uri(self->web_view));
  } else if (strcmp(method, "title") == 0) {
    response = string_or_null_response(
        self->web_view == nullptr ? nullptr
                                  : webkit_web_view_get_title(self->web_view));
  } else if (strcmp(method, "estimatedProgress") == 0) {
    g_autoptr(FlValue) result = fl_value_new_float(
        self->web_view == nullptr
            ? 0.0
            : webkit_web_view_get_estimated_load_progress(self->web_view));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "evaluateJavaScript") == 0) {
    response = error_response(
        "unsupportedPlatformFeature",
        "WebKitGTK JavaScript evaluation is asynchronous and is not exposed "
        "through this synchronous method channel implementation yet.");
  } else if (strcmp(method, "getContentSize") == 0) {
    response = content_size_response(self);
  } else if (strcmp(method, "captureSnapshot") == 0) {
    g_autoptr(FlValue) result = fl_value_new_uint8_list(nullptr, 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "printDocument") == 0) {
    response = error_response("unsupportedPlatformFeature",
                              "Printing is not consistently supported by "
                              "the Linux WebKitGTK backend.");
  } else if (strcmp(method, "clearCache") == 0 ||
             strcmp(method, "clearStorage") == 0 ||
             strcmp(method, "dispose") == 0) {
    if (strcmp(method, "dispose") == 0 && self->web_view != nullptr) {
      g_object_unref(self->web_view);
      self->web_view = nullptr;
    }
    response = success_null();
  } else if (strcmp(method, "getCapabilities") == 0) {
    response = capabilities_response();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void papyrus_linux_plugin_dispose(GObject* object) {
  PapyrusLinuxPlugin* self = PAPYRUS_LINUX_PLUGIN(object);
  if (self->web_view != nullptr) {
    g_object_unref(self->web_view);
    self->web_view = nullptr;
  }
  G_OBJECT_CLASS(papyrus_linux_plugin_parent_class)->dispose(object);
}

static void papyrus_linux_plugin_class_init(PapyrusLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = papyrus_linux_plugin_dispose;
}

static void papyrus_linux_plugin_init(PapyrusLinuxPlugin* self) {
  self->web_view = nullptr;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  PapyrusLinuxPlugin* plugin = PAPYRUS_LINUX_PLUGIN(user_data);
  papyrus_linux_plugin_handle_method_call(plugin, method_call);
}

void papyrus_linux_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PapyrusLinuxPlugin* plugin = PAPYRUS_LINUX_PLUGIN(
      g_object_new(papyrus_linux_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.papyrus.papyrus_linux", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
