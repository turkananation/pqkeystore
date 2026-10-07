// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#include "pq_keystore_plugin.h"

// windows.h must precede most other Windows headers.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <memory>
#include <string>

#include "pq_keystore_contract.h"

namespace pqkeystore {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// static
void PqKeystorePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<PqKeystorePlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

PqKeystorePlugin::PqKeystorePlugin() = default;
PqKeystorePlugin::~PqKeystorePlugin() = default;

void PqKeystorePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const Method method = ParseMethod(method_call.method_name());
  if (method == Method::kUnknown) {
    result->NotImplemented();
    return;
  }
  if (method == Method::kPlatformInfo) {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("contractVersion"), EncodableValue(kContractVersion)},
        {EncodableValue("os"), EncodableValue("windows")},
        {EncodableValue("backend"), EncodableValue("dpapi-user-file")},
        // Windows cannot enforce any optional capability in v1.
        {EncodableValue("supportedOptions"), EncodableValue(EncodableList{})},
    }));
    return;
  }

  Request request;
  ContractError error;
  if (!ParseRequest(method, method_call.arguments(), &request, &error)) {
    result->Error(error.code, error.message);
    return;
  }

  StoreResult r;
  switch (method) {
    case Method::kPut:
      r = store_.Put(request.id, request.data);
      break;
    case Method::kGet:
      r = store_.Get(request.id);
      break;
    case Method::kDelete:
      r = store_.Delete(request.id);
      break;
    case Method::kContains:
      r = store_.Contains(request.id);
      break;
    case Method::kListIds:
      r = store_.ListIds();
      break;
    default:
      r.kind = StoreResult::Kind::kError;
      r.error = {kErrInvalidArgs, "unknown method"};
      break;
  }
  std::fill(request.data.begin(), request.data.end(), uint8_t{0});

  switch (r.kind) {
    case StoreResult::Kind::kError:
      result->Error(r.error.code, r.error.message);
      break;
    case StoreResult::Kind::kNull:
      result->Success();
      break;
    case StoreResult::Kind::kBool:
      result->Success(EncodableValue(r.boolean));
      break;
    case StoreResult::Kind::kBytes:
      result->Success(EncodableValue(r.bytes));
      std::fill(r.bytes.begin(), r.bytes.end(), uint8_t{0});
      break;
    case StoreResult::Kind::kStrings: {
      EncodableList list;
      for (const auto& s : r.strings) list.emplace_back(s);
      result->Success(EncodableValue(list));
      break;
    }
  }
}

}  // namespace pqkeystore
