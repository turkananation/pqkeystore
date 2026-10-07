//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <pqkeystore/pq_keystore_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) pqkeystore_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PqKeystorePlugin");
  pq_keystore_plugin_register_with_registrar(pqkeystore_registrar);
}
