// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#include "pq_keystore_secret_store.h"

#include <libsecret/secret.h>

#include <atomic>
#include <cstring>
#include <set>
#include <utility>

namespace pqkeystore {
namespace {

const SecretSchema* Schema() {
  static const SecretSchema schema = {
      "com.yardenah.pqkeystore.v1",
      SECRET_SCHEMA_NONE,
      {
          {"app", SECRET_SCHEMA_ATTRIBUTE_STRING},
          {"id", SECRET_SCHEMA_ATTRIBUTE_STRING},
          {nullptr, SECRET_SCHEMA_ATTRIBUTE_STRING},
      },
      // Reserved fields.
      0, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
  return &schema;
}

StoreResult Error(const char* code, std::string message) {
  StoreResult r;
  r.kind = StoreResult::Kind::kError;
  r.error.code = code;
  r.error.message = std::move(message);
  return r;
}

// Maps a GError to a contract error. Messages carry no record data.
StoreResult FromGError(const char* what, GError* error) {
  std::string message = std::string(what) + ": " + error->message;
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
    return Error(kErrUserCancelled, message);
  }
  if (error->domain == SECRET_ERROR && error->code == SECRET_ERROR_IS_LOCKED) {
    return Error(kErrLocked, message);
  }
  if (error->domain == G_DBUS_ERROR &&
      (error->code == G_DBUS_ERROR_SERVICE_UNKNOWN ||
       error->code == G_DBUS_ERROR_NAME_HAS_NO_OWNER ||
       error->code == G_DBUS_ERROR_SPAWN_FAILED ||
       error->code == G_DBUS_ERROR_SPAWN_EXEC_FAILED ||
       error->code == G_DBUS_ERROR_SPAWN_CHILD_EXITED ||
       error->code == G_DBUS_ERROR_SPAWN_SERVICE_NOT_FOUND)) {
    return Error(kErrUnavailable, message);
  }
  return Error(kErrStorage, message);
}

// Upper bound for reaching (and, if needed, D-Bus-activating) the Secret
// Service. Without it a provider that is activatable but never comes up
// would stall every call on libsecret's long internal timeouts.
constexpr int kReachTimeoutMs = 5000;

// Bounded reachability probe via org.freedesktop.DBus.Peer.Ping. Skipped once
// a connection has succeeded; user-paced unlock prompts are not bounded.
bool Reachable(StoreResult* failure) {
  static std::atomic<bool> reached{false};
  if (reached.load()) return true;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) {
    *failure = Error(kErrUnavailable, std::string("no D-Bus session bus: ") +
                                          error->message);
    return false;
  }
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.freedesktop.secrets", "/org/freedesktop/secrets",
      "org.freedesktop.DBus.Peer", "Ping", nullptr, nullptr,
      G_DBUS_CALL_FLAGS_NONE, kReachTimeoutMs, nullptr, &error);
  if (reply == nullptr) {
    *failure = Error(kErrUnavailable, std::string("Secret Service unreachable: ") +
                                          error->message);
    return false;
  }
  reached.store(true);
  return true;
}

// Connects to the Secret Service (libsecret caches the proxy).
SecretService* Connect(StoreResult* failure) {
  if (!Reachable(failure)) return nullptr;
  g_autoptr(GError) error = nullptr;
  SecretService* service =
      secret_service_get_sync(SECRET_SERVICE_OPEN_SESSION, nullptr, &error);
  if (service == nullptr) {
    *failure = Error(kErrUnavailable,
                     std::string("Secret Service unavailable: ") +
                         (error != nullptr ? error->message : "unknown"));
  }
  return service;
}

GHashTable* Attributes(const std::string& app, const std::string* id) {
  if (id == nullptr) {
    return secret_attributes_build(Schema(), "app", app.c_str(), nullptr);
  }
  return secret_attributes_build(Schema(), "app", app.c_str(), "id",
                                 id->c_str(), nullptr);
}

void SecureClear(gchar* text) {
  if (text != nullptr) {
    volatile gchar* p = text;
    while (*p != '\0') {
      *p++ = '\0';
    }
  }
}

}  // namespace

SecretStore::SecretStore(std::string app_namespace)
    : app_(std::move(app_namespace)) {}

StoreResult SecretStore::Put(const std::string& id,
                             const std::vector<uint8_t>& data) {
  StoreResult failure;
  g_autoptr(SecretService) service = Connect(&failure);
  if (service == nullptr) return failure;

  g_autoptr(GHashTable) attrs = Attributes(app_, &id);
  gchar* encoded = g_base64_encode(data.data(), data.size());
  // secret_value_new copies into libsecret's secure memory.
  SecretValue* value = secret_value_new(encoded, -1, "text/plain");
  SecureClear(encoded);
  g_free(encoded);

  // Replaces an existing item with identical attributes in one D-Bus call.
  g_autoptr(GError) error = nullptr;
  const gboolean ok = secret_service_store_sync(
      service, Schema(), attrs, SECRET_COLLECTION_DEFAULT, "pqkeystore record",
      value, nullptr, &error);
  secret_value_unref(value);
  if (!ok) {
    if (error != nullptr) return FromGError("store failed", error);
    return Error(kErrStorage, "store failed");
  }
  return StoreResult();
}

StoreResult SecretStore::Get(const std::string& id) {
  StoreResult failure;
  g_autoptr(SecretService) service = Connect(&failure);
  if (service == nullptr) return failure;

  g_autoptr(GHashTable) attrs = Attributes(app_, &id);
  g_autoptr(GError) error = nullptr;
  GList* items = secret_service_search_sync(
      service, Schema(), attrs,
      static_cast<SecretSearchFlags>(SECRET_SEARCH_ALL | SECRET_SEARCH_UNLOCK |
                                     SECRET_SEARCH_LOAD_SECRETS),
      nullptr, &error);
  if (error != nullptr) {
    g_list_free_full(items, g_object_unref);
    return FromGError("search failed", error);
  }
  if (items == nullptr) {
    return StoreResult();  // Not found → null.
  }
  if (items->next != nullptr) {
    g_list_free_full(items, g_object_unref);
    return Error(kErrCorrupt, "multiple items share one id");
  }

  SecretItem* item = SECRET_ITEM(items->data);
  StoreResult result;
  if (secret_item_get_locked(item)) {
    result = Error(kErrLocked, "collection is locked");
  } else {
    SecretValue* value = secret_item_get_secret(item);
    if (value == nullptr) {
      result = Error(kErrLocked, "secret could not be loaded");
    } else {
      const gchar* text = secret_value_get_text(value);
      gsize length = 0;
      guchar* decoded =
          text != nullptr ? g_base64_decode(text, &length) : nullptr;
      // g_base64_decode is lenient; require the canonical encoding.
      gchar* reencoded =
          decoded != nullptr ? g_base64_encode(decoded, length) : nullptr;
      if (decoded == nullptr || length == 0 || length > kMaxRecordBytes ||
          reencoded == nullptr || strcmp(reencoded, text) != 0) {
        result = Error(kErrCorrupt, "stored secret is not a valid record");
      } else {
        result.kind = StoreResult::Kind::kBytes;
        result.bytes.assign(decoded, decoded + length);
      }
      if (decoded != nullptr) memset(decoded, 0, length);
      g_free(decoded);
      SecureClear(reencoded);
      g_free(reencoded);
      secret_value_unref(value);
    }
  }
  g_list_free_full(items, g_object_unref);
  return result;
}

StoreResult SecretStore::Delete(const std::string& id) {
  StoreResult failure;
  g_autoptr(SecretService) service = Connect(&failure);
  if (service == nullptr) return failure;

  g_autoptr(GHashTable) attrs = Attributes(app_, &id);
  g_autoptr(GError) error = nullptr;
  const gboolean removed =
      secret_service_clear_sync(service, Schema(), attrs, nullptr, &error);
  if (error != nullptr) return FromGError("delete failed", error);
  StoreResult r;
  r.kind = StoreResult::Kind::kBool;
  r.boolean = removed;
  return r;
}

StoreResult SecretStore::Contains(const std::string& id) {
  StoreResult failure;
  g_autoptr(SecretService) service = Connect(&failure);
  if (service == nullptr) return failure;

  // Attribute matching works on locked collections; no unlock prompt.
  g_autoptr(GHashTable) attrs = Attributes(app_, &id);
  g_autoptr(GError) error = nullptr;
  GList* items = secret_service_search_sync(service, Schema(), attrs,
                                            SECRET_SEARCH_ALL, nullptr, &error);
  if (error != nullptr) {
    g_list_free_full(items, g_object_unref);
    return FromGError("search failed", error);
  }
  StoreResult r;
  r.kind = StoreResult::Kind::kBool;
  r.boolean = items != nullptr;
  g_list_free_full(items, g_object_unref);
  return r;
}

StoreResult SecretStore::ListIds() {
  StoreResult failure;
  g_autoptr(SecretService) service = Connect(&failure);
  if (service == nullptr) return failure;

  // Attribute values of locked items may not be readable (gnome-keyring
  // stores them hashed), so unlock first.
  g_autoptr(GHashTable) attrs = Attributes(app_, nullptr);
  g_autoptr(GError) error = nullptr;
  GList* items = secret_service_search_sync(
      service, Schema(), attrs,
      static_cast<SecretSearchFlags>(SECRET_SEARCH_ALL | SECRET_SEARCH_UNLOCK),
      nullptr, &error);
  if (error != nullptr) {
    g_list_free_full(items, g_object_unref);
    return FromGError("search failed", error);
  }

  StoreResult r;
  r.kind = StoreResult::Kind::kStrings;
  std::set<std::string> seen;
  for (GList* l = items; l != nullptr; l = l->next) {
    SecretItem* item = SECRET_ITEM(l->data);
    if (secret_item_get_locked(item)) {
      g_list_free_full(items, g_object_unref);
      return Error(kErrLocked, "collection is locked");
    }
    g_autoptr(GHashTable) item_attrs = secret_item_get_attributes(item);
    const gchar* id =
        static_cast<const gchar*>(g_hash_table_lookup(item_attrs, "id"));
    // Items written by something else under our schema are skipped.
    if (id != nullptr && IsValidId(id) && seen.insert(id).second) {
      r.strings.emplace_back(id);
    }
  }
  g_list_free_full(items, g_object_unref);
  return r;
}

}  // namespace pqkeystore
