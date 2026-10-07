// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Linux implementation of platform channel contract v1
// (doc/PLATFORM_CONTRACT.md). Storage: Secret Service via libsecret.

#ifndef FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
#define FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

typedef struct _PqKeystorePlugin PqKeystorePlugin;
typedef struct {
  GObjectClass parent_class;
} PqKeystorePluginClass;

FLUTTER_PLUGIN_EXPORT GType pq_keystore_plugin_get_type();

FLUTTER_PLUGIN_EXPORT void pq_keystore_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
