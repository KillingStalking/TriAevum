# Native Apple-hosted iOS cross toolchain, used for CI validation.
# Windows developers should use ios-windows.cmake instead.

if(NOT CMAKE_HOST_APPLE)
    message(FATAL_ERROR "ios-apple.cmake requires a macOS host with Xcode")
endif()

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR arm64)
set(CMAKE_OSX_SYSROOT iphoneos CACHE STRING "iPhoneOS SDK" FORCE)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS device architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum iOS version" FORCE)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

# Unsigned device builds are sufficient for a static-library compile check.
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO)
