// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#ifndef FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
#define FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

#include "pq_keystore_dpapi_store.h"

namespace pqkeystore {

// Threading: calls are handled synchronously on the platform thread, which
// serializes them in arrival order. Operations are bounded (records are at
// most 1 MiB and DPAPI never shows UI with CRYPTPROTECT_UI_FORBIDDEN).
class PqKeystorePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  PqKeystorePlugin();
  ~PqKeystorePlugin() override;

  PqKeystorePlugin(const PqKeystorePlugin&) = delete;
  PqKeystorePlugin& operator=(const PqKeystorePlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  DpapiStore store_;
};

}  // namespace pqkeystore

#endif  // FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
