#include "include/papyrus_linux/papyrus_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <sys/utsname.h>
#include <webkit2/webkit2.h>

#include <algorithm>
#include <cstring>

#include "papyrus_linux_plugin_private.h"

#define PAPYRUS_LINUX_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), papyrus_linux_plugin_get_type(), \
                              PapyrusLinuxPlugin))

namespace {

constexpr char kDefaultVirtualResourceScheme[] = "papyrus-resource";

typedef struct {
  GBytes* bytes;
  gchar* mime_type;
  gint status_code;
  GHashTable* headers;
} PapyrusLinuxInlineResource;

typedef struct {
  PapyrusLinuxPlugin* plugin;
  WebKitURISchemeRequest* request;
} PapyrusLinuxSchemeInvocation;

static void papyrus_linux_inline_resource_free(
    PapyrusLinuxInlineResource* resource) {
  if (resource == nullptr) {
    return;
  }
  if (resource->bytes != nullptr) {
    g_bytes_unref(resource->bytes);
  }
  g_clear_pointer(&resource->mime_type, g_free);
  if (resource->headers != nullptr) {
    g_hash_table_unref(resource->headers);
  }
  g_free(resource);
}

static void papyrus_linux_scheme_invocation_free(
    PapyrusLinuxSchemeInvocation* invocation) {
  if (invocation == nullptr) {
    return;
  }
  if (invocation->plugin != nullptr) {
    g_object_unref(invocation->plugin);
  }
  if (invocation->request != nullptr) {
    g_object_unref(invocation->request);
  }
  g_free(invocation);
}

static gboolean is_builtin_scheme(const gchar* scheme) {
  return g_strcmp0(scheme, "http") == 0 || g_strcmp0(scheme, "https") == 0 ||
         g_strcmp0(scheme, "file") == 0 || g_strcmp0(scheme, "about") == 0 ||
         g_strcmp0(scheme, "data") == 0 || g_strcmp0(scheme, "blob") == 0;
}

static gchar* sanitize_custom_scheme(const gchar* scheme) {
  if (scheme == nullptr) {
    return g_strdup(kDefaultVirtualResourceScheme);
  }

  g_autofree gchar* stripped = g_strstrip(g_strdup(scheme));
  if (stripped[0] == '\0') {
    return g_strdup(kDefaultVirtualResourceScheme);
  }

  return g_ascii_strdown(stripped, -1);
}

static gint fl_value_lookup_int(FlValue* map, const gchar* key, gint fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<gint>(fl_value_get_int(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<gint>(fl_value_get_float(value));
  }
  return fallback;
}

static GHashTable* fl_value_to_string_hash_table(FlValue* value) {
  GHashTable* result = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                             g_free);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) {
    return result;
  }

  const size_t length = fl_value_get_length(value);
  for (size_t index = 0; index < length; ++index) {
    FlValue* key = fl_value_get_map_key(value, index);
    FlValue* entry = fl_value_get_map_value(value, index);
    if (key == nullptr || entry == nullptr ||
        fl_value_get_type(key) != FL_VALUE_TYPE_STRING ||
        fl_value_get_type(entry) != FL_VALUE_TYPE_STRING) {
      continue;
    }
    g_hash_table_insert(result, g_strdup(fl_value_get_string(key)),
                        g_strdup(fl_value_get_string(entry)));
  }
  return result;
}

static GBytes* fl_value_to_bytes(FlValue* value) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_LIST) {
    return g_bytes_new(nullptr, 0);
  }

  const size_t length = fl_value_get_length(value);
  guint8* bytes = static_cast<guint8*>(g_malloc(length == 0 ? 1 : length));
  for (size_t index = 0; index < length; ++index) {
    FlValue* entry = fl_value_get_list_value(value, index);
    gint element = 0;
    if (entry != nullptr) {
      if (fl_value_get_type(entry) == FL_VALUE_TYPE_INT) {
        element = static_cast<gint>(fl_value_get_int(entry));
      } else if (fl_value_get_type(entry) == FL_VALUE_TYPE_FLOAT) {
        element = static_cast<gint>(fl_value_get_float(entry));
      }
    }
    bytes[index] = static_cast<guint8>(std::clamp(element, 0, 255));
  }
  return g_bytes_new_take(bytes, length);
}

static PapyrusLinuxInlineResource* inline_resource_from_value(FlValue* value) {
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }

  auto* resource = g_new0(PapyrusLinuxInlineResource, 1);
  resource->bytes = fl_value_to_bytes(fl_value_lookup_string(value, "bytes"));
  resource->mime_type = g_strdup(
      fl_value_lookup_string_or_null(value, "mimeType") != nullptr
          ? fl_value_lookup_string_or_null(value, "mimeType")
          : "application/octet-stream");
  resource->status_code = fl_value_lookup_int(value, "statusCode", 200);
  resource->headers =
      fl_value_to_string_hash_table(fl_value_lookup_string(value, "headers"));
  return resource;
}

static const gchar* reason_phrase_for_status(gint status_code) {
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

static void finish_request_with_status(WebKitURISchemeRequest* request,
                                       gint status_code,
                                       const gchar* message) {
#if WEBKIT_CHECK_VERSION(2, 36, 0)
  g_autoptr(GInputStream) stream =
      g_memory_input_stream_new_from_data(nullptr, 0, nullptr);
  g_autoptr(WebKitURISchemeResponse) response =
      webkit_uri_scheme_response_new(stream, 0);
  webkit_uri_scheme_response_set_content_type(response, "text/plain");
  webkit_uri_scheme_response_set_status(response, status_code,
                                        reason_phrase_for_status(status_code));
  webkit_uri_scheme_request_finish_with_response(request, response);
#else
  g_autoptr(GError) error = g_error_new_literal(
      g_quark_from_static_string("papyrus-linux"), status_code, message);
  webkit_uri_scheme_request_finish_error(request, error);
#endif
}

static void finish_request_with_resource(WebKitURISchemeRequest* request,
                                         PapyrusLinuxInlineResource* resource) {
  gsize length = 0;
  const guint8* data = static_cast<const guint8*>(
      g_bytes_get_data(resource->bytes, &length));
  gpointer copy = length == 0 ? nullptr : g_memdup2(data, length);
  g_autoptr(GInputStream) stream =
      g_memory_input_stream_new_from_data(copy, length, g_free);

#if WEBKIT_CHECK_VERSION(2, 36, 0)
  g_autoptr(WebKitURISchemeResponse) response =
      webkit_uri_scheme_response_new(stream, static_cast<gint64>(length));
  webkit_uri_scheme_response_set_content_type(response, resource->mime_type);
  webkit_uri_scheme_response_set_status(response, resource->status_code,
                                        reason_phrase_for_status(
                                            resource->status_code));
  if (resource->headers != nullptr && g_hash_table_size(resource->headers) > 0) {
    SoupMessageHeaders* headers =
        soup_message_headers_new(SOUP_MESSAGE_HEADERS_RESPONSE);
    GHashTableIter iter;
    gpointer key = nullptr;
    gpointer value = nullptr;
    g_hash_table_iter_init(&iter, resource->headers);
    while (g_hash_table_iter_next(&iter, &key, &value)) {
      soup_message_headers_append(headers, static_cast<const char*>(key),
                                  static_cast<const char*>(value));
    }
    webkit_uri_scheme_response_set_http_headers(response, headers);
    soup_message_headers_unref(headers);
  }
  webkit_uri_scheme_request_finish_with_response(request, response);
#else
  if (resource->status_code == 200) {
    webkit_uri_scheme_request_finish(request, stream, static_cast<gint64>(length),
                                     resource->mime_type);
  } else {
    finish_request_with_status(request, resource->status_code,
                               reason_phrase_for_status(resource->status_code));
  }
#endif
}

static const gchar* header_lookup(GHashTable* headers, const gchar* key) {
  return headers == nullptr ? nullptr
                            : static_cast<const gchar*>(
                                  g_hash_table_lookup(headers, key));
}

static const gchar* resource_type_for_request(const gchar* uri,
                                              GHashTable* headers,
                                              gboolean is_main_frame) {
  if (is_main_frame) {
    return "document";
  }

  g_autofree gchar* uri_lower = g_ascii_strdown(uri == nullptr ? "" : uri, -1);
  g_autofree gchar* accept_lower =
      g_ascii_strdown(header_lookup(headers, "Accept") != nullptr
                          ? header_lookup(headers, "Accept")
                          : "",
                      -1);

  if (strstr(accept_lower, "text/css") != nullptr ||
      g_str_has_suffix(uri_lower, ".css")) {
    return "stylesheet";
  }
  if (strstr(accept_lower, "image/") != nullptr ||
      g_str_has_suffix(uri_lower, ".png") || g_str_has_suffix(uri_lower, ".jpg") ||
      g_str_has_suffix(uri_lower, ".jpeg") || g_str_has_suffix(uri_lower, ".gif") ||
      g_str_has_suffix(uri_lower, ".svg") || g_str_has_suffix(uri_lower, ".webp")) {
    return "image";
  }
  if (strstr(accept_lower, "font/") != nullptr ||
      g_str_has_suffix(uri_lower, ".woff") || g_str_has_suffix(uri_lower, ".woff2") ||
      g_str_has_suffix(uri_lower, ".ttf")) {
    return "font";
  }
  if (strstr(accept_lower, "javascript") != nullptr ||
      g_str_has_suffix(uri_lower, ".js")) {
    return "script";
  }
  if (strstr(accept_lower, "video/") != nullptr ||
      strstr(accept_lower, "audio/") != nullptr) {
    return "media";
  }
  return "other";
}

static void papyrus_linux_resource_method_response_cb(GObject* object,
                                                      GAsyncResult* result,
                                                      gpointer user_data);
static void papyrus_linux_uri_scheme_request_cb(
    WebKitURISchemeRequest* request,
    gpointer user_data);

}  // namespace

struct _PapyrusLinuxPlugin {
  GObject parent_instance;
  FlView* flutter_view;
  FlMethodChannel* channel;
  GtkWidget* overlay;
  GtkWidget* fixed;
  WebKitWebView* web_view;
  gboolean resource_resolver_enabled;
  gboolean visible;
  gchar* virtual_resource_scheme;
  GHashTable* virtual_resources;
  GHashTable* registered_schemes;
  double last_x;
  double last_y;
  double last_width;
  double last_height;
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

static gboolean fl_value_lookup_string_equals(FlValue* map,
                                              const gchar* key,
                                              const gchar* expected) {
  const gchar* value = fl_value_lookup_string_or_null(map, key);
  return value != nullptr && strcmp(value, expected) == 0;
}

static double fl_value_lookup_double(FlValue* map, const gchar* key,
                                     double fallback) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(value));
  }
  return fallback;
}

static void ensure_virtual_scheme_registered(PapyrusLinuxPlugin* self,
                                             WebKitWebContext* context,
                                             const gchar* scheme) {
  if (scheme == nullptr || is_builtin_scheme(scheme) ||
      g_hash_table_contains(self->registered_schemes, scheme)) {
    return;
  }

  g_hash_table_insert(self->registered_schemes, g_strdup(scheme),
                      GINT_TO_POINTER(TRUE));
  webkit_web_context_register_uri_scheme(
      context, scheme, papyrus_linux_uri_scheme_request_cb, g_object_ref(self),
      g_object_unref);
}

static void update_virtual_resource_scheme(PapyrusLinuxPlugin* self,
                                           FlValue* config) {
  g_autofree gchar* scheme = sanitize_custom_scheme(
      fl_value_lookup_string_or_null(config, "virtualResourceScheme"));
  if (g_strcmp0(self->virtual_resource_scheme, scheme) == 0) {
    return;
  }
  g_free(self->virtual_resource_scheme);
  self->virtual_resource_scheme = g_strdup(scheme);
}

static void update_virtual_resources(PapyrusLinuxPlugin* self, FlValue* request) {
  g_hash_table_remove_all(self->virtual_resources);
  if (request == nullptr || fl_value_get_type(request) != FL_VALUE_TYPE_MAP) {
    return;
  }

  FlValue* resources = fl_value_lookup_string(request, "virtualResources");
  if (resources == nullptr || fl_value_get_type(resources) != FL_VALUE_TYPE_LIST) {
    return;
  }

  const size_t length = fl_value_get_length(resources);
  for (size_t index = 0; index < length; ++index) {
    FlValue* entry = fl_value_get_list_value(resources, index);
    if (entry == nullptr || fl_value_get_type(entry) != FL_VALUE_TYPE_MAP) {
      continue;
    }
    const gchar* uri = fl_value_lookup_string_or_null(entry, "uri");
    PapyrusLinuxInlineResource* resource = inline_resource_from_value(entry);
    if (uri == nullptr || resource == nullptr) {
      papyrus_linux_inline_resource_free(resource);
      continue;
    }
    g_hash_table_insert(self->virtual_resources, g_strdup(uri), resource);
  }
}

static void ensure_overlay_container(PapyrusLinuxPlugin* self) {
  if (self->overlay != nullptr || self->flutter_view == nullptr) {
    return;
  }

  GtkWidget* flutter_widget = GTK_WIDGET(self->flutter_view);
  GtkWidget* parent = gtk_widget_get_parent(flutter_widget);
  if (parent == nullptr || !GTK_IS_CONTAINER(parent)) {
    return;
  }

  self->overlay = gtk_overlay_new();
  gtk_widget_show(self->overlay);

  g_object_ref(flutter_widget);
  gtk_container_remove(GTK_CONTAINER(parent), flutter_widget);
  gtk_container_add(GTK_CONTAINER(parent), self->overlay);
  gtk_container_add(GTK_CONTAINER(self->overlay), flutter_widget);
  g_object_unref(flutter_widget);

  self->fixed = gtk_fixed_new();
  gtk_widget_set_halign(self->fixed, GTK_ALIGN_START);
  gtk_widget_set_valign(self->fixed, GTK_ALIGN_START);
  gtk_widget_show(self->fixed);
  gtk_overlay_add_overlay(GTK_OVERLAY(self->overlay), self->fixed);
}

static void ensure_web_view(PapyrusLinuxPlugin* self, FlValue* config) {
  update_virtual_resource_scheme(self, config);
  self->resource_resolver_enabled =
      fl_value_lookup_bool(config, "resourceResolverEnabled",
                           self->resource_resolver_enabled);
  if (self->web_view != nullptr) {
    return;
  }
  ensure_overlay_container(self);
  WebKitWebContext* context = webkit_web_context_get_default();
  ensure_virtual_scheme_registered(self, context, self->virtual_resource_scheme);
  WebKitSettings* settings = webkit_settings_new();
  webkit_settings_set_enable_javascript(
      settings, fl_value_lookup_bool(config, "allowJavaScript", FALSE));
  webkit_settings_set_javascript_can_open_windows_automatically(
      settings, FALSE);
  webkit_settings_set_enable_write_console_messages_to_stdout(settings, FALSE);
  webkit_settings_set_enable_developer_extras(
      settings, fl_value_lookup_bool(config, "debuggingEnabled", FALSE));
  if (fl_value_lookup_string_equals(config, "hardwareAcceleration",
                                    "software")) {
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
  } else if (fl_value_lookup_string_equals(config, "hardwareAcceleration",
                                           "hardware")) {
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS);
  }

  WebKitUserContentManager* content_manager = webkit_user_content_manager_new();
  self->web_view = WEBKIT_WEB_VIEW(g_object_new(
      WEBKIT_TYPE_WEB_VIEW, "settings", settings, "user-content-manager",
    content_manager, "web-context", context, nullptr));
  g_object_unref(settings);
  g_object_unref(content_manager);

  if (self->fixed != nullptr) {
    gtk_container_add(GTK_CONTAINER(self->fixed), GTK_WIDGET(self->web_view));
    gtk_widget_hide(GTK_WIDGET(self->web_view));
  }
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

static void set_viewport(PapyrusLinuxPlugin* self, FlValue* args) {
  ensure_web_view(self, nullptr);
  if (self->web_view == nullptr || self->fixed == nullptr) {
    return;
  }

  const gboolean visible = fl_value_lookup_bool(args, "visible", FALSE);
  const double x = fl_value_lookup_double(args, "x", 0);
  const double y = fl_value_lookup_double(args, "y", 0);
  const double width = fl_value_lookup_double(args, "width", 0);
  const double height = fl_value_lookup_double(args, "height", 0);
  self->visible = visible && width > 0 && height > 0;
  self->last_x = x;
  self->last_y = y;
  self->last_width = width;
  self->last_height = height;

  GtkWidget* widget = GTK_WIDGET(self->web_view);
  gtk_fixed_move(GTK_FIXED(self->fixed), widget, static_cast<gint>(x),
                 static_cast<gint>(y));
  gtk_widget_set_size_request(widget, static_cast<gint>(width),
                              static_cast<gint>(height));

  if (self->visible) {
    gtk_widget_show(widget);
  } else {
    gtk_widget_hide(widget);
  }
}

static FlMethodResponse* debug_overlay_state_response(
    PapyrusLinuxPlugin* self) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "overlayAttached",
                           fl_value_new_bool(self->overlay != nullptr));
  fl_value_set_string_take(result, "webViewAttached",
                           fl_value_new_bool(self->web_view != nullptr));
  fl_value_set_string_take(result, "visible",
                           fl_value_new_bool(self->visible));
  fl_value_set_string_take(result, "x", fl_value_new_float(self->last_x));
  fl_value_set_string_take(result, "y", fl_value_new_float(self->last_y));
  fl_value_set_string_take(result, "width",
                           fl_value_new_float(self->last_width));
  fl_value_set_string_take(result, "height",
                           fl_value_new_float(self->last_height));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void load_request(PapyrusLinuxPlugin* self, FlValue* request) {
  ensure_web_view(self, nullptr);
  update_virtual_resources(self, request);
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

static FlValue* request_headers_value(WebKitURISchemeRequest* request,
                                      GHashTable** headers_out) {
  g_autoptr(FlValue) result = fl_value_new_map();
  GHashTable* headers =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);

#if WEBKIT_CHECK_VERSION(2, 34, 0)
  SoupMessageHeaders* request_headers =
      webkit_uri_scheme_request_get_http_headers(request);
  if (request_headers != nullptr) {
    SoupMessageHeadersIter iter;
    const char* name = nullptr;
    const char* value = nullptr;
    soup_message_headers_iter_init(&iter, request_headers);
    while (soup_message_headers_iter_next(&iter, &name, &value)) {
      if (name == nullptr || value == nullptr) {
        continue;
      }
      g_hash_table_insert(headers, g_strdup(name), g_strdup(value));
      fl_value_set_string_take(result, name, fl_value_new_string(value));
    }
  }
#endif

  if (headers_out != nullptr) {
    *headers_out = headers;
  } else {
    g_hash_table_unref(headers);
  }
  return fl_value_ref(result);
}

static FlValue* resource_request_arguments(PapyrusLinuxPlugin* self,
                                           WebKitURISchemeRequest* request,
                                           GHashTable** headers_out) {
  const gchar* uri = webkit_uri_scheme_request_get_uri(request);
  g_autoptr(FlValue) arguments = fl_value_new_map();
  g_autoptr(FlValue) headers = request_headers_value(request, headers_out);
  WebKitWebView* web_view = webkit_uri_scheme_request_get_web_view(request);
  const gchar* current_uri =
      web_view == nullptr ? nullptr : webkit_web_view_get_uri(web_view);
  const gboolean is_main_frame = g_strcmp0(uri, current_uri) == 0;

  fl_value_set_string_take(arguments, "uri",
                           fl_value_new_string(uri == nullptr ? "" : uri));
#if WEBKIT_CHECK_VERSION(2, 34, 0)
  const gchar* method = webkit_uri_scheme_request_get_http_method(request);
#else
  const gchar* method = nullptr;
#endif
  fl_value_set_string_take(arguments, "method",
                           fl_value_new_string(method == nullptr ? "GET" : method));
  fl_value_set_string(arguments, "headers", headers);
  fl_value_set_string_take(
      arguments, "resourceType",
      fl_value_new_string(resource_type_for_request(uri, *headers_out, is_main_frame)));
  fl_value_set_string_take(arguments, "isMainFrame",
                           fl_value_new_bool(is_main_frame));
  return fl_value_ref(arguments);
}

static void papyrus_linux_resource_method_response_cb(GObject* object,
                                                      GAsyncResult* result,
                                                      gpointer user_data) {
  auto* invocation = static_cast<PapyrusLinuxSchemeInvocation*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, &error);

  if (error != nullptr || response == nullptr ||
      !FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    finish_request_with_status(invocation->request, 403,
                               "Papyrus resource blocked.");
    papyrus_linux_scheme_invocation_free(invocation);
    return;
  }

  FlValue* value = fl_method_success_response_get_result(
      FL_METHOD_SUCCESS_RESPONSE(response));
  const gchar* decision = fl_value_lookup_string_or_null(value, "decision");
  if (g_strcmp0(decision, "respond") == 0) {
    PapyrusLinuxInlineResource* resource = inline_resource_from_value(
        fl_value_lookup_string(value, "response"));
    if (resource != nullptr) {
      finish_request_with_resource(invocation->request, resource);
      papyrus_linux_inline_resource_free(resource);
    } else {
      finish_request_with_status(invocation->request, 403,
                                 "Papyrus resource blocked.");
    }
  } else if (g_strcmp0(decision, "allow") == 0) {
    finish_request_with_status(invocation->request, 404,
                               "Papyrus resource not found.");
  } else {
    finish_request_with_status(invocation->request, 403,
                               "Papyrus resource blocked.");
  }

  papyrus_linux_scheme_invocation_free(invocation);
}

static void papyrus_linux_uri_scheme_request_cb(
    WebKitURISchemeRequest* request,
    gpointer user_data) {
  PapyrusLinuxPlugin* self = PAPYRUS_LINUX_PLUGIN(user_data);
  const gchar* uri = webkit_uri_scheme_request_get_uri(request);
  auto* inline_resource = static_cast<PapyrusLinuxInlineResource*>(
      g_hash_table_lookup(self->virtual_resources, uri));
  if (inline_resource != nullptr) {
    finish_request_with_resource(request, inline_resource);
    return;
  }

  if (!self->resource_resolver_enabled || self->channel == nullptr) {
    finish_request_with_status(request, 404, "Papyrus resource not found.");
    return;
  }

  auto* invocation = g_new0(PapyrusLinuxSchemeInvocation, 1);
  invocation->plugin = PAPYRUS_LINUX_PLUGIN(g_object_ref(self));
  invocation->request = WEBKIT_URI_SCHEME_REQUEST(g_object_ref(request));

  GHashTable* header_lookup_table = nullptr;
  g_autoptr(FlValue) arguments =
      resource_request_arguments(self, request, &header_lookup_table);
  if (header_lookup_table != nullptr) {
    g_hash_table_unref(header_lookup_table);
  }

  fl_method_channel_invoke_method(self->channel, "resourceRequest", arguments,
                                  nullptr,
                                  papyrus_linux_resource_method_response_cb,
                                  invocation);
}

static void papyrus_linux_plugin_handle_method_call(
    PapyrusLinuxPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "create") == 0) {
    ensure_web_view(self, args);
    response = success_null();
  } else if (strcmp(method, "setViewport") == 0) {
    set_viewport(self, args);
    response = success_null();
  } else if (strcmp(method, "debugOverlayState") == 0) {
    response = debug_overlay_state_response(self);
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
      gtk_widget_destroy(GTK_WIDGET(self->web_view));
      self->web_view = nullptr;
      self->visible = FALSE;
      self->last_width = 0;
      self->last_height = 0;
      g_hash_table_remove_all(self->virtual_resources);
      self->resource_resolver_enabled = FALSE;
    }
    response = success_null();
  } else if (strcmp(method, "setResourceResolverEnabled") == 0) {
    self->resource_resolver_enabled =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(args);
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
    gtk_widget_destroy(GTK_WIDGET(self->web_view));
    self->web_view = nullptr;
    self->visible = FALSE;
  }
  if (self->channel != nullptr) {
    g_object_unref(self->channel);
    self->channel = nullptr;
  }
  if (self->flutter_view != nullptr) {
    g_object_unref(self->flutter_view);
    self->flutter_view = nullptr;
  }
  if (self->virtual_resources != nullptr) {
    g_hash_table_unref(self->virtual_resources);
    self->virtual_resources = nullptr;
  }
  if (self->registered_schemes != nullptr) {
    g_hash_table_unref(self->registered_schemes);
    self->registered_schemes = nullptr;
  }
  g_clear_pointer(&self->virtual_resource_scheme, g_free);
  G_OBJECT_CLASS(papyrus_linux_plugin_parent_class)->dispose(object);
}

static void papyrus_linux_plugin_class_init(PapyrusLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = papyrus_linux_plugin_dispose;
}

static void papyrus_linux_plugin_init(PapyrusLinuxPlugin* self) {
  self->flutter_view = nullptr;
  self->channel = nullptr;
  self->overlay = nullptr;
  self->fixed = nullptr;
  self->web_view = nullptr;
  self->resource_resolver_enabled = FALSE;
  self->visible = FALSE;
  self->virtual_resource_scheme = g_strdup(kDefaultVirtualResourceScheme);
  self->virtual_resources = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free,
      reinterpret_cast<GDestroyNotify>(papyrus_linux_inline_resource_free));
  self->registered_schemes =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  self->last_x = 0;
  self->last_y = 0;
  self->last_width = 0;
  self->last_height = 0;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  PapyrusLinuxPlugin* plugin = PAPYRUS_LINUX_PLUGIN(user_data);
  papyrus_linux_plugin_handle_method_call(plugin, method_call);
}

void papyrus_linux_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PapyrusLinuxPlugin* plugin = PAPYRUS_LINUX_PLUGIN(
      g_object_new(papyrus_linux_plugin_get_type(), nullptr));
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    plugin->flutter_view = FL_VIEW(g_object_ref(view));
  }

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.papyrus.papyrus_linux", FL_METHOD_CODEC(codec));
  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
