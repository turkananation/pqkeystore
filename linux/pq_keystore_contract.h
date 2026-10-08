// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Platform channel contract v1 — argument validation for Linux.
// Must match lib/src/backend/platform_contract.dart and
// test/contract/reference_native_store.dart exactly.

#ifndef PQ_KEYSTORE_CONTRACT_H_
#define PQ_KEYSTORE_CONTRACT_H_

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <string>
#include <vector>

namespace pqkeystore {

constexpr const char kChannelName[] = "com.yardenah.pqkeystore/store";
constexpr int kContractVersion = 1;
constexpr size_t kMaxIdUtf8Bytes = 256;
constexpr size_t kMaxRecordBytes = 1024 * 1024;

// Error codes (closed set).
constexpr const char kErrInvalidArgs[] = "INVALID_ARGS";
constexpr const char kErrUnsupportedOption[] = "UNSUPPORTED_OPTION";
constexpr const char kErrUnavailable[] = "UNAVAILABLE";
constexpr const char kErrLocked[] = "LOCKED";
constexpr const char kErrUserCancelled[] = "USER_CANCELLED";
constexpr const char kErrCorrupt[] = "CORRUPT";
constexpr const char kErrStorage[] = "STORAGE_ERROR";

enum class Method { kPlatformInfo, kPut, kGet, kDelete, kContains, kListIds,
                    kUnknown };

Method ParseMethod(const gchar* name);

struct Request {
  Method method = Method::kUnknown;
  std::string id;
  std::vector<uint8_t> data;
};

struct ContractError {
  std::string code;
  std::string message;
};

// Validates `args` for `method` and fills `out`. Returns false and fills
// `error` on any violation. Linux supports no optional capabilities, so any
// non-default option yields UNSUPPORTED_OPTION.
//
// Limitation: the Linux embedder's standard codec truncates strings at U+0000
// before the plugin sees them, so an embedded NUL cannot be detected here.
// The Dart client rejects such IDs before they reach the channel.
bool ParseRequest(Method method, FlValue* args, Request* out,
                  ContractError* error);

// True if `id` satisfies the v1 ID rules (non-empty, valid UTF-8, no NUL,
// <= kMaxIdUtf8Bytes).
bool IsValidId(const std::string& id);

}  // namespace pqkeystore

#endif  // PQ_KEYSTORE_CONTRACT_H_
