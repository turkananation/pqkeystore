// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Windows implementation of platform channel contract v1
// (doc/PLATFORM_CONTRACT.md). Storage: DPAPI-protected files.

#ifndef FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_C_API_H_
#define FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_C_API_H_

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void PqKeystorePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_C_API_H_
