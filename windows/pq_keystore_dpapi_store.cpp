// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#ifndef NOMINMAX
#define NOMINMAX
#endif
// windows.h must precede the other Win32 headers.
#include <windows.h>

#include <bcrypt.h>
#include <dpapi.h>
#include <knownfolders.h>
#include <sddl.h>
#include <shlobj.h>

#include "pq_keystore_dpapi_store.h"

#include <algorithm>
#include <cstring>
#include <cwctype>
#include <set>
#include <string>

namespace pqkeystore {
namespace {

constexpr char kMagic[4] = {'P', 'Q', 'N', 'W'};
constexpr uint8_t kFormatVersion = 1;
constexpr wchar_t kExtension[] = L".pqnw";
constexpr wchar_t kTempMarker[] = L".tmp-";
constexpr char kEntropyContext[] = "com.yardenah.pqkeystore.v1";
// DPAPI adds a few hundred bytes; allow generous headroom.
constexpr uint64_t kMaxFileBytes = kMaxRecordBytes + 64 * 1024;
constexpr size_t kMaxAppNamespace = 64;

StoreResult Error(const char* code, const std::string& message) {
  StoreResult r;
  r.kind = StoreResult::Kind::kError;
  r.error = {code, message};
  return r;
}

StoreResult Win32Error(const char* what) {
  return Error(kErrStorage, std::string(what) + " (win32 error " +
                                std::to_string(GetLastError()) + ")");
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(),
                                    static_cast<int>(s.size()), nullptr, 0);
  std::wstring w(static_cast<size_t>(n), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(),
                      static_cast<int>(s.size()), w.data(), n);
  return w;
}

bool Sha256Hex(const std::string& input, std::wstring* out) {
  BCRYPT_ALG_HANDLE alg = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  UCHAR digest[32];
  bool ok = BCRYPT_SUCCESS(BCryptOpenAlgorithmProvider(
                &alg, BCRYPT_SHA256_ALGORITHM, nullptr, 0)) &&
            BCRYPT_SUCCESS(BCryptCreateHash(alg, &hash, nullptr, 0, nullptr, 0,
                                            0)) &&
            BCRYPT_SUCCESS(BCryptHashData(
                hash,
                reinterpret_cast<PUCHAR>(const_cast<char*>(input.data())),
                static_cast<ULONG>(input.size()), 0)) &&
            BCRYPT_SUCCESS(BCryptFinishHash(hash, digest, sizeof(digest), 0));
  if (hash != nullptr) BCryptDestroyHash(hash);
  if (alg != nullptr) BCryptCloseAlgorithmProvider(alg, 0);
  if (!ok) return false;
  static const wchar_t kHex[] = L"0123456789abcdef";
  out->clear();
  for (UCHAR b : digest) {
    out->push_back(kHex[b >> 4]);
    out->push_back(kHex[b & 0xF]);
  }
  return true;
}

// Executable stem restricted to [A-Za-z0-9._-]. Namespacing only: DPAPI user
// scope does not isolate applications running as the same user.
std::string AppNamespace() {
  wchar_t buffer[MAX_PATH * 4];
  const DWORD n = GetModuleFileNameW(nullptr, buffer, ARRAYSIZE(buffer));
  std::wstring path(buffer, n);
  const size_t slash = path.find_last_of(L"\\/");
  std::wstring stem = slash == std::wstring::npos ? path : path.substr(slash + 1);
  const size_t dot = stem.find_last_of(L'.');
  if (dot != std::wstring::npos) stem.resize(dot);
  std::string out;
  for (wchar_t c : stem) {
    const bool safe = (c >= L'a' && c <= L'z') || (c >= L'A' && c <= L'Z') ||
                      (c >= L'0' && c <= L'9') || c == L'.' || c == L'_' ||
                      c == L'-';
    out.push_back(safe ? static_cast<char>(c) : '_');
    if (out.size() == kMaxAppNamespace) break;
  }
  // Avoid names Windows treats specially ("." / "..").
  if (out.empty() || out.find_first_not_of('.') == std::string::npos) {
    out = "unknown";
  }
  return out;
}

std::wstring CurrentUserSddl() {
  HANDLE token = nullptr;
  std::wstring sddl;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return sddl;
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> buffer(size);
  if (size > 0 &&
      GetTokenInformation(token, TokenUser, buffer.data(), size, &size)) {
    LPWSTR sid = nullptr;
    if (ConvertSidToStringSidW(
            reinterpret_cast<TOKEN_USER*>(buffer.data())->User.Sid, &sid)) {
      // Protected DACL: current user + SYSTEM, inherited by children.
      sddl = L"D:P(A;OICI;FA;;;" + std::wstring(sid) + L")(A;OICI;FA;;;SY)";
      LocalFree(sid);
    }
  }
  CloseHandle(token);
  return sddl;
}

bool EnsureDirectory(const std::wstring& path, const std::wstring& sddl) {
  const DWORD attrs = GetFileAttributesW(path.c_str());
  if (attrs != INVALID_FILE_ATTRIBUTES) {
    return (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0 &&
           (attrs & FILE_ATTRIBUTE_REPARSE_POINT) == 0;
  }
  PSECURITY_DESCRIPTOR sd = nullptr;
  if (sddl.empty() || !ConvertStringSecurityDescriptorToSecurityDescriptorW(
                          sddl.c_str(), SDDL_REVISION_1, &sd, nullptr)) {
    return false;
  }
  SECURITY_ATTRIBUTES sa{sizeof(sa), sd, FALSE};
  const BOOL created = CreateDirectoryW(path.c_str(), &sa);
  const DWORD err = GetLastError();
  LocalFree(sd);
  return created || err == ERROR_ALREADY_EXISTS;
}

enum class ReadStatus { kOk, kMissing, kForeign, kIoError };

struct Entry {
  std::string id;
  std::vector<uint8_t> blob;
};

bool ParseEntry(const std::vector<uint8_t>& bytes, Entry* out) {
  size_t off = 0;
  auto need = [&](size_t n) { return bytes.size() - off >= n; };
  if (!need(4 + 1 + 2) || memcmp(bytes.data(), kMagic, 4) != 0 ||
      bytes[4] != kFormatVersion) {
    return false;
  }
  off = 5;
  const size_t id_len = (static_cast<size_t>(bytes[off]) << 8) | bytes[off + 1];
  off += 2;
  if (id_len == 0 || id_len > kMaxIdUtf8Bytes || !need(id_len + 4)) {
    return false;
  }
  out->id.assign(reinterpret_cast<const char*>(bytes.data() + off), id_len);
  off += id_len;
  const size_t blob_len = (static_cast<size_t>(bytes[off]) << 24) |
                          (static_cast<size_t>(bytes[off + 1]) << 16) |
                          (static_cast<size_t>(bytes[off + 2]) << 8) |
                          bytes[off + 3];
  off += 4;
  // Strict: no trailing bytes.
  if (blob_len == 0 || bytes.size() - off != blob_len || !IsValidId(out->id)) {
    return false;
  }
  out->blob.assign(bytes.begin() + off, bytes.end());
  return true;
}

ReadStatus ReadFileBytes(const std::wstring& path, std::vector<uint8_t>* out) {
  // FILE_SHARE_DELETE lets a concurrent replace/delete proceed.
  HANDLE file = CreateFileW(
      path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    const DWORD err = GetLastError();
    return err == ERROR_FILE_NOT_FOUND || err == ERROR_PATH_NOT_FOUND
               ? ReadStatus::kMissing
               : ReadStatus::kIoError;
  }
  LARGE_INTEGER size{};
  ReadStatus status = ReadStatus::kOk;
  if (!GetFileSizeEx(file, &size)) {
    status = ReadStatus::kIoError;
  } else if (size.QuadPart <= 0 ||
             static_cast<uint64_t>(size.QuadPart) > kMaxFileBytes) {
    status = ReadStatus::kForeign;
  } else {
    out->resize(static_cast<size_t>(size.QuadPart));
    size_t done = 0;
    while (done < out->size()) {
      DWORD got = 0;
      if (!ReadFile(file, out->data() + done,
                    static_cast<DWORD>(out->size() - done), &got, nullptr) ||
          got == 0) {
        status = ReadStatus::kIoError;
        break;
      }
      done += got;
    }
  }
  CloseHandle(file);
  return status;
}

ReadStatus ReadEntry(const std::wstring& path, const std::string& id,
                     Entry* entry) {
  if (path.empty()) {
    SetLastError(ERROR_INVALID_FUNCTION);  // Hashing failed.
    return ReadStatus::kIoError;
  }
  std::vector<uint8_t> bytes;
  const ReadStatus status = ReadFileBytes(path, &bytes);
  if (status != ReadStatus::kOk) return status;
  if (!ParseEntry(bytes, entry) || entry->id != id) return ReadStatus::kForeign;
  return ReadStatus::kOk;
}

// Retries transient sharing violations (e.g. antivirus scanners).
template <typename F>
bool WithRetry(F op) {
  for (int attempt = 0; attempt < 5; attempt++) {
    if (op()) return true;
    const DWORD err = GetLastError();
    if (err != ERROR_SHARING_VIOLATION && err != ERROR_ACCESS_DENIED &&
        err != ERROR_LOCK_VIOLATION) {
      return false;
    }
    Sleep(10 * (attempt + 1));
  }
  return false;
}

void Put32(std::vector<uint8_t>* out, uint32_t v) {
  out->push_back(static_cast<uint8_t>(v >> 24));
  out->push_back(static_cast<uint8_t>(v >> 16));
  out->push_back(static_cast<uint8_t>(v >> 8));
  out->push_back(static_cast<uint8_t>(v));
}

}  // namespace

DpapiStore::DpapiStore() : app_(AppNamespace()) {}

bool DpapiStore::EnsureRoot(ContractError* error) {
  if (root_ready_) return true;
  PWSTR local = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, KF_FLAG_DEFAULT,
                                  nullptr, &local))) {
    error->code = kErrUnavailable;
    error->message = "LocalAppData folder unavailable";
    return false;
  }
  // Extended-length prefix lifts the MAX_PATH limit.
  std::wstring path = L"\\\\?\\" + std::wstring(local);
  CoTaskMemFree(local);
  const std::wstring sddl = CurrentUserSddl();
  for (const std::wstring& part :
       {std::wstring(L"yardenah"), std::wstring(L"pqkeystore"),
        Utf8ToWide(app_), std::wstring(L"v1")}) {
    path += L"\\" + part;
    if (!EnsureDirectory(path, sddl)) {
      error->code = kErrStorage;
      error->message = "cannot create storage directory (win32 error " +
                       std::to_string(GetLastError()) + ")";
      return false;
    }
  }
  root_ = path;
  root_ready_ = true;
  RemoveStaleTempFiles();
  return true;
}

void DpapiStore::RemoveStaleTempFiles() {
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW((root_ + L"\\*" + kTempMarker + L"*").c_str(),
                               &data);
  if (find == INVALID_HANDLE_VALUE) return;
  FILETIME now_ft;
  GetSystemTimeAsFileTime(&now_ft);
  ULARGE_INTEGER now;
  now.LowPart = now_ft.dwLowDateTime;
  now.HighPart = now_ft.dwHighDateTime;
  constexpr ULONGLONG kTenMinutes = 10ULL * 60 * 10000000;  // 100ns units.
  do {
    ULARGE_INTEGER written;
    written.LowPart = data.ftLastWriteTime.dwLowDateTime;
    written.HighPart = data.ftLastWriteTime.dwHighDateTime;
    if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0 &&
        now.QuadPart - written.QuadPart > kTenMinutes) {
      DeleteFileW((root_ + L"\\" + data.cFileName).c_str());
    }
  } while (FindNextFileW(find, &data));
  FindClose(find);
}

std::wstring DpapiStore::PathFor(const std::string& id) const {
  std::wstring hex;
  if (!Sha256Hex(id, &hex)) return std::wstring();
  return root_ + L"\\" + hex + kExtension;
}

std::vector<uint8_t> DpapiStore::Entropy(const std::string& id) const {
  // context \0 app \0 id — binds every blob to its app namespace and ID.
  // "com.yardenah.pqkeystore.v1" \0 app \0 id — binds every blob to its
  // app namespace and ID.
  std::vector<uint8_t> e(
      kEntropyContext, kEntropyContext + sizeof(kEntropyContext) - 1);
  e.push_back(0);
  e.insert(e.end(), app_.begin(), app_.end());
  e.push_back(0);
  e.insert(e.end(), id.begin(), id.end());
  return e;
}

StoreResult DpapiStore::Put(const std::string& id,
                            const std::vector<uint8_t>& data) {
  ContractError root_error;
  if (!EnsureRoot(&root_error)) {
    return Error(root_error.code.c_str(), root_error.message);
  }
  const std::wstring path = PathFor(id);
  if (path.empty()) return Error(kErrStorage, "hashing failed");

  std::vector<uint8_t> entropy = Entropy(id);
  DATA_BLOB in{static_cast<DWORD>(data.size()),
               const_cast<BYTE*>(data.data())};
  DATA_BLOB ent{static_cast<DWORD>(entropy.size()), entropy.data()};
  DATA_BLOB out{};
  if (!CryptProtectData(&in, L"pqkeystore", &ent, nullptr, nullptr,
                        CRYPTPROTECT_UI_FORBIDDEN, &out)) {
    return Win32Error("CryptProtectData failed");
  }

  std::vector<uint8_t> body(kMagic, kMagic + 4);
  body.push_back(kFormatVersion);
  body.push_back(static_cast<uint8_t>(id.size() >> 8));
  body.push_back(static_cast<uint8_t>(id.size()));
  body.insert(body.end(), id.begin(), id.end());
  Put32(&body, out.cbData);
  body.insert(body.end(), out.pbData, out.pbData + out.cbData);
  LocalFree(out.pbData);

  const std::wstring temp = path + kTempMarker +
                            std::to_wstring(GetCurrentProcessId()) + L"-" +
                            std::to_wstring(++temp_counter_);
  HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return Win32Error("cannot create file");
  size_t done = 0;
  bool ok = true;
  while (ok && done < body.size()) {
    DWORD wrote = 0;
    ok = WriteFile(file, body.data() + done,
                   static_cast<DWORD>(body.size() - done), &wrote, nullptr) &&
         wrote > 0;
    done += wrote;
  }
  ok = ok && FlushFileBuffers(file);
  CloseHandle(file);
  if (!ok) {
    StoreResult err = Win32Error("cannot write file");
    DeleteFileW(temp.c_str());
    return err;
  }
  // Atomic replace: the previous entry survives any failure before this.
  if (!WithRetry([&] {
        return MoveFileExW(temp.c_str(), path.c_str(),
                           MOVEFILE_REPLACE_EXISTING |
                               MOVEFILE_WRITE_THROUGH) != 0;
      })) {
    StoreResult err = Win32Error("cannot commit file");
    DeleteFileW(temp.c_str());
    return err;
  }
  return StoreResult();
}

StoreResult DpapiStore::Get(const std::string& id) {
  ContractError root_error;
  if (!EnsureRoot(&root_error)) {
    return Error(root_error.code.c_str(), root_error.message);
  }
  Entry entry;
  switch (ReadEntry(PathFor(id), id, &entry)) {
    case ReadStatus::kMissing:
    case ReadStatus::kForeign:
      return StoreResult();  // null
    case ReadStatus::kIoError:
      return Win32Error("cannot read file");
    case ReadStatus::kOk:
      break;
  }
  std::vector<uint8_t> entropy = Entropy(id);
  DATA_BLOB in{static_cast<DWORD>(entry.blob.size()), entry.blob.data()};
  DATA_BLOB ent{static_cast<DWORD>(entropy.size()), entropy.data()};
  DATA_BLOB out{};
  if (!CryptUnprotectData(&in, nullptr, &ent, nullptr, nullptr,
                          CRYPTPROTECT_UI_FORBIDDEN, &out)) {
    return Error(kErrCorrupt, "stored entry cannot be unprotected (win32 "
                              "error " + std::to_string(GetLastError()) + ")");
  }
  StoreResult r;
  if (out.cbData == 0 || out.cbData > kMaxRecordBytes) {
    r = Error(kErrCorrupt, "stored entry has an invalid size");
  } else {
    r.kind = StoreResult::Kind::kBytes;
    r.bytes.assign(out.pbData, out.pbData + out.cbData);
  }
  SecureZeroMemory(out.pbData, out.cbData);
  LocalFree(out.pbData);
  return r;
}

StoreResult DpapiStore::Delete(const std::string& id) {
  ContractError root_error;
  if (!EnsureRoot(&root_error)) {
    return Error(root_error.code.c_str(), root_error.message);
  }
  const std::wstring path = PathFor(id);
  Entry entry;
  const ReadStatus status = ReadEntry(path, id, &entry);
  if (status == ReadStatus::kMissing) {
    StoreResult r;
    r.kind = StoreResult::Kind::kBool;
    return r;
  }
  if (status == ReadStatus::kIoError) return Win32Error("cannot read file");
  // Unparseable files at this path are removed but were not valid entries.
  if (!WithRetry([&] { return DeleteFileW(path.c_str()) != 0; }) &&
      GetLastError() != ERROR_FILE_NOT_FOUND) {
    return Win32Error("cannot delete file");
  }
  StoreResult r;
  r.kind = StoreResult::Kind::kBool;
  r.boolean = status == ReadStatus::kOk;
  return r;
}

StoreResult DpapiStore::Contains(const std::string& id) {
  ContractError root_error;
  if (!EnsureRoot(&root_error)) {
    return Error(root_error.code.c_str(), root_error.message);
  }
  Entry entry;
  const ReadStatus status = ReadEntry(PathFor(id), id, &entry);
  if (status == ReadStatus::kIoError) return Win32Error("cannot read file");
  StoreResult r;
  r.kind = StoreResult::Kind::kBool;
  r.boolean = status == ReadStatus::kOk;
  return r;
}

StoreResult DpapiStore::ListIds() {
  ContractError root_error;
  if (!EnsureRoot(&root_error)) {
    return Error(root_error.code.c_str(), root_error.message);
  }
  StoreResult r;
  r.kind = StoreResult::Kind::kStrings;
  WIN32_FIND_DATAW data;
  HANDLE find = FindFirstFileW((root_ + L"\\*" + kExtension).c_str(), &data);
  if (find == INVALID_HANDLE_VALUE) {
    return GetLastError() == ERROR_FILE_NOT_FOUND
               ? r
               : Win32Error("cannot enumerate storage");
  }
  const std::wstring ext(kExtension);
  std::set<std::string> seen;
  do {
    std::wstring name(data.cFileName);
    if ((data.dwFileAttributes &
         (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) != 0 ||
        name.size() != 64 + ext.size() ||
        name.compare(64, ext.size(), ext) != 0) {
      continue;
    }
    std::vector<uint8_t> bytes;
    Entry entry;
    if (ReadFileBytes(root_ + L"\\" + name, &bytes) != ReadStatus::kOk ||
        !ParseEntry(bytes, &entry)) {
      continue;
    }
    std::wstring expected;
    if (!Sha256Hex(entry.id, &expected)) continue;
    std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) {
      return static_cast<wchar_t>(std::towlower(c));
    });
    if (name == expected + ext && seen.insert(entry.id).second) {
      r.strings.push_back(entry.id);
    }
  } while (FindNextFileW(find, &data));
  FindClose(find);
  return r;
}

}  // namespace pqkeystore
