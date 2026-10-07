// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// PQNW ("PQ Native Windows") DPAPI-protected file storage. Spec:
// doc/FORMATS.md §4. Not to be confused with PQKS, the portable record it
// encrypts.
//
// Location : %LOCALAPPDATA%\yardenah\pqkeystore\<app>\v1\
//            Directories created by the plugin get a protected DACL granting
//            access only to the current user and SYSTEM.
// File name: lowercase hex SHA-256 of the UTF-8 ID + ".pqnw" — injective in
//            practice, case-insensitive-filesystem safe, and short enough to
//            stay under MAX_PATH. IDs are never interpreted as paths.
// File body: "PQNW" | u8 version(1) | u16be idLen | id | u32be blobLen | blob
//            blob = CryptProtectData(record, entropy = context || app || id,
//                                    CRYPTPROTECT_UI_FORBIDDEN)
// Writes   : temp file + FlushFileBuffers + MoveFileExW(REPLACE_EXISTING |
//            WRITE_THROUGH). The previous entry stays intact until the
//            replacement is committed.
//
// An entry exists iff its file is present and its header names the requested
// ID. A file whose payload cannot be unprotected is reported as CORRUPT.

#ifndef PQ_KEYSTORE_DPAPI_STORE_H_
#define PQ_KEYSTORE_DPAPI_STORE_H_

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "pq_keystore_contract.h"

namespace pqkeystore {

struct StoreResult {
  enum class Kind { kNull, kBool, kBytes, kStrings, kError } kind = Kind::kNull;
  bool boolean = false;
  std::vector<uint8_t> bytes;
  std::vector<std::string> strings;
  ContractError error;
};

class DpapiStore {
 public:
  DpapiStore();

  StoreResult Put(const std::string& id, const std::vector<uint8_t>& data);
  StoreResult Get(const std::string& id);
  StoreResult Delete(const std::string& id);
  StoreResult Contains(const std::string& id);
  StoreResult ListIds();

 private:
  // Resolves (and creates, on first use) the storage directory.
  bool EnsureRoot(ContractError* error);
  std::wstring PathFor(const std::string& id) const;
  std::vector<uint8_t> Entropy(const std::string& id) const;
  void RemoveStaleTempFiles();

  std::string app_;
  std::wstring root_;
  bool root_ready_ = false;
  uint64_t temp_counter_ = 0;
};

}  // namespace pqkeystore

#endif  // PQ_KEYSTORE_DPAPI_STORE_H_
