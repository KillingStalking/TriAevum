# iOS uses MoltenVK as a statically linked XCFramework. Never search for a
# system Vulkan loader: iOS does not provide one.
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "ios-vulkan.cmake is only valid for an iOS target")
endif()

include(cmake/dependencies/vulkan-compiler-dependencies.cmake)

if(CMAKE_VERSION VERSION_LESS 3.28)
    message(FATAL_ERROR "iOS XCFramework selection requires CMake 3.28 or newer")
endif()

set(THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK "" CACHE PATH
    "Path to the static MoltenVK.xcframework built for iOS")
if(NOT THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK)
    message(FATAL_ERROR
        "iOS Vulkan requires -DTHREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK=/path/to/MoltenVK.xcframework. "
        "Run scripts/ios/build_moltenvk.sh on a macOS/Xcode runner first.")
endif()
if(NOT EXISTS "${THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK}/Info.plist")
    message(FATAL_ERROR
        "MoltenVK XCFramework not found: ${THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK}")
endif()
if(NOT CMAKE_GENERATOR STREQUAL "Xcode")
    message(FATAL_ERROR
        "The iOS MoltenVK XCFramework integration currently requires the Xcode CMake generator.")
endif()

find_library(THREE_DS_RECOMP_MOLTENVK_LIBRARY
    NAMES MoltenVK
    PATHS "${THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK}"
    NO_DEFAULT_PATH
    REQUIRED
)
set(Vulkan_LIBRARY "${THREE_DS_RECOMP_MOLTENVK_LIBRARY}" CACHE FILEPATH
    "Static MoltenVK library selected from the iOS XCFramework" FORCE)
set(Vulkan_INCLUDE_DIR "${android_vulkan_headers_SOURCE_DIR}/include" CACHE PATH
    "Vulkan-Headers include directory" FORCE)

message(STATUS "iOS Vulkan loader: ${Vulkan_LIBRARY}")
message(STATUS "iOS Vulkan headers: ${Vulkan_INCLUDE_DIR}")
