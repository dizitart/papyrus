#include "include/papyrus_linux/papyrus_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <libsoup/soup.h>
#include <sys/utsname.h>
#include <webkit2/webkit2.h>

#include <algorithm>
#include <cstring>

#include "papyrus_linux_plugin_private.h"

static const gchar* fl_value_lookup_string_or_null(FlValue* map,
                                                   const gchar* key);

#define PAPYRUS_LINUX_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), papyrus_linux_plugin_get_type(), \
                              PapyrusLinuxPlugin))

namespace {

constexpr char kDefaultVirtualResourceScheme[] = "papyrus-resource";
constexpr char kOverlayFixedDataKey[] = "papyrus-overlay-fixed";
constexpr char kPrewrapInProgressDataKey[] = "papyrus-prewrap-in-progress";
constexpr char kPrewrapDeferredHandlerDataKey[] =
  "papyrus-prewrap-deferred-handler";

gulong g_papyrus_linux_container_add_hook_id = 0;

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

typedef struct {
  FlMethodCall* method_call;
} PapyrusLinuxMethodInvocation;

typedef struct {
  WebKitPolicyDecision* decision;
  gchar* uri;
  gchar* fallback_decision;
} PapyrusLinuxNavigationInvocation;

static const gchar* const kDefaultNavigationAllowedSchemes[] = {
    "https", nullptr};
static const gchar* const kDefaultNavigationExternalSchemes[] = {
    "http", "https", "mailto", "tel", nullptr};
static const gchar* const kDefaultNavigationBlockedSchemes[] = {
    "javascript", "data", "file", nullptr};

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

static void papyrus_linux_method_invocation_free(
    PapyrusLinuxMethodInvocation* invocation) {
  if (invocation == nullptr) {
    return;
  }
  if (invocation->method_call != nullptr) {
    g_object_unref(invocation->method_call);
  }
  g_free(invocation);
}

static void papyrus_linux_navigation_invocation_free(
    PapyrusLinuxNavigationInvocation* invocation) {
  if (invocation == nullptr) {
    return;
  }
  if (invocation->decision != nullptr) {
    g_object_unref(invocation->decision);
  }
  g_clear_pointer(&invocation->uri, g_free);
  g_clear_pointer(&invocation->fallback_decision, g_free);
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
  const gchar* mime_type = fl_value_lookup_string_or_null(value, "mimeType");
  resource->mime_type =
      g_strdup(mime_type != nullptr ? mime_type : "application/octet-stream");
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

}  // namespace

static void papyrus_linux_resource_method_response_cb(GObject* object,
                                                      GAsyncResult* result,
                                                      gpointer user_data);
static void papyrus_linux_uri_scheme_request_cb(
    WebKitURISchemeRequest* request,
    gpointer user_data);
static gboolean papyrus_linux_decide_policy_cb(
    WebKitWebView* web_view,
    WebKitPolicyDecision* decision,
    WebKitPolicyDecisionType decision_type,
    gpointer user_data);
static void papyrus_linux_navigation_method_response_cb(GObject* object,
                                                        GAsyncResult* result,
                                                        gpointer user_data);
static void papyrus_linux_selected_text_cb(GObject* object,
                                           GAsyncResult* result,
                                           gpointer user_data);
static void papyrus_linux_snapshot_cb(GObject* object,
                                      GAsyncResult* result,
                                      gpointer user_data);
static void papyrus_linux_uri_changed_cb(WebKitWebView* web_view,
                                         GParamSpec* pspec,
                                         gpointer user_data);

struct _PapyrusLinuxPlugin {
  GObject parent_instance;
  FlView* flutter_view;
  FlMethodChannel* channel;
  FlValue* configuration;
  FlValue* pending_load;
  GtkWidget* overlay;
  GtkWidget* fixed;
  WebKitWebView* web_view;
  WebKitWebContext* web_context;
  gchar* current_uri;
  gboolean allow_file_access;
  gboolean navigation_resolver_enabled;
  gboolean resource_resolver_enabled;
  gboolean require_user_gesture_for_external_open;
  gboolean allow_main_frame_navigation;
  gboolean allow_sub_frame_navigation;
  gboolean visible;
  gchar* navigation_default_decision;
  gchar* virtual_resource_scheme;
  GHashTable* app_initiated_navigations;
  GHashTable* navigation_allowed_schemes;
  GHashTable* navigation_external_schemes;
  GHashTable* navigation_blocked_schemes;
  GHashTable* virtual_resources;
  GHashTable* registered_schemes;
  guint64 inline_document_counter;
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

static void replace_fl_value(FlValue** slot, FlValue* value) {
  if (*slot != nullptr) {
    fl_value_unref(*slot);
  }
  *slot = value == nullptr ? nullptr : fl_value_ref(value);
}

static void replace_string(gchar** slot, const gchar* value) {
  g_free(*slot);
  *slot = value == nullptr ? nullptr : g_strdup(value);
}

static const gchar* effective_current_uri(PapyrusLinuxPlugin* self) {
  if (self->web_view != nullptr) {
    WebKitBackForwardList* history =
        webkit_web_view_get_back_forward_list(self->web_view);
    if (history != nullptr) {
      WebKitBackForwardListItem* item =
          webkit_back_forward_list_get_current_item(history);
      if (item != nullptr) {
        const gchar* history_uri = webkit_back_forward_list_item_get_uri(item);
        if (history_uri != nullptr && history_uri[0] != '\0') {
          return history_uri;
        }
      }
    }
  }

  const gchar* current_uri =
      self->web_view == nullptr ? nullptr : webkit_web_view_get_uri(self->web_view);
  if (current_uri == nullptr || current_uri[0] == '\0' ||
      g_strcmp0(current_uri, "about:blank") == 0) {
    return self->current_uri;
  }
  return current_uri;
}

static void maybe_focus_web_view(PapyrusLinuxPlugin* self) {
  if (self->web_view == nullptr || !self->visible) {
    return;
  }

  GtkWidget* widget = GTK_WIDGET(self->web_view);
  GtkWidget* top_level = gtk_widget_get_toplevel(widget);
  if (GTK_IS_WINDOW(top_level) &&
      gtk_window_get_focus(GTK_WINDOW(top_level)) != nullptr) {
    return;
  }

  gtk_widget_grab_focus(widget);
}

static void string_set_assign_defaults(GHashTable* set,
                                       const gchar* const* defaults) {
  g_hash_table_remove_all(set);
  for (const gchar* const* value = defaults;
       value != nullptr && *value != nullptr; ++value) {
    g_hash_table_insert(set, g_ascii_strdown(*value, -1),
                        GINT_TO_POINTER(TRUE));
  }
}

static void string_set_assign(GHashTable* set,
                              FlValue* value,
                              const gchar* const* defaults) {
  g_hash_table_remove_all(set);
  gboolean has_values = FALSE;
  if (value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_LIST) {
    const size_t length = fl_value_get_length(value);
    for (size_t index = 0; index < length; ++index) {
      FlValue* entry = fl_value_get_list_value(value, index);
      if (entry == nullptr || fl_value_get_type(entry) != FL_VALUE_TYPE_STRING) {
        continue;
      }
      has_values = TRUE;
      g_hash_table_insert(set, g_ascii_strdown(fl_value_get_string(entry), -1),
                          GINT_TO_POINTER(TRUE));
    }
  }
  if (!has_values) {
    string_set_assign_defaults(set, defaults);
  }
}

static gboolean string_set_contains(GHashTable* set, const gchar* value) {
  if (set == nullptr || value == nullptr) {
    return FALSE;
  }
  g_autofree gchar* lowered = g_ascii_strdown(value, -1);
  return g_hash_table_contains(set, lowered);
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

static void update_navigation_policy(PapyrusLinuxPlugin* self, FlValue* config) {
  if (config == nullptr || fl_value_get_type(config) != FL_VALUE_TYPE_MAP) {
    return;
  }
  g_free(self->navigation_default_decision);
  self->navigation_default_decision = g_strdup(
      fl_value_lookup_string_or_null(config, "navigationDefaultDecision") != nullptr
          ? fl_value_lookup_string_or_null(config, "navigationDefaultDecision")
          : "block");
  string_set_assign(self->navigation_allowed_schemes,
                    fl_value_lookup_string(config, "navigationAllowedSchemes"),
                    kDefaultNavigationAllowedSchemes);
  string_set_assign(self->navigation_external_schemes,
                    fl_value_lookup_string(config, "navigationExternalSchemes"),
                    kDefaultNavigationExternalSchemes);
  string_set_assign(self->navigation_blocked_schemes,
                    fl_value_lookup_string(config, "navigationBlockedSchemes"),
                    kDefaultNavigationBlockedSchemes);
  self->require_user_gesture_for_external_open = fl_value_lookup_bool(
      config, "requireUserGestureForExternalOpen",
      self->require_user_gesture_for_external_open);
  self->allow_main_frame_navigation =
      fl_value_lookup_bool(config, "allowMainFrameNavigation",
                           self->allow_main_frame_navigation);
  self->allow_sub_frame_navigation =
      fl_value_lookup_bool(config, "allowSubFrameNavigation",
                           self->allow_sub_frame_navigation);
}

static void mark_app_initiated_navigation(PapyrusLinuxPlugin* self,
                                          const gchar* uri) {
  if (uri == nullptr || uri[0] == '\0') {
    return;
  }
  g_hash_table_insert(self->app_initiated_navigations, g_strdup(uri),
                      GINT_TO_POINTER(TRUE));
}

static gboolean consume_app_initiated_navigation(PapyrusLinuxPlugin* self,
                                                 const gchar* uri) {
  return uri != nullptr &&
         g_hash_table_remove(self->app_initiated_navigations, uri);
}

static const gchar* navigation_type_name(WebKitNavigationAction* action) {
  if (action == nullptr) {
    return "other";
  }
  switch (webkit_navigation_action_get_navigation_type(action)) {
    case WEBKIT_NAVIGATION_TYPE_LINK_CLICKED:
      return "linkClicked";
    case WEBKIT_NAVIGATION_TYPE_FORM_SUBMITTED:
    case WEBKIT_NAVIGATION_TYPE_FORM_RESUBMITTED:
      return "formSubmitted";
    case WEBKIT_NAVIGATION_TYPE_BACK_FORWARD:
      return "backForward";
    case WEBKIT_NAVIGATION_TYPE_RELOAD:
      return "reload";
    default:
      return webkit_navigation_action_is_user_gesture(action) ? "other"
                                                              : "programmatic";
  }
}

static gboolean navigation_is_main_frame(
    WebKitNavigationAction* action,
    WebKitPolicyDecisionType decision_type) {
  if (decision_type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return TRUE;
  }
  const gchar* frame_name =
      action == nullptr ? nullptr : webkit_navigation_action_get_frame_name(action);
  return frame_name == nullptr || frame_name[0] == '\0';
}

static const gchar* navigation_decision_for(PapyrusLinuxPlugin* self,
                                            const gchar* uri,
                                            gboolean is_main_frame,
                                            gboolean has_user_gesture) {
  g_autoptr(GUri) parsed_uri = g_uri_parse(uri, G_URI_FLAGS_NONE, nullptr);
  const gchar* scheme =
      parsed_uri == nullptr ? nullptr : g_uri_get_scheme(parsed_uri);
  if (string_set_contains(self->navigation_blocked_schemes, scheme)) {
    return "block";
  }
  if (is_main_frame && !self->allow_main_frame_navigation) {
    return self->navigation_default_decision;
  }
  if (!is_main_frame && !self->allow_sub_frame_navigation) {
    return "block";
  }
  if (string_set_contains(self->navigation_allowed_schemes, scheme)) {
    return "allow";
  }
  if (string_set_contains(self->navigation_external_schemes, scheme)) {
    if (self->require_user_gesture_for_external_open && !has_user_gesture) {
      return "block";
    }
    return "openExternally";
  }
  return self->navigation_default_decision;
}

static void open_externally(const gchar* uri) {
  if (uri == nullptr || uri[0] == '\0') {
    return;
  }
  g_app_info_launch_default_for_uri(uri, nullptr, nullptr);
}

static void apply_navigation_decision(WebKitPolicyDecision* decision,
                                      const gchar* uri,
                                      const gchar* action) {
  if (g_strcmp0(action, "allow") == 0) {
    webkit_policy_decision_use(decision);
    return;
  }
  if (g_strcmp0(action, "download") == 0) {
    webkit_policy_decision_download(decision);
    return;
  }
  if (g_strcmp0(action, "openExternally") == 0) {
    open_externally(uri);
  }
  webkit_policy_decision_ignore(decision);
}

static FlValue* navigation_arguments(const gchar* uri,
                                     gboolean is_main_frame,
                                     WebKitNavigationAction* action) {
  g_autoptr(FlValue) arguments = fl_value_new_map();
  fl_value_set_string_take(arguments, "uri",
                           fl_value_new_string(uri == nullptr ? "" : uri));
  fl_value_set_string_take(arguments, "isMainFrame",
                           fl_value_new_bool(is_main_frame));
  fl_value_set_string_take(arguments, "navigationType",
                           fl_value_new_string(navigation_type_name(action)));
  fl_value_set_string_take(arguments, "hasUserGesture",
                           fl_value_new_bool(action != nullptr &&
                                             webkit_navigation_action_is_user_gesture(
                                                 action)));
  return fl_value_ref(arguments);
}

static WebKitCookieAcceptPolicy cookie_accept_policy_for_config(FlValue* config) {
  const gchar* cookie_policy =
      fl_value_lookup_string_or_null(config, "cookiePolicy");
  if (g_strcmp0(cookie_policy, "allow") == 0) {
    return WEBKIT_COOKIE_POLICY_ACCEPT_ALWAYS;
  }
  if (g_strcmp0(cookie_policy, "allowByHost") == 0) {
    return WEBKIT_COOKIE_POLICY_ACCEPT_NO_THIRD_PARTY;
  }
  return WEBKIT_COOKIE_POLICY_ACCEPT_NEVER;
}

static WebKitCacheModel cache_model_for_config(FlValue* config) {
  const gchar* cache_mode = fl_value_lookup_string_or_null(config, "cacheMode");
  if (g_strcmp0(cache_mode, "noCache") == 0) {
    return WEBKIT_CACHE_MODEL_DOCUMENT_VIEWER;
  }
  if (g_strcmp0(cache_mode, "cacheOnly") == 0) {
    return WEBKIT_CACHE_MODEL_DOCUMENT_BROWSER;
  }
  return WEBKIT_CACHE_MODEL_WEB_BROWSER;
}

static void apply_storage_policy(PapyrusLinuxPlugin* self,
                                 FlValue* config,
                                 WebKitSettings* settings) {
  const gboolean local_storage_enabled =
      g_strcmp0(fl_value_lookup_string_or_null(config, "localStorage"),
                "enabled") == 0;
  webkit_settings_set_enable_html5_local_storage(settings,
                                                 local_storage_enabled);
  if (self->web_context == nullptr) {
    return;
  }
  webkit_web_context_set_cache_model(self->web_context,
                                     cache_model_for_config(config));
  WebKitCookieManager* cookie_manager =
      webkit_web_context_get_cookie_manager(self->web_context);
  if (cookie_manager != nullptr) {
    webkit_cookie_manager_set_accept_policy(
        cookie_manager, cookie_accept_policy_for_config(config));
  }
}

static void clear_website_data(PapyrusLinuxPlugin* self,
                               WebKitWebsiteDataTypes data_types) {
  if (self->web_context == nullptr) {
    return;
  }
  WebKitWebsiteDataManager* manager =
      webkit_web_context_get_website_data_manager(self->web_context);
  if (manager == nullptr) {
    return;
  }
  webkit_website_data_manager_clear(manager, data_types, 0, nullptr, nullptr,
                                    nullptr);
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

static PapyrusLinuxInlineResource* inline_html_resource(const gchar* html) {
  auto* resource = g_new0(PapyrusLinuxInlineResource, 1);
  resource->bytes =
      g_bytes_new(html == nullptr ? "" : html, strlen(html == nullptr ? "" : html));
  resource->mime_type = g_strdup("text/html");
  resource->status_code = 200;
  resource->headers =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_free);
  return resource;
}

static gchar* next_inline_document_uri(PapyrusLinuxPlugin* self) {
  self->inline_document_counter += 1;
  return g_strdup_printf("%s://papyrus.inline/%" G_GUINT64_FORMAT ".html",
                         self->virtual_resource_scheme,
                         self->inline_document_counter);
}

static GtkWidget* ensure_overlay_fixed_child(GtkWidget* overlay) {
  GtkWidget* fixed =
      GTK_WIDGET(g_object_get_data(G_OBJECT(overlay), kOverlayFixedDataKey));
  if (fixed != nullptr) {
    return fixed;
  }

  fixed = gtk_fixed_new();
  gtk_widget_set_halign(fixed, GTK_ALIGN_START);
  gtk_widget_set_valign(fixed, GTK_ALIGN_START);
  gtk_widget_set_hexpand(fixed, FALSE);
  gtk_widget_set_vexpand(fixed, FALSE);
  gtk_widget_show(fixed);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), fixed);
  g_object_set_data(G_OBJECT(overlay), kOverlayFixedDataKey, fixed);
  return fixed;
}

static void prewrap_flutter_view_if_needed(GtkWidget* flutter_widget) {
  if (flutter_widget == nullptr || !FL_IS_VIEW(flutter_widget) ||
      gtk_widget_get_mapped(flutter_widget) ||
      g_object_get_data(G_OBJECT(flutter_widget),
                        kPrewrapInProgressDataKey) != nullptr) {
    return;
  }

  GtkWidget* parent = gtk_widget_get_parent(flutter_widget);
  if (parent == nullptr || GTK_IS_OVERLAY(parent) || !GTK_IS_WINDOW(parent)) {
    return;
  }

  if (!GTK_IS_BIN(parent) ||
      gtk_bin_get_child(GTK_BIN(parent)) != flutter_widget) {
    return;
  }

  g_object_set_data(G_OBJECT(flutter_widget), kPrewrapInProgressDataKey,
                    GINT_TO_POINTER(TRUE));

  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  ensure_overlay_fixed_child(overlay);

  g_object_ref(flutter_widget);
  gtk_container_remove(GTK_CONTAINER(parent), flutter_widget);
  gtk_container_add(GTK_CONTAINER(parent), overlay);
  gtk_container_add(GTK_CONTAINER(overlay), flutter_widget);
  g_object_unref(flutter_widget);

  gtk_widget_show(flutter_widget);
  g_object_set_data(G_OBJECT(flutter_widget), kPrewrapInProgressDataKey,
                    nullptr);
}

static void papyrus_linux_after_view_parented(GtkWidget* widget,
                                              GtkWidget* previous_widget,
                                              gpointer user_data) {
  (void)previous_widget;
  (void)user_data;
  g_signal_handlers_disconnect_by_func(
      widget, reinterpret_cast<gpointer>(papyrus_linux_after_view_parented),
      nullptr);
  g_object_set_data(G_OBJECT(widget), kPrewrapDeferredHandlerDataKey,
                    nullptr);
  prewrap_flutter_view_if_needed(widget);
}

static gboolean papyrus_linux_container_add_emission_hook(
    GSignalInvocationHint* hint,
    guint n_param_values,
    const GValue* param_values,
    gpointer data) {
  (void)hint;
  (void)data;
  if (n_param_values < 2) {
    return TRUE;
  }

  GtkWidget* container = GTK_WIDGET(g_value_get_object(&param_values[0]));
  GtkWidget* child = GTK_WIDGET(g_value_get_object(&param_values[1]));
  if (container == nullptr || child == nullptr || !GTK_IS_WINDOW(container) ||
      !FL_IS_VIEW(child)) {
    return TRUE;
  }

  if (GTK_IS_BIN(container) && gtk_bin_get_child(GTK_BIN(container)) == child) {
    prewrap_flutter_view_if_needed(child);
    return TRUE;
  }

  if (g_object_get_data(G_OBJECT(child), kPrewrapDeferredHandlerDataKey) ==
      nullptr) {
    g_object_set_data(G_OBJECT(child), kPrewrapDeferredHandlerDataKey,
                      GINT_TO_POINTER(TRUE));
    g_signal_connect_after(child, "parent-set",
                           G_CALLBACK(papyrus_linux_after_view_parented),
                           nullptr);
    g_signal_connect_after(child, "hierarchy-changed",
                           G_CALLBACK(papyrus_linux_after_view_parented),
                           nullptr);
  }
  return TRUE;
}

__attribute__((constructor)) static void papyrus_linux_install_widget_hook() {
  if (g_papyrus_linux_container_add_hook_id != 0) {
    return;
  }

  g_type_class_ref(GTK_TYPE_CONTAINER);

  const guint add_signal_id = g_signal_lookup("add", GTK_TYPE_CONTAINER);
  if (add_signal_id != 0) {
    g_papyrus_linux_container_add_hook_id = g_signal_add_emission_hook(
        add_signal_id, 0, papyrus_linux_container_add_emission_hook, nullptr,
        nullptr);
  }
}

static void ensure_overlay_container(PapyrusLinuxPlugin* self) {
  if (self->overlay != nullptr || self->flutter_view == nullptr) {
    return;
  }

  GtkWidget* flutter_widget = GTK_WIDGET(self->flutter_view);
  GtkWidget* parent = gtk_widget_get_parent(flutter_widget);
  if (parent != nullptr && GTK_IS_OVERLAY(parent)) {
    self->overlay = parent;
    self->fixed = ensure_overlay_fixed_child(parent);
    return;
  }

  if (parent == nullptr || !GTK_IS_CONTAINER(parent)) {
    return;
  }

  if (gtk_widget_get_realized(flutter_widget)) {
    return;
  }

  self->overlay = gtk_overlay_new();
  gtk_widget_show(self->overlay);
  self->fixed = ensure_overlay_fixed_child(self->overlay);

  g_object_ref(flutter_widget);
  gtk_container_remove(GTK_CONTAINER(parent), flutter_widget);
  gtk_container_add(GTK_CONTAINER(parent), self->overlay);
  gtk_container_add(GTK_CONTAINER(self->overlay), flutter_widget);
  g_object_unref(flutter_widget);
}

static gboolean web_view_is_attached(PapyrusLinuxPlugin* self) {
  return self->web_view != nullptr && self->fixed != nullptr &&
         gtk_widget_get_parent(GTK_WIDGET(self->web_view)) == self->fixed;
}

static void attach_web_view_if_needed(PapyrusLinuxPlugin* self) {
  ensure_overlay_container(self);
  if (self->web_view == nullptr || self->fixed == nullptr ||
      web_view_is_attached(self)) {
    return;
  }

  GtkWidget* web_widget = GTK_WIDGET(self->web_view);
  GtkWidget* parent = gtk_widget_get_parent(web_widget);
  if (parent != nullptr) {
    if (!GTK_IS_CONTAINER(parent)) {
      return;
    }
    gtk_container_remove(GTK_CONTAINER(parent), web_widget);
  }

  gtk_container_add(GTK_CONTAINER(self->fixed), web_widget);
  if (self->visible) {
    gtk_widget_show(web_widget);
  } else {
    gtk_widget_hide(web_widget);
  }
}

static void ensure_web_view(PapyrusLinuxPlugin* self, FlValue* config) {
  if (config != nullptr && fl_value_get_type(config) == FL_VALUE_TYPE_MAP) {
    replace_fl_value(&self->configuration, config);
  }
  FlValue* effective_config = self->configuration;
  const gboolean has_viewport = self->last_width > 0 && self->last_height > 0;

  update_virtual_resource_scheme(self, effective_config);
  update_navigation_policy(self, effective_config);
  self->allow_file_access = fl_value_lookup_bool(effective_config,
                                                 "allowFileAccess",
                                                 self->allow_file_access);
  self->resource_resolver_enabled =
      fl_value_lookup_bool(effective_config, "resourceResolverEnabled",
                           self->resource_resolver_enabled);
  if (self->web_view == nullptr && self->flutter_view != nullptr &&
      !has_viewport) {
    return;
  }
  attach_web_view_if_needed(self);
  if (self->web_view != nullptr) {
    return;
  }
  ensure_overlay_container(self);
  if (self->flutter_view != nullptr && self->fixed == nullptr) {
    return;
  }
  self->web_context = webkit_web_context_get_default();
  ensure_virtual_scheme_registered(self, self->web_context,
                                   self->virtual_resource_scheme);
  WebKitSettings* settings = webkit_settings_new();
  webkit_settings_set_enable_javascript(
      settings,
      fl_value_lookup_bool(effective_config, "allowJavaScript", FALSE));
  webkit_settings_set_javascript_can_open_windows_automatically(
      settings, fl_value_lookup_bool(effective_config, "allowPopups", FALSE));
  webkit_settings_set_enable_write_console_messages_to_stdout(settings, FALSE);
  webkit_settings_set_enable_developer_extras(
      settings,
      fl_value_lookup_bool(effective_config, "debuggingEnabled", FALSE));
  apply_storage_policy(self, effective_config, settings);
  if (fl_value_lookup_string_equals(effective_config,
                                    "hardwareAcceleration",
                                    "hardware")) {
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_ALWAYS);
  } else {
    webkit_settings_set_hardware_acceleration_policy(
        settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
  }
  const gchar* user_agent =
      fl_value_lookup_string_or_null(effective_config, "userAgent");
  if (user_agent != nullptr && user_agent[0] != '\0') {
    webkit_settings_set_user_agent(settings, user_agent);
  }

  WebKitUserContentManager* content_manager = webkit_user_content_manager_new();
  self->web_view = WEBKIT_WEB_VIEW(g_object_new(
      WEBKIT_TYPE_WEB_VIEW, "settings", settings, "user-content-manager",
      content_manager, "web-context", self->web_context, nullptr));
  g_object_unref(settings);
  g_object_unref(content_manager);
  gtk_widget_set_can_focus(GTK_WIDGET(self->web_view), TRUE);

  g_signal_connect(self->web_view, "decide-policy",
                   G_CALLBACK(papyrus_linux_decide_policy_cb), self);
  g_signal_connect(self->web_view, "notify::uri",
                   G_CALLBACK(papyrus_linux_uri_changed_cb), self);

  attach_web_view_if_needed(self);
}

static void execute_load_request(PapyrusLinuxPlugin* self, FlValue* request) {
  update_virtual_resources(self, request);
  const gchar* type = fl_value_lookup_string_or_null(request, "type");
  if (type == nullptr) {
    return;
  }
  if (strcmp(type, "html") == 0) {
    const gchar* html = fl_value_lookup_string_or_null(request, "html");
    const gchar* base_uri = fl_value_lookup_string_or_null(request, "baseUri");
    maybe_focus_web_view(self);
    if (base_uri == nullptr) {
      g_autofree gchar* inline_uri = next_inline_document_uri(self);
      PapyrusLinuxInlineResource* resource = inline_html_resource(html);
      if (inline_uri != nullptr && resource != nullptr) {
        g_hash_table_insert(self->virtual_resources, g_strdup(inline_uri), resource);
        mark_app_initiated_navigation(self, inline_uri);
        replace_string(&self->current_uri, inline_uri);
        webkit_web_view_load_uri(self->web_view, inline_uri);
        return;
      }
      papyrus_linux_inline_resource_free(resource);
    }
    if (base_uri != nullptr) {
      mark_app_initiated_navigation(self, base_uri);
      replace_string(&self->current_uri, base_uri);
    }
    webkit_web_view_load_html(self->web_view, html == nullptr ? "" : html,
                              base_uri);
  } else if (strcmp(type, "uri") == 0) {
    const gchar* uri = fl_value_lookup_string_or_null(request, "uri");
    if (uri != nullptr) {
      maybe_focus_web_view(self);
      mark_app_initiated_navigation(self, uri);
      replace_string(&self->current_uri, uri);
      webkit_web_view_load_uri(self->web_view, uri);
    }
  } else if (strcmp(type, "file") == 0) {
    const gchar* path = fl_value_lookup_string_or_null(request, "absolutePath");
    if (path != nullptr) {
      g_autofree gchar* uri = g_filename_to_uri(path, nullptr, nullptr);
      if (uri != nullptr) {
        maybe_focus_web_view(self);
        mark_app_initiated_navigation(self, uri);
        replace_string(&self->current_uri, uri);
        webkit_web_view_load_uri(self->web_view, uri);
      }
    }
  }
}

static void run_pending_load_if_ready(PapyrusLinuxPlugin* self) {
  if (self->pending_load == nullptr || self->web_view == nullptr ||
      !web_view_is_attached(self)) {
    return;
  }

  g_autoptr(FlValue) pending_load = self->pending_load;
  self->pending_load = nullptr;
  execute_load_request(self, pending_load);
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

  ensure_web_view(self, nullptr);
  if (self->web_view == nullptr || self->fixed == nullptr) {
    return;
  }

  GtkWidget* widget = GTK_WIDGET(self->web_view);
  gtk_widget_set_margin_start(self->fixed, static_cast<gint>(x));
  gtk_widget_set_margin_top(self->fixed, static_cast<gint>(y));
  gtk_widget_set_size_request(self->fixed, static_cast<gint>(width),
                              static_cast<gint>(height));
  gtk_fixed_move(GTK_FIXED(self->fixed), widget, 0, 0);
  gtk_widget_set_size_request(widget, static_cast<gint>(width),
                              static_cast<gint>(height));

  if (self->visible) {
    gtk_widget_show(widget);
    maybe_focus_web_view(self);
  } else {
    gtk_widget_hide(widget);
  }

  run_pending_load_if_ready(self);
}

static FlMethodResponse* debug_overlay_state_response(
    PapyrusLinuxPlugin* self) {
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "overlayAttached",
                           fl_value_new_bool(self->overlay != nullptr));
  fl_value_set_string_take(result, "webViewAttached",
                           fl_value_new_bool(web_view_is_attached(self)));
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
  if (self->web_view == nullptr || !web_view_is_attached(self)) {
    replace_fl_value(&self->pending_load, request);
    return;
  }
  replace_fl_value(&self->pending_load, nullptr);
  execute_load_request(self, request);
}

static gboolean is_file_load_allowed(PapyrusLinuxPlugin* self, FlValue* request) {
  const gchar* type = fl_value_lookup_string_or_null(request, "type");
  if (type == nullptr) {
    return TRUE;
  }
  if (g_strcmp0(type, "file") == 0) {
    return self->allow_file_access;
  }
  if (g_strcmp0(type, "uri") != 0) {
    return TRUE;
  }
  const gchar* uri = fl_value_lookup_string_or_null(request, "uri");
  return uri == nullptr || !g_str_has_prefix(uri, "file://") ||
         self->allow_file_access;
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
  const gchar* current_uri = self->current_uri;
  if (current_uri == nullptr) {
    current_uri = web_view == nullptr ? nullptr : effective_current_uri(self);
  }
  if (current_uri == nullptr) {
    current_uri = self->current_uri;
  }
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

  fl_method_channel_invoke_method(
      self->channel, "resourceRequest", arguments, nullptr,
      papyrus_linux_resource_method_response_cb, invocation);
}

static void papyrus_linux_navigation_method_response_cb(GObject* object,
                                                        GAsyncResult* result,
                                                        gpointer user_data) {
  auto* invocation = static_cast<PapyrusLinuxNavigationInvocation*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = fl_method_channel_invoke_method_finish(
      FL_METHOD_CHANNEL(object), result, &error);

  const gchar* decision_name = invocation->fallback_decision;
  if (error == nullptr && response != nullptr &&
      FL_IS_METHOD_SUCCESS_RESPONSE(response)) {
    FlValue* value = fl_method_success_response_get_result(
        FL_METHOD_SUCCESS_RESPONSE(response));
    const gchar* candidate = fl_value_lookup_string_or_null(value, "decision");
    if (candidate != nullptr) {
      decision_name = candidate;
    }
  }

  apply_navigation_decision(invocation->decision, invocation->uri,
                            decision_name);
  papyrus_linux_navigation_invocation_free(invocation);
}

static gboolean papyrus_linux_decide_policy_cb(
    WebKitWebView* web_view,
    WebKitPolicyDecision* decision,
    WebKitPolicyDecisionType decision_type,
    gpointer user_data) {
  PapyrusLinuxPlugin* self = PAPYRUS_LINUX_PLUGIN(user_data);
  if (decision_type != WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      decision_type != WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    return FALSE;
  }

  auto* navigation_decision = WEBKIT_NAVIGATION_POLICY_DECISION(decision);
  WebKitNavigationAction* action =
      webkit_navigation_policy_decision_get_navigation_action(
          navigation_decision);
  WebKitURIRequest* request =
      action == nullptr ? nullptr : webkit_navigation_action_get_request(action);
  const gchar* uri =
      request == nullptr ? nullptr : webkit_uri_request_get_uri(request);
  if (uri == nullptr || uri[0] == '\0') {
    return FALSE;
  }

  const gboolean is_main_frame = navigation_is_main_frame(action, decision_type);
  const WebKitNavigationType navigation_type =
      action == nullptr ? WEBKIT_NAVIGATION_TYPE_OTHER
                        : webkit_navigation_action_get_navigation_type(action);
  if (is_main_frame && consume_app_initiated_navigation(self, uri)) {
    replace_string(&self->current_uri, uri);
    webkit_policy_decision_use(decision);
    return TRUE;
  }

  if (is_main_frame &&
      (navigation_type == WEBKIT_NAVIGATION_TYPE_BACK_FORWARD ||
       navigation_type == WEBKIT_NAVIGATION_TYPE_RELOAD)) {
    replace_string(&self->current_uri, uri);
    webkit_policy_decision_use(decision);
    return TRUE;
  }

  const gboolean has_user_gesture =
      action != nullptr && webkit_navigation_action_is_user_gesture(action);
  const gchar* fallback_decision =
      navigation_decision_for(self, uri, is_main_frame, has_user_gesture);
  if (!self->navigation_resolver_enabled || self->channel == nullptr) {
    apply_navigation_decision(decision, uri, fallback_decision);
    return TRUE;
  }

  auto* invocation = g_new0(PapyrusLinuxNavigationInvocation, 1);
  invocation->decision = WEBKIT_POLICY_DECISION(g_object_ref(decision));
  invocation->uri = g_strdup(uri);
  invocation->fallback_decision = g_strdup(fallback_decision);

  g_autoptr(FlValue) arguments = navigation_arguments(uri, is_main_frame, action);
  fl_method_channel_invoke_method(
      self->channel, "navigationRequest", arguments, nullptr,
      papyrus_linux_navigation_method_response_cb, invocation);
  return TRUE;
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
    if (!is_file_load_allowed(self, args)) {
      response = error_response(
          "navigationBlocked",
          "File loading is disabled by the current Papyrus security policy.");
    } else {
      load_request(self, args);
      response = success_null();
    }
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
    response = string_or_null_response(effective_current_uri(self));
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
  } else if (strcmp(method, "selectedText") == 0) {
    if (self->web_view == nullptr) {
      response = success_null();
    } else {
      gtk_widget_grab_focus(GTK_WIDGET(self->web_view));
      auto* invocation = g_new0(PapyrusLinuxMethodInvocation, 1);
      invocation->method_call = FL_METHOD_CALL(g_object_ref(method_call));
      webkit_web_view_evaluate_javascript(
          self->web_view,
          "(function(){var selection = window.getSelection ? window.getSelection() : (document.getSelection ? document.getSelection() : null); var text = selection && selection.toString ? selection.toString() : ''; if (!text && selection && selection.rangeCount > 0) { for (var i = 0; i < selection.rangeCount; i += 1) { var fragment = selection.getRangeAt(i).cloneContents(); text += fragment && fragment.textContent ? fragment.textContent : ''; } } if (!text) { var active = document.activeElement; if (active && typeof active.value === 'string') { var start = active.selectionStart; var end = active.selectionEnd; if (typeof start === 'number' && typeof end === 'number' && end > start) { text = active.value.substring(start, end); } } } return text ? encodeURIComponent(text) : null;})()",
          -1, nullptr, nullptr, nullptr, papyrus_linux_selected_text_cb,
          invocation);
      return;
    }
  } else if (strcmp(method, "getContentSize") == 0) {
    response = content_size_response(self);
  } else if (strcmp(method, "captureSnapshot") == 0) {
    if (self->web_view == nullptr) {
      response = error_response("webViewUnavailable",
                                "Snapshot capture requires an attached Linux WebKit view.");
    } else {
      auto* invocation = g_new0(PapyrusLinuxMethodInvocation, 1);
      invocation->method_call = FL_METHOD_CALL(g_object_ref(method_call));
      webkit_web_view_get_snapshot(
          self->web_view, WEBKIT_SNAPSHOT_REGION_VISIBLE,
          WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr, papyrus_linux_snapshot_cb,
          invocation);
      return;
    }
  } else if (strcmp(method, "printDocument") == 0) {
    response = error_response("unsupportedPlatformFeature",
                              "Printing is not consistently supported by "
                              "the Linux WebKitGTK backend.");
  } else if (strcmp(method, "clearCache") == 0) {
    clear_website_data(
        self, static_cast<WebKitWebsiteDataTypes>(
                  WEBKIT_WEBSITE_DATA_MEMORY_CACHE |
                  WEBKIT_WEBSITE_DATA_DISK_CACHE));
    response = success_null();
  } else if (strcmp(method, "clearStorage") == 0) {
    clear_website_data(self, WEBKIT_WEBSITE_DATA_ALL);
    response = success_null();
  } else if (strcmp(method, "dispose") == 0) {
    if (strcmp(method, "dispose") == 0 && self->web_view != nullptr) {
      gtk_widget_destroy(GTK_WIDGET(self->web_view));
      self->web_view = nullptr;
      self->web_context = nullptr;
      self->visible = FALSE;
      self->last_width = 0;
      self->last_height = 0;
      g_clear_pointer(&self->current_uri, g_free);
      g_hash_table_remove_all(self->app_initiated_navigations);
      g_hash_table_remove_all(self->virtual_resources);
      self->navigation_resolver_enabled = FALSE;
      self->resource_resolver_enabled = FALSE;
    }
    response = success_null();
  } else if (strcmp(method, "setNavigationResolverEnabled") == 0) {
    self->navigation_resolver_enabled =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
        fl_value_get_bool(args);
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
    self->web_context = nullptr;
    self->visible = FALSE;
  }
  if (self->channel != nullptr) {
    g_object_unref(self->channel);
    self->channel = nullptr;
  }
  if (self->configuration != nullptr) {
    fl_value_unref(self->configuration);
    self->configuration = nullptr;
  }
  if (self->pending_load != nullptr) {
    fl_value_unref(self->pending_load);
    self->pending_load = nullptr;
  }
  if (self->flutter_view != nullptr) {
    g_object_unref(self->flutter_view);
    self->flutter_view = nullptr;
  }
  g_clear_pointer(&self->current_uri, g_free);
  if (self->virtual_resources != nullptr) {
    g_hash_table_unref(self->virtual_resources);
    self->virtual_resources = nullptr;
  }
  if (self->registered_schemes != nullptr) {
    g_hash_table_unref(self->registered_schemes);
    self->registered_schemes = nullptr;
  }
  if (self->app_initiated_navigations != nullptr) {
    g_hash_table_unref(self->app_initiated_navigations);
    self->app_initiated_navigations = nullptr;
  }
  if (self->navigation_allowed_schemes != nullptr) {
    g_hash_table_unref(self->navigation_allowed_schemes);
    self->navigation_allowed_schemes = nullptr;
  }
  if (self->navigation_external_schemes != nullptr) {
    g_hash_table_unref(self->navigation_external_schemes);
    self->navigation_external_schemes = nullptr;
  }
  if (self->navigation_blocked_schemes != nullptr) {
    g_hash_table_unref(self->navigation_blocked_schemes);
    self->navigation_blocked_schemes = nullptr;
  }
  g_clear_pointer(&self->navigation_default_decision, g_free);
  g_clear_pointer(&self->virtual_resource_scheme, g_free);
  G_OBJECT_CLASS(papyrus_linux_plugin_parent_class)->dispose(object);
}

static void papyrus_linux_plugin_class_init(PapyrusLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = papyrus_linux_plugin_dispose;
}

static void papyrus_linux_plugin_init(PapyrusLinuxPlugin* self) {
  self->flutter_view = nullptr;
  self->channel = nullptr;
  self->configuration = nullptr;
  self->pending_load = nullptr;
  self->overlay = nullptr;
  self->fixed = nullptr;
  self->web_view = nullptr;
  self->web_context = nullptr;
  self->current_uri = nullptr;
  self->allow_file_access = FALSE;
  self->navigation_resolver_enabled = FALSE;
  self->resource_resolver_enabled = FALSE;
    self->require_user_gesture_for_external_open = TRUE;
    self->allow_main_frame_navigation = FALSE;
    self->allow_sub_frame_navigation = FALSE;
  self->visible = FALSE;
    self->navigation_default_decision = g_strdup("block");
  self->virtual_resource_scheme = g_strdup(kDefaultVirtualResourceScheme);
    self->app_initiated_navigations =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
    self->navigation_allowed_schemes =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
    self->navigation_external_schemes =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
    self->navigation_blocked_schemes =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
    string_set_assign_defaults(self->navigation_allowed_schemes,
                 kDefaultNavigationAllowedSchemes);
    string_set_assign_defaults(self->navigation_external_schemes,
                 kDefaultNavigationExternalSchemes);
    string_set_assign_defaults(self->navigation_blocked_schemes,
                 kDefaultNavigationBlockedSchemes);
  self->virtual_resources = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free,
      reinterpret_cast<GDestroyNotify>(papyrus_linux_inline_resource_free));
  self->registered_schemes =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, nullptr);
  self->inline_document_counter = 0;
  self->last_x = 0;
  self->last_y = 0;
  self->last_width = 0;
  self->last_height = 0;
}

static void papyrus_linux_selected_text_cb(GObject* object,
                                           GAsyncResult* result,
                                           gpointer user_data) {
  PapyrusLinuxMethodInvocation* invocation =
      static_cast<PapyrusLinuxMethodInvocation*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = nullptr;

  g_autoptr(JSCValue) javascript_value =
      webkit_web_view_evaluate_javascript_finish(
          WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    response = error_response("papyrus_linux", error->message);
  } else if (javascript_value == nullptr ||
             jsc_value_is_null(javascript_value) ||
             jsc_value_is_undefined(javascript_value)) {
    response = success_null();
  } else {
    g_autofree gchar* text = jsc_value_to_string(javascript_value);
    if (text == nullptr || text[0] == '\0' || g_strcmp0(text, "null") == 0) {
      response = success_null();
    } else {
      gchar* normalized_text = text;
      const size_t length = strlen(text);
      if (length >= 2 && text[0] == '"' && text[length - 1] == '"') {
        text[length - 1] = '\0';
        normalized_text = text + 1;
      }
      if (normalized_text[0] == '\0') {
        response = success_null();
      } else {
        g_autoptr(FlValue) result_value = fl_value_new_string(normalized_text);
        response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(result_value));
      }
    }
  }

  fl_method_call_respond(invocation->method_call, response, nullptr);
  papyrus_linux_method_invocation_free(invocation);
}

static void papyrus_linux_snapshot_cb(GObject* object,
                                      GAsyncResult* result,
                                      gpointer user_data) {
  PapyrusLinuxMethodInvocation* invocation =
      static_cast<PapyrusLinuxMethodInvocation*>(user_data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(FlMethodResponse) response = nullptr;

  cairo_surface_t* surface = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr || surface == nullptr) {
    response = error_response(
        error != nullptr ? "papyrus_linux" : "webViewUnavailable",
        error != nullptr ? error->message
                         : "Failed to capture a Linux WebKit snapshot.");
  } else {
    GtkWidget* widget = GTK_WIDGET(object);
    const gint width = std::max(1, gtk_widget_get_allocated_width(widget));
    const gint height = std::max(1, gtk_widget_get_allocated_height(widget));
    g_autoptr(GdkPixbuf) pixbuf =
        gdk_pixbuf_get_from_surface(surface, 0, 0, width, height);
    cairo_surface_destroy(surface);

    if (pixbuf == nullptr) {
      response = error_response("webViewUnavailable",
                                "Failed to convert Linux WebKit snapshot surface.");
    } else {
      gchar* buffer = nullptr;
      gsize buffer_size = 0;
      g_autoptr(GError) save_error = nullptr;
      if (!gdk_pixbuf_save_to_buffer(pixbuf, &buffer, &buffer_size, "png",
                                     &save_error, nullptr)) {
        g_free(buffer);
        response = error_response(
            save_error != nullptr ? "papyrus_linux" : "webViewUnavailable",
            save_error != nullptr ? save_error->message
                                  : "Failed to encode Linux WebKit snapshot as PNG.");
      } else {
        g_autoptr(FlValue) result_value = fl_value_new_uint8_list(
            reinterpret_cast<const guint8*>(buffer), buffer_size);
        g_free(buffer);
        response = FL_METHOD_RESPONSE(
            fl_method_success_response_new(result_value));
      }
    }
  }

  fl_method_call_respond(invocation->method_call, response, nullptr);
  papyrus_linux_method_invocation_free(invocation);
}

static void papyrus_linux_uri_changed_cb(WebKitWebView* web_view,
                                         GParamSpec* pspec,
                                         gpointer user_data) {
  (void)pspec;
  PapyrusLinuxPlugin* self = PAPYRUS_LINUX_PLUGIN(user_data);
  const gchar* uri = webkit_web_view_get_uri(web_view);
  if (uri == nullptr || uri[0] == '\0' || g_strcmp0(uri, "about:blank") == 0) {
    return;
  }
  replace_string(&self->current_uri, uri);
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
