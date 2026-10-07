// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Secret Service storage for Linux (libsecret). Blocking; call only from the
// plugin's worker thread, never from the GTK main thread.
//
// Layout: one Secret Service item per record in the default collection.
//   schema     : com.yardenah.pqkeystore.v1
//   attributes : app = <application namespace>, id = <storage ID>
//   secret     : canonical base64 of the record bytes (text/plain)
//   label      : "pqkeystore record" (IDs are not placed in labels)
//
// There is deliberately no file fallback: if no Secret Service is reachable
// every operation fails with UNAVAILABLE.

#ifndef PQ_KEYSTORE_SECRET_STORE_H_
#define PQ_KEYSTORE_SECRET_STORE_H_

#include <cstdint>
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

class SecretStore {
 public:
  explicit SecretStore(std::string app_namespace);

  StoreResult Put(const std::string& id, const std::vector<uint8_t>& data);
  StoreResult Get(const std::string& id);
  StoreResult Delete(const std::string& id);
  StoreResult Contains(const std::string& id);
  StoreResult ListIds();

 private:
  std::string app_;
};

}  // namespace pqkeystore

#endif  // PQ_KEYSTORE_SECRET_STORE_H_
