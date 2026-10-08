// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Native unit tests for Windows: contract validation and the DPAPI store.
// Store tests use real DPAPI under the test executable's namespace
// (%LOCALAPPDATA%\yardenah\pqkeystore\pqkeystore_test\v1) with test-only data.

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <flutter/encodable_value.h>
#include <gtest/gtest.h>

#include <string>
#include <vector>

#include "pq_keystore_contract.h"
#include "pq_keystore_dpapi_store.h"

namespace pqkeystore {
namespace test {

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

EncodableValue Options(bool presence = false,
                       const std::string& access = "platformDefault") {
  return EncodableValue(EncodableMap{
      {EncodableValue("requireUserPresence"), EncodableValue(presence)},
      {EncodableValue("requireBiometric"), EncodableValue(false)},
      {EncodableValue("accessibility"), EncodableValue(access)},
      {EncodableValue("synchronizable"), EncodableValue(false)},
  });
}

EncodableValue PutArgs(const std::string& id, size_t size,
                       EncodableValue options) {
  return EncodableValue(EncodableMap{
      {EncodableValue("id"), EncodableValue(id)},
      {EncodableValue("data"),
       EncodableValue(std::vector<uint8_t>(size, 0x5a))},
      {EncodableValue("options"), options},
  });
}

std::string Parse(Method m, const EncodableValue* args) {
  Request req;
  ContractError err;
  return ParseRequest(m, args, &req, &err) ? "OK" : err.code;
}

const std::string kPrefix = "pqks-native-test/";

void Cleanup(DpapiStore& store) {
  for (const auto& id : store.ListIds().strings) {
    if (id.rfind(kPrefix, 0) == 0) store.Delete(id);
  }
}

}  // namespace

TEST(Contract, IdRules) {
  EXPECT_TRUE(IsValidId("a"));
  EXPECT_TRUE(IsValidId("caf\xc3\xa9"));
  EXPECT_TRUE(IsValidId(std::string(kMaxIdUtf8Bytes, 'a')));
  EXPECT_FALSE(IsValidId(""));
  EXPECT_FALSE(IsValidId(std::string(kMaxIdUtf8Bytes + 1, 'a')));
  EXPECT_FALSE(IsValidId(std::string("a\0b", 3)));
  EXPECT_FALSE(IsValidId("\xff"));
  EXPECT_FALSE(IsValidId("\xc0\xaf"));          // Overlong.
  EXPECT_FALSE(IsValidId("\xed\xa0\x80"));      // Surrogate.
}

TEST(Contract, PutValidation) {
  auto ok = PutArgs("id", 1, Options());
  EXPECT_EQ(Parse(Method::kPut, &ok), "OK");
  auto empty = PutArgs("id", 0, Options());
  EXPECT_EQ(Parse(Method::kPut, &empty), kErrInvalidArgs);
  auto big = PutArgs("id", kMaxRecordBytes + 1, Options());
  EXPECT_EQ(Parse(Method::kPut, &big), kErrInvalidArgs);
  auto presence = PutArgs("id", 1, Options(true));
  EXPECT_EQ(Parse(Method::kPut, &presence), kErrUnsupportedOption);
  auto unlocked = PutArgs("id", 1, Options(false, "whenUnlocked"));
  EXPECT_EQ(Parse(Method::kPut, &unlocked), kErrUnsupportedOption);
  auto bad = PutArgs("id", 1, Options(false, "always"));
  EXPECT_EQ(Parse(Method::kPut, &bad), kErrInvalidArgs);
}

TEST(Contract, ArgumentShape) {
  EncodableValue not_map("x");
  EXPECT_EQ(Parse(Method::kGet, &not_map), kErrInvalidArgs);
  EXPECT_EQ(Parse(Method::kGet, nullptr), kErrInvalidArgs);
  EncodableValue extra(EncodableMap{{EncodableValue("id"), EncodableValue("a")},
                                    {EncodableValue("key"), EncodableValue("a")}});
  EXPECT_EQ(Parse(Method::kGet, &extra), kErrInvalidArgs);
  EncodableValue list_args(EncodableMap{});
  EXPECT_EQ(Parse(Method::kListIds, &list_args), kErrInvalidArgs);
  EXPECT_EQ(Parse(Method::kListIds, nullptr), "OK");
}

TEST(DpapiStore, RoundTripReplaceDelete) {
  DpapiStore store;
  Cleanup(store);
  const std::string id = kPrefix + "rt";
  EXPECT_EQ(store.Get(id).kind, StoreResult::Kind::kNull);
  EXPECT_FALSE(store.Delete(id).boolean);

  ASSERT_EQ(store.Put(id, {1, 2, 3}).kind, StoreResult::Kind::kNull);
  ASSERT_EQ(store.Put(id, {9, 8}).kind, StoreResult::Kind::kNull);
  auto got = store.Get(id);
  ASSERT_EQ(got.kind, StoreResult::Kind::kBytes);
  EXPECT_EQ(got.bytes, (std::vector<uint8_t>{9, 8}));
  EXPECT_TRUE(store.Contains(id).boolean);
  EXPECT_TRUE(store.Delete(id).boolean);
  EXPECT_FALSE(store.Contains(id).boolean);
  Cleanup(store);
}

TEST(DpapiStore, CaseVariantsDoNotAlias) {
  DpapiStore store;
  Cleanup(store);
  ASSERT_EQ(store.Put(kPrefix + "Key", {1}).kind, StoreResult::Kind::kNull);
  ASSERT_EQ(store.Put(kPrefix + "key", {2}).kind, StoreResult::Kind::kNull);
  EXPECT_EQ(store.Get(kPrefix + "Key").bytes, (std::vector<uint8_t>{1}));
  EXPECT_EQ(store.Get(kPrefix + "key").bytes, (std::vector<uint8_t>{2}));
  EXPECT_EQ(store.ListIds().strings.size() >= 2, true);
  Cleanup(store);
}

}  // namespace test
}  // namespace pqkeystore
