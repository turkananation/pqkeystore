// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Linux plugin: channel wiring and threading.
//
// Threading model: arguments are validated on the GTK main thread; storage
// operations run on a single exclusive worker thread (so calls are executed
// strictly in arrival order and Secret Service prompts never block the UI);
// responses are delivered back on the main context.

#include "include/pqkeystore/pq_keystore_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <algorithm>
#include <memory>
#include <string>

#include "pq_keystore_contract.h"
#include "pq_keystore_secret_store.h"

#define PQ_KEYSTORE_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), pq_keystore_plugin_get_type(), \
                              PqKeystorePlugin))

struct _PqKeystorePlugin {
  GObject parent_instance;
  GThreadPool* worker;
  pqkeystore::SecretStore* store;
};

G_DEFINE_TYPE(PqKeystorePlugin, pq_keystore_plugin, g_object_get_type())

namespace {

struct Job {
  PqKeystorePlugin* plugin;  // Strong ref.
  FlMethodCall* call;        // Strong ref.
  pqkeystore::Request request;
  pqkeystore::StoreResult result;
};

FlMethodResponse* ErrorResponse(const std::string& code,
                                const std::string& message) {
  return FL_METHOD_RESPONSE(fl_method_error_response_new(
      code.c_str(), message.c_str(), nullptr));
}

FlMethodResponse* ToResponse(const pqkeystore::StoreResult& r) {
  using Kind = pqkeystore::StoreResult::Kind;
  g_autoptr(FlValue) value = nullptr;
  switch (r.kind) {
    case Kind::kError:
      return ErrorResponse(r.error.code, r.error.message);
    case Kind::kNull:
      value = fl_value_new_null();
      break;
    case Kind::kBool:
      value = fl_value_new_bool(r.boolean);
      break;
    case Kind::kBytes:
      value = fl_value_new_uint8_list(r.bytes.data(), r.bytes.size());
      break;
    case Kind::kStrings:
      value = fl_value_new_list();
      for (const auto& s : r.strings) {
        fl_value_append_take(value, fl_value_new_string(s.c_str()));
      }
      break;
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(value));
}

gboolean RespondOnMain(gpointer data) {
  std::unique_ptr<Job> job(static_cast<Job*>(data));
  g_autoptr(FlMethodResponse) response = ToResponse(job->result);
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(job->call, response, &error)) {
    g_warning("pqkeystore: failed to send response: %s", error->message);
  }
  // Wipe any record bytes held by the job before release.
  std::fill(job->result.bytes.begin(), job->result.bytes.end(), 0);
  std::fill(job->request.data.begin(), job->request.data.end(), 0);
  g_object_unref(job->call);
  g_object_unref(job->plugin);
  return G_SOURCE_REMOVE;
}

void RunOnWorker(gpointer data, gpointer /*user_data*/) {
  Job* job = static_cast<Job*>(data);
  pqkeystore::SecretStore* store = job->plugin->store;
  const auto& req = job->request;
  switch (req.method) {
    case pqkeystore::Method::kPut:
      job->result = store->Put(req.id, req.data);
      break;
    case pqkeystore::Method::kGet:
      job->result = store->Get(req.id);
      break;
    case pqkeystore::Method::kDelete:
      job->result = store->Delete(req.id);
      break;
    case pqkeystore::Method::kContains:
      job->result = store->Contains(req.id);
      break;
    case pqkeystore::Method::kListIds:
      job->result = store->ListIds();
      break;
    default:
      job->result.kind = pqkeystore::StoreResult::Kind::kError;
      job->result.error = {pqkeystore::kErrInvalidArgs, "unknown method"};
      break;
  }
  g_main_context_invoke(nullptr, RespondOnMain, job);
}

FlMethodResponse* PlatformInfoResponse() {
  g_autoptr(FlValue) info = fl_value_new_map();
  fl_value_set_string_take(info, "contractVersion",
                           fl_value_new_int(pqkeystore::kContractVersion));
  fl_value_set_string_take(info, "os", fl_value_new_string("linux"));
  fl_value_set_string_take(info, "backend",
                           fl_value_new_string("libsecret-secret-service"));
  // Linux cannot enforce any optional capability.
  fl_value_set_string_take(info, "supportedOptions", fl_value_new_list());
  return FL_METHOD_RESPONSE(fl_method_success_response_new(info));
}

// Application namespace so different apps in one session do not collide.
// This is namespacing, not isolation: Secret Service has no per-app ACL.
std::string AppNamespace() {
  GApplication* app = g_application_get_default();
  const gchar* id = app != nullptr ? g_application_get_application_id(app)
                                   : nullptr;
  if (id != nullptr && *id != '\0') return id;
  const gchar* prg = g_get_prgname();
  if (prg != nullptr && *prg != '\0') return prg;
  return "unknown";
}

}  // namespace

static void pq_keystore_plugin_handle_method_call(PqKeystorePlugin* self,
                                                  FlMethodCall* method_call) {
  const pqkeystore::Method method =
      pqkeystore::ParseMethod(fl_method_call_get_name(method_call));
  if (method == pqkeystore::Method::kUnknown) {
    g_autoptr(FlMethodResponse) r =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, r, nullptr);
    return;
  }
  if (method == pqkeystore::Method::kPlatformInfo) {
    g_autoptr(FlMethodResponse) r = PlatformInfoResponse();
    fl_method_call_respond(method_call, r, nullptr);
    return;
  }

  auto job = std::make_unique<Job>();
  pqkeystore::ContractError error;
  if (!pqkeystore::ParseRequest(method, fl_method_call_get_args(method_call),
                                &job->request, &error)) {
    g_autoptr(FlMethodResponse) r = ErrorResponse(error.code, error.message);
    fl_method_call_respond(method_call, r, nullptr);
    return;
  }

  job->plugin = PQ_KEYSTORE_PLUGIN(g_object_ref(self));
  job->call = FL_METHOD_CALL(g_object_ref(method_call));
  g_autoptr(GError) push_error = nullptr;
  Job* raw = job.release();
  if (!g_thread_pool_push(self->worker, raw, &push_error)) {
    raw->result.kind = pqkeystore::StoreResult::Kind::kError;
    raw->result.error = {pqkeystore::kErrStorage, "worker unavailable"};
    RespondOnMain(raw);
  }
}

static void pq_keystore_plugin_dispose(GObject* object) {
  PqKeystorePlugin* self = PQ_KEYSTORE_PLUGIN(object);
  if (self->worker != nullptr) {
    // Jobs hold a plugin ref, so the pool is idle when dispose runs.
    g_thread_pool_free(self->worker, FALSE, TRUE);
    self->worker = nullptr;
  }
  delete self->store;
  self->store = nullptr;
  G_OBJECT_CLASS(pq_keystore_plugin_parent_class)->dispose(object);
}

static void pq_keystore_plugin_class_init(PqKeystorePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = pq_keystore_plugin_dispose;
}

static void pq_keystore_plugin_init(PqKeystorePlugin* self) {
  // max_threads = 1, exclusive: strict FIFO execution of storage operations.
  self->worker = g_thread_pool_new(RunOnWorker, nullptr, 1, TRUE, nullptr);
  self->store = new pqkeystore::SecretStore(AppNamespace());
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  pq_keystore_plugin_handle_method_call(PQ_KEYSTORE_PLUGIN(user_data),
                                        method_call);
}

void pq_keystore_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  PqKeystorePlugin* plugin = PQ_KEYSTORE_PLUGIN(
      g_object_new(pq_keystore_plugin_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), pqkeystore::kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
