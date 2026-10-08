// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform channel contract v1 — argument validation for Windows.
// Must match lib/src/backend/platform_contract.dart and
// test/contract/reference_native_store.dart exactly.

#ifndef PQ_KEYSTORE_CONTRACT_H_
#define PQ_KEYSTORE_CONTRACT_H_

#include <flutter/encodable_value.h>

#include <cstdint>
#include <string>
#include <vector>

namespace pqkeystore {

constexpr const char kChannelName[] = "com.yardenah.pqkeystore/store";
constexpr int kContractVersion = 1;
constexpr size_t kMaxIdUtf8Bytes = 256;
constexpr size_t kMaxRecordBytes = 1024 * 1024;

constexpr const char kErrInvalidArgs[] = "INVALID_ARGS";
constexpr const char kErrUnsupportedOption[] = "UNSUPPORTED_OPTION";
constexpr const char kErrUnavailable[] = "UNAVAILABLE";
constexpr const char kErrCorrupt[] = "CORRUPT";
constexpr const char kErrStorage[] = "STORAGE_ERROR";

enum class Method { kPlatformInfo, kPut, kGet, kDelete, kContains, kListIds,
                    kUnknown };

Method ParseMethod(const std::string& name);

struct Request {
  Method method = Method::kUnknown;
  std::string id;  // UTF-8.
  std::vector<uint8_t> data;
};

struct ContractError {
  std::string code;
  std::string message;
};

// Validates `args` (may be null) for `method`. Windows supports no optional
// capability, so any non-default option yields UNSUPPORTED_OPTION.
bool ParseRequest(Method method, const flutter::EncodableValue* args,
                  Request* out, ContractError* error);

// Non-empty, valid UTF-8, no NUL, <= kMaxIdUtf8Bytes.
bool IsValidId(const std::string& id);

}  // namespace pqkeystore

#endif  // PQ_KEYSTORE_CONTRACT_H_
