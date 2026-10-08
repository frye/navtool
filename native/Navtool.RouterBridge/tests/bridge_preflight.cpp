#include "navtool_router_bridge.h"
#include <iostream>
#include <string>
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
#else
int main(int argc, char** argv) {
#endif
    if (argc < 2 || argc > 3) {
        std::cerr << "Usage: navtool_router_bridge_preflight <exact-library-path> [expected-revision]\n";
        return 2;
    }
#ifdef _WIN32
    const auto handle = LoadLibraryW(argv[1]);
    const auto symbol = [&](const char* name) { return handle ? GetProcAddress(handle, name) : nullptr; };
#else
    const auto handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    const auto symbol = [&](const char* name) { return handle ? dlsym(handle, name) : nullptr; };
#endif
    if (!handle) { std::cerr << "Routing engine unavailable: exact bridge/dependencies could not load\n"; return 1; }
    const auto abi = reinterpret_cast<uint32_t (*)()>(symbol("navtool_router_bridge_preflight_v1"));
    const auto capabilities = reinterpret_cast<uint64_t (*)()>(symbol("navtool_router_bridge_capabilities_v1"));
    const auto info = reinterpret_cast<int32_t (*)(char**, size_t*)>(symbol("navtool_router_build_info_v8"));
    const auto release = reinterpret_cast<void (*)(void*)>(symbol("navtool_router_bridge_free_v1"));
    bool valid = abi && capabilities && info && release && abi() == NAVTOOL_ROUTER_BRIDGE_ABI_VERSION &&
        (capabilities() & ((1ULL << 14) - 1)) == ((1ULL << 14) - 1) &&
        symbol("navtool_router_calculate_route_streaming_v9");
    char* json = nullptr; size_t size = 0;
    if (valid) valid = info(&json, &size) == 0 && json;
    if (valid) {
        std::string value(json, size);
        valid = value.find("\"ensemble_enabled\":false") != std::string::npos &&
            value.find("\"land_data_enabled\":true") != std::string::npos;
        if (argc == 3) {
#ifdef _WIN32
            const std::wstring argument{argv[2]};
            const std::string revision(argument.begin(), argument.end());
#else
            const std::string revision{argv[2]};
#endif
            valid = valid && value.find("\"library_revision\":\"" + revision + "\"") != std::string::npos;
        }
        if (valid) std::cout << value << '\n';
    }
    if (json && release) release(json);
#ifdef _WIN32
    FreeLibrary(handle);
#else
    dlclose(handle);
#endif
    if (!valid) std::cerr << "Routing engine unavailable: mandatory bridge ABI, capabilities, features or revision mismatch\n";
    return valid ? 0 : 1;
}
