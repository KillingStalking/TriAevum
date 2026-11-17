# Cross-built compiler libraries, never host SDK binaries. Versions below come
# from shaderc v2026.2's DEPS; test-only dependencies are intentionally omitted.
include(cmake/dependencies/vulkan-compiler-dependencies.cmake)

# MinGW links the Windows loader through an import library named vulkan-1.
find_library(Vulkan_LIBRARY NAMES vulkan vulkan-1 REQUIRED)
