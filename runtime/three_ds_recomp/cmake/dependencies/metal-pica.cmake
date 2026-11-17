# Metal PICA shader translation dependencies.
# shaderc compiles canonical GLSL to SPIR-V; SPIRV-Cross lowers SPIR-V to MSL.
# No Vulkan loader or MoltenVK is required by this path.

include(cmake/dependencies/vulkan-compiler-dependencies.cmake)
include(FetchContent)

set(SPIRV_CROSS_STATIC ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SHARED OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_MSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_C_API OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SKIP_INSTALL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_FORCE_PIC ON CACHE BOOL "" FORCE)

FetchContent_Declare(
    spirv_cross
    GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Cross.git
    GIT_TAG 57e4efcc84112abcd426dc5ec248b5339bee04f2
)
FetchContent_MakeAvailable(spirv_cross)

if(NOT TARGET spirv-cross-msl)
    message(FATAL_ERROR "SPIRV-Cross MSL target was not created")
endif()
