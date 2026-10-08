// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#include "pq_keystore_contract.h"

#include <set>
#include <variant>

namespace pqkeystore {
namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

bool Fail(ContractError* error, const char* code, const char* message) {
  error->code = code;
  error->message = message;
  return false;
}

// Strict UTF-8: rejects overlongs, surrogates, and code points > U+10FFFF.
bool IsStrictUtf8(const std::string& s) {
  size_t i = 0;
  const size_t n = s.size();
  while (i < n) {
    const unsigned char c = static_cast<unsigned char>(s[i]);
    size_t len;
    uint32_t cp;
    if (c < 0x80) {
      i++;
      continue;
    } else if ((c & 0xE0) == 0xC0) {
      len = 2;
      cp = c & 0x1F;
    } else if ((c & 0xF0) == 0xE0) {
      len = 3;
      cp = c & 0x0F;
    } else if ((c & 0xF8) == 0xF0) {
      len = 4;
      cp = c & 0x07;
    } else {
      return false;
    }
    if (i + len > n) return false;
    for (size_t k = 1; k < len; k++) {
      const unsigned char cc = static_cast<unsigned char>(s[i + k]);
      if ((cc & 0xC0) != 0x80) return false;
      cp = (cp << 6) | (cc & 0x3F);
    }
    if ((len == 2 && cp < 0x80) || (len == 3 && cp < 0x800) ||
        (len == 4 && cp < 0x10000) || cp > 0x10FFFF ||
        (cp >= 0xD800 && cp <= 0xDFFF)) {
      return false;
    }
    i += len;
  }
  return true;
}

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  return it == map.end() ? nullptr : &it->second;
}

bool CheckKeys(const EncodableMap& map, const std::set<std::string>& allowed) {
  for (const auto& entry : map) {
    const auto* key = std::get_if<std::string>(&entry.first);
    if (key == nullptr || allowed.count(*key) == 0) return false;
  }
  return true;
}

bool ParseId(const EncodableMap& args, Request* out, ContractError* error) {
  const EncodableValue* v = Lookup(args, "id");
  const auto* id = v == nullptr ? nullptr : std::get_if<std::string>(v);
  if (id == nullptr || !IsValidId(*id)) {
    return Fail(error, kErrInvalidArgs, "invalid id");
  }
  out->id = *id;
  return true;
}

bool LookupBool(const EncodableMap& map, const char* key, bool* out) {
  const EncodableValue* v = Lookup(map, key);
  const bool* b = v == nullptr ? nullptr : std::get_if<bool>(v);
  if (b == nullptr) return false;
  *out = *b;
  return true;
}

bool ParseOptions(const EncodableValue* raw, ContractError* error) {
  const auto* options = raw == nullptr ? nullptr : std::get_if<EncodableMap>(raw);
  if (options == nullptr || options->size() != 4 ||
      !CheckKeys(*options, {"requireUserPresence", "requireBiometric",
                            "accessibility", "synchronizable"})) {
    return Fail(error, kErrInvalidArgs,
                "options must contain exactly the v1 keys");
  }
  bool presence = false, biometric = false, sync = false;
  if (!LookupBool(*options, "requireUserPresence", &presence) ||
      !LookupBool(*options, "requireBiometric", &biometric) ||
      !LookupBool(*options, "synchronizable", &sync)) {
    return Fail(error, kErrInvalidArgs, "boolean option has wrong type");
  }
  const EncodableValue* acc_value = Lookup(*options, "accessibility");
  const auto* acc =
      acc_value == nullptr ? nullptr : std::get_if<std::string>(acc_value);
  if (acc == nullptr || (*acc != "platformDefault" && *acc != "whenUnlocked" &&
                         *acc != "afterFirstUnlock")) {
    return Fail(error, kErrInvalidArgs, "unknown accessibility");
  }
  // Windows enforces no optional capability. Normative order: unsupported
  // capability first, then combinations (unreachable here).
  if (presence || biometric || sync || *acc != "platformDefault") {
    return Fail(error, kErrUnsupportedOption,
                "option not enforceable on windows");
  }
  return true;
}

}  // namespace

Method ParseMethod(const std::string& name) {
  if (name == "platformInfo") return Method::kPlatformInfo;
  if (name == "put") return Method::kPut;
  if (name == "get") return Method::kGet;
  if (name == "delete") return Method::kDelete;
  if (name == "contains") return Method::kContains;
  if (name == "listIds") return Method::kListIds;
  return Method::kUnknown;
}

bool IsValidId(const std::string& id) {
  return !id.empty() && id.size() <= kMaxIdUtf8Bytes &&
         id.find('\0') == std::string::npos && IsStrictUtf8(id);
}

bool ParseRequest(Method method, const EncodableValue* args, Request* out,
                  ContractError* error) {
  out->method = method;
  const bool args_null =
      args == nullptr || std::holds_alternative<std::monostate>(*args);
  switch (method) {
    case Method::kPlatformInfo:
      return true;
    case Method::kListIds:
      return args_null ||
             Fail(error, kErrInvalidArgs, "listIds takes no arguments");
    case Method::kUnknown:
      return Fail(error, kErrInvalidArgs, "unknown method");
    default:
      break;
  }

  const auto* map = args_null ? nullptr : std::get_if<EncodableMap>(args);
  if (map == nullptr) {
    return Fail(error, kErrInvalidArgs, "arguments must be a map");
  }
  if (method != Method::kPut) {
    if (!CheckKeys(*map, {"id"})) {
      return Fail(error, kErrInvalidArgs, "unexpected argument");
    }
    return ParseId(*map, out, error);
  }

  if (!CheckKeys(*map, {"id", "data", "options"})) {
    return Fail(error, kErrInvalidArgs, "unexpected argument");
  }
  if (!ParseId(*map, out, error)) return false;
  const EncodableValue* data_value = Lookup(*map, "data");
  const auto* data = data_value == nullptr
                         ? nullptr
                         : std::get_if<std::vector<uint8_t>>(data_value);
  if (data == nullptr || data->empty() || data->size() > kMaxRecordBytes) {
    return Fail(error, kErrInvalidArgs, "data must be 1..1048576 bytes");
  }
  if (!ParseOptions(Lookup(*map, "options"), error)) return false;
  out->data = *data;
  return true;
}

}  // namespace pqkeystore
