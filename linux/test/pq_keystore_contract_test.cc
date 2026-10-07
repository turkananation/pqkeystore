// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Native unit tests for Linux contract validation. No D-Bus required.
// Behavioral parity is proven by the Dart contract suite on device.

#include <flutter_linux/flutter_linux.h>
#include <gtest/gtest.h>

#include <string>

#include "pq_keystore_contract.h"

namespace pqkeystore {
namespace test {

namespace {

FlValue* Options(bool presence = false, const char* access = "platformDefault",
                 bool sync = false) {
  FlValue* o = fl_value_new_map();
  fl_value_set_string_take(o, "requireUserPresence",
                           fl_value_new_bool(presence));
  fl_value_set_string_take(o, "requireBiometric", fl_value_new_bool(false));
  fl_value_set_string_take(o, "accessibility", fl_value_new_string(access));
  fl_value_set_string_take(o, "synchronizable", fl_value_new_bool(sync));
  return o;
}

FlValue* PutArgs(const std::string& id, size_t size, FlValue* options) {
  FlValue* args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_string(id.c_str()));
  std::string data(size, '\x5a');
  fl_value_set_string_take(
      args, "data",
      fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(data.data()),
                              data.size()));
  fl_value_set_string_take(args, "options", options);
  return args;
}

std::string Parse(Method m, FlValue* args) {
  Request req;
  ContractError err;
  return ParseRequest(m, args, &req, &err) ? "OK" : err.code;
}

}  // namespace

TEST(Contract, MethodNames) {
  EXPECT_EQ(ParseMethod("put"), Method::kPut);
  EXPECT_EQ(ParseMethod("listIds"), Method::kListIds);
  EXPECT_EQ(ParseMethod("putJson"), Method::kUnknown);
}

TEST(Contract, IdRules) {
  EXPECT_TRUE(IsValidId("a"));
  EXPECT_TRUE(IsValidId("caf\xc3\xa9"));
  EXPECT_TRUE(IsValidId(std::string(kMaxIdUtf8Bytes, 'a')));
  EXPECT_FALSE(IsValidId(""));
  EXPECT_FALSE(IsValidId(std::string(kMaxIdUtf8Bytes + 1, 'a')));
  EXPECT_FALSE(IsValidId(std::string("a\0b", 3)));
  EXPECT_FALSE(IsValidId("\xff"));
}

TEST(Contract, PutValidation) {
  g_autoptr(FlValue) ok = PutArgs("id", 1, Options());
  EXPECT_EQ(Parse(Method::kPut, ok), "OK");

  g_autoptr(FlValue) max = PutArgs("id", kMaxRecordBytes, Options());
  EXPECT_EQ(Parse(Method::kPut, max), "OK");

  g_autoptr(FlValue) empty = PutArgs("id", 0, Options());
  EXPECT_EQ(Parse(Method::kPut, empty), kErrInvalidArgs);

  g_autoptr(FlValue) big = PutArgs("id", kMaxRecordBytes + 1, Options());
  EXPECT_EQ(Parse(Method::kPut, big), kErrInvalidArgs);

  g_autoptr(FlValue) bad_access = PutArgs("id", 1, Options(false, "always"));
  EXPECT_EQ(Parse(Method::kPut, bad_access), kErrInvalidArgs);
}

TEST(Contract, LinuxRejectsEveryOptionalCapability) {
  g_autoptr(FlValue) presence = PutArgs("id", 1, Options(true));
  EXPECT_EQ(Parse(Method::kPut, presence), kErrUnsupportedOption);
  g_autoptr(FlValue) unlocked = PutArgs("id", 1, Options(false, "whenUnlocked"));
  EXPECT_EQ(Parse(Method::kPut, unlocked), kErrUnsupportedOption);
  g_autoptr(FlValue) afu = PutArgs("id", 1, Options(false, "afterFirstUnlock"));
  EXPECT_EQ(Parse(Method::kPut, afu), kErrUnsupportedOption);
  g_autoptr(FlValue) sync = PutArgs("id", 1, Options(false, "platformDefault",
                                                     true));
  EXPECT_EQ(Parse(Method::kPut, sync), kErrUnsupportedOption);
}

TEST(Contract, OptionsShape) {
  FlValue* extra = Options();
  fl_value_set_string_take(extra, "unknown", fl_value_new_bool(true));
  g_autoptr(FlValue) a = PutArgs("id", 1, extra);
  EXPECT_EQ(Parse(Method::kPut, a), kErrInvalidArgs);

  g_autoptr(FlValue) b = PutArgs("id", 1, fl_value_new_map());
  EXPECT_EQ(Parse(Method::kPut, b), kErrInvalidArgs);

  g_autoptr(FlValue) c = PutArgs("id", 1, fl_value_new_null());
  EXPECT_EQ(Parse(Method::kPut, c), kErrInvalidArgs);
}

TEST(Contract, ArgumentShape) {
  g_autoptr(FlValue) not_map = fl_value_new_string("x");
  EXPECT_EQ(Parse(Method::kGet, not_map), kErrInvalidArgs);
  EXPECT_EQ(Parse(Method::kGet, nullptr), kErrInvalidArgs);

  g_autoptr(FlValue) extra = fl_value_new_map();
  fl_value_set_string_take(extra, "id", fl_value_new_string("a"));
  fl_value_set_string_take(extra, "key", fl_value_new_string("a"));
  EXPECT_EQ(Parse(Method::kGet, extra), kErrInvalidArgs);

  g_autoptr(FlValue) wrong_type = fl_value_new_map();
  fl_value_set_string_take(wrong_type, "id", fl_value_new_int(1));
  EXPECT_EQ(Parse(Method::kDelete, wrong_type), kErrInvalidArgs);

  g_autoptr(FlValue) list_args = fl_value_new_map();
  EXPECT_EQ(Parse(Method::kListIds, list_args), kErrInvalidArgs);
  EXPECT_EQ(Parse(Method::kListIds, nullptr), "OK");
}

}  // namespace test
}  // namespace pqkeystore
