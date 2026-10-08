// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.

#include "include/pqkeystore/pq_keystore_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "pq_keystore_plugin.h"

void PqKeystorePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  pqkeystore::PqKeystorePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
