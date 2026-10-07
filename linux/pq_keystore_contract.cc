// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#include "pq_keystore_contract.h"

#include <cstring>
#include <set>

namespace pqkeystore {
namespace {

constexpr const char kArgId[] = "id";
constexpr const char kArgData[] = "data";
constexpr const char kArgOptions[] = "options";

bool Fail(ContractError* error, const char* code, const char* message) {
  error->code = code;
  error->message = message;
  return false;
}

bool CheckKeys(FlValue* map, const std::set<std::string>& allowed,
               ContractError* error) {
  const size_t n = fl_value_get_length(map);
  for (size_t i = 0; i < n; i++) {
    FlValue* key = fl_value_get_map_key(map, i);
    if (fl_value_get_type(key) != FL_VALUE_TYPE_STRING ||
        allowed.count(fl_value_get_string(key)) == 0) {
      return Fail(error, kErrInvalidArgs, "unexpected argument");
    }
  }
  return true;
}

bool ParseId(FlValue* args, Request* out, ContractError* error) {
  FlValue* id = fl_value_lookup_string(args, kArgId);
  if (id == nullptr || fl_value_get_type(id) != FL_VALUE_TYPE_STRING) {
    return Fail(error, kErrInvalidArgs, "id must be a string");
  }
  out->id = fl_value_get_string(id);
  if (!IsValidId(out->id)) {
    return Fail(error, kErrInvalidArgs, "invalid id");
  }
  return true;
}

bool LookupBool(FlValue* options, const char* key, bool* out) {
  FlValue* v = fl_value_lookup_string(options, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_BOOL) {
    return false;
  }
  *out = fl_value_get_bool(v);
  return true;
}

bool ParseOptions(FlValue* options, ContractError* error) {
  if (options == nullptr || fl_value_get_type(options) != FL_VALUE_TYPE_MAP ||
      fl_value_get_length(options) != 4) {
    return Fail(error, kErrInvalidArgs,
                "options must contain exactly the v1 keys");
  }
  if (!CheckKeys(options,
                 {"requireUserPresence", "requireBiometric", "accessibility",
                  "synchronizable"},
                 error)) {
    return Fail(error, kErrInvalidArgs,
                "options must contain exactly the v1 keys");
  }
  bool presence = false, biometric = false, sync = false;
  if (!LookupBool(options, "requireUserPresence", &presence) ||
      !LookupBool(options, "requireBiometric", &biometric) ||
      !LookupBool(options, "synchronizable", &sync)) {
    return Fail(error, kErrInvalidArgs, "boolean option has wrong type");
  }
  FlValue* acc = fl_value_lookup_string(options, "accessibility");
  if (acc == nullptr || fl_value_get_type(acc) != FL_VALUE_TYPE_STRING) {
    return Fail(error, kErrInvalidArgs, "unknown accessibility");
  }
  const std::string accessibility = fl_value_get_string(acc);
  const bool non_default_access = accessibility != "platformDefault";
  if (non_default_access && accessibility != "whenUnlocked" &&
      accessibility != "afterFirstUnlock") {
    return Fail(error, kErrInvalidArgs, "unknown accessibility");
  }
  // Linux enforces no optional capability. Normative order: unsupported
  // capability first, then combinations (unreachable here).
  if (presence || biometric || sync || non_default_access) {
    return Fail(error, kErrUnsupportedOption,
                "option not enforceable on linux");
  }
  return true;
}

}  // namespace

Method ParseMethod(const gchar* name) {
  if (strcmp(name, "platformInfo") == 0) return Method::kPlatformInfo;
  if (strcmp(name, "put") == 0) return Method::kPut;
  if (strcmp(name, "get") == 0) return Method::kGet;
  if (strcmp(name, "delete") == 0) return Method::kDelete;
  if (strcmp(name, "contains") == 0) return Method::kContains;
  if (strcmp(name, "listIds") == 0) return Method::kListIds;
  return Method::kUnknown;
}

bool IsValidId(const std::string& id) {
  if (id.empty() || id.size() > kMaxIdUtf8Bytes) {
    return false;
  }
  if (memchr(id.data(), '\0', id.size()) != nullptr) {
    return false;
  }
  return g_utf8_validate(id.data(), static_cast<gssize>(id.size()), nullptr);
}

bool ParseRequest(Method method, FlValue* args, Request* out,
                  ContractError* error) {
  out->method = method;
  switch (method) {
    case Method::kPlatformInfo:
      return true;
    case Method::kListIds:
      if (args != nullptr && fl_value_get_type(args) != FL_VALUE_TYPE_NULL) {
        return Fail(error, kErrInvalidArgs, "listIds takes no arguments");
      }
      return true;
    case Method::kUnknown:
      return Fail(error, kErrInvalidArgs, "unknown method");
    default:
      break;
  }

  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return Fail(error, kErrInvalidArgs, "arguments must be a map");
  }

  if (method != Method::kPut) {
    return CheckKeys(args, {kArgId}, error) && ParseId(args, out, error);
  }

  if (!CheckKeys(args, {kArgId, kArgData, kArgOptions}, error) ||
      !ParseId(args, out, error)) {
    return false;
  }
  FlValue* data = fl_value_lookup_string(args, kArgData);
  if (data == nullptr || fl_value_get_type(data) != FL_VALUE_TYPE_UINT8_LIST ||
      fl_value_get_length(data) == 0 ||
      fl_value_get_length(data) > kMaxRecordBytes) {
    return Fail(error, kErrInvalidArgs, "data must be 1..1048576 bytes");
  }
  if (!ParseOptions(fl_value_lookup_string(args, kArgOptions), error)) {
    return false;
  }
  const uint8_t* bytes = fl_value_get_uint8_list(data);
  out->data.assign(bytes, bytes + fl_value_get_length(data));
  return true;
}

}  // namespace pqkeystore
