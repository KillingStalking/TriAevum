# Cross-compile iOS targets from Windows with upstream LLVM/LLD and an iPhoneOS SDK.
#
# Required environment:
#   IOS_SDK_ROOT  - root of an extracted iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk
#   LLVM_ROOT     - LLVM installation root (bin/clang.exe, bin/clang++.exe, bin/ld64.lld.exe)
#
# This file deliberately does not select or enable a renderer.  The current
# PICA/NRI execution path is Vulkan-only; selecting Metal requires a separate
# native PICA Metal implementation.

if(NOT WIN32)
    message(FATAL_ERROR "ios-windows.cmake is intended for a Windows build host")
endif()

if(NOT DEFINED ENV{IOS_SDK_ROOT} OR "$ENV{IOS_SDK_ROOT}" STREQUAL "")
    message(FATAL_ERROR "Set IOS_SDK_ROOT to the extracted iPhoneOS SDK directory")
endif()
if(NOT DEFINED ENV{LLVM_ROOT} OR "$ENV{LLVM_ROOT}" STREQUAL "")
    message(FATAL_ERROR "Set LLVM_ROOT to the LLVM installation directory")
endif()

file(TO_CMAKE_PATH "$ENV{IOS_SDK_ROOT}" _ios_sdk)
file(TO_CMAKE_PATH "$ENV{LLVM_ROOT}" _llvm_root)
set(_llvm_bin "${_llvm_root}/bin")

if(NOT EXISTS "${_ios_sdk}/System/Library/Frameworks")
    message(FATAL_ERROR "IOS_SDK_ROOT does not look like an iPhoneOS SDK: ${_ios_sdk}")
endif()
if(NOT EXISTS "${_llvm_bin}/clang.exe" OR NOT EXISTS "${_llvm_bin}/clang++.exe")
    message(FATAL_ERROR "LLVM_ROOT must contain bin/clang.exe and bin/clang++.exe")
endif()

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_C_COMPILER "${_llvm_bin}/clang.exe" CACHE FILEPATH "" FORCE)
set(CMAKE_CXX_COMPILER "${_llvm_bin}/clang++.exe" CACHE FILEPATH "" FORCE)
set(CMAKE_OBJC_COMPILER "${_llvm_bin}/clang.exe" CACHE FILEPATH "" FORCE)
set(CMAKE_OBJCXX_COMPILER "${_llvm_bin}/clang++.exe" CACHE FILEPATH "" FORCE)

set(CMAKE_C_COMPILER_TARGET arm64-apple-ios15.0)
set(CMAKE_CXX_COMPILER_TARGET arm64-apple-ios15.0)
set(CMAKE_OBJC_COMPILER_TARGET arm64-apple-ios15.0)
set(CMAKE_OBJCXX_COMPILER_TARGET arm64-apple-ios15.0)

set(CMAKE_SYSROOT "${_ios_sdk}" CACHE PATH "iPhoneOS SDK" FORCE)
set(CMAKE_OSX_SYSROOT "${_ios_sdk}" CACHE PATH "iPhoneOS SDK" FORCE)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "iOS device architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum iOS version" FORCE)

# LLD is selected through Clang's driver so CMake's compiler checks and final
# links use the same linker. CMAKE_LINKER is also exposed for projects that
# invoke the linker directly.
if(EXISTS "${_llvm_bin}/ld64.lld.exe")
    set(CMAKE_LINKER "${_llvm_bin}/ld64.lld.exe" CACHE FILEPATH "" FORCE)
elseif(EXISTS "${_llvm_bin}/ld64.lld")
    set(CMAKE_LINKER "${_llvm_bin}/ld64.lld" CACHE FILEPATH "" FORCE)
else()
    message(FATAL_ERROR "LLVM_ROOT/bin/ld64.lld[.exe] was not found")
endif()

# Use LLVM's archive tools explicitly: Windows PATH commonly has no Unix
# ar/ranlib, while this cross build must produce Mach-O-compatible archives.
foreach(_tool IN ITEMS llvm-ar llvm-ranlib llvm-nm)
    if(EXISTS "${_llvm_bin}/${_tool}.exe")
        set(_tool_path "${_llvm_bin}/${_tool}.exe")
    elseif(EXISTS "${_llvm_bin}/${_tool}")
        set(_tool_path "${_llvm_bin}/${_tool}")
    else()
        message(FATAL_ERROR "LLVM_ROOT/bin/${_tool}[.exe] was not found")
    endif()
    if(_tool STREQUAL "llvm-ar")
        set(CMAKE_AR "${_tool_path}" CACHE FILEPATH "" FORCE)
    elseif(_tool STREQUAL "llvm-ranlib")
        set(CMAKE_RANLIB "${_tool_path}" CACHE FILEPATH "" FORCE)
    else()
        set(CMAKE_NM "${_tool_path}" CACHE FILEPATH "" FORCE)
    endif()
endforeach()

set(_ios_target_flags "-B\"${_llvm_bin}\" -fuse-ld=lld -isysroot \"${_ios_sdk}\"")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_ios_target_flags}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_ios_target_flags}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_ios_target_flags}")

set(CMAKE_FIND_ROOT_PATH "${_ios_sdk}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Prefer static third-party libraries for iOS" FORCE)
message(STATUS "Windows-hosted iOS cross compile: arm64, SDK=${_ios_sdk}, deployment=15.0")
