#ifndef FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
#define FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void PqKeystorePluginRegisterWithRegistrar(
    void* registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_PQ_KEYSTORE_PLUGIN_H_
