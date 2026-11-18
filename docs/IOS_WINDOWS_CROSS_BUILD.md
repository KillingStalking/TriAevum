# Windows-hosted iOS cross-build

## Status and scope

The first Windows-hosted Metal milestone is the **PICA shader translation
and frame-foundation library**, not a runnable iOS application. It compiles
shaderc and SPIRV-Cross for the iOS device ABI, builds canonical PICA
GLSL -> SPIR-V -> MSL translation, and compiles the SDL CAMetalLayer device,
command-queue and drawable presentation primitives.

The current native PICA/NRI execution implementation is Vulkan-specific.
The existing `gfx_metal.cpp` implements the legacy Fast3D `GfxRenderingAPI`
operations; it does not implement the modern PICA render-backend contract or
the title's `TitleRenderBackend` / `PicaProgramPreparationBackend` services.
A playable Metal port still needs a native PICA backend, shader/pipeline
translation, runtime backend selection and an iOS application host/packaging
layer. The native game's pipeline-preparation helper is now only added when
the Vulkan renderer is enabled, so a future non-Vulkan backend will not inherit
an unconditional NRI/Vulkan link dependency.

## Toolchain prerequisites

- Windows 10/11 x64.
- Python 3.10+.
- CMake 3.26+ and Ninja.
- LLVM/Clang with `clang.exe`, `clang++.exe`, `ld64.lld.exe`,
  `llvm-ar.exe`, `llvm-ranlib.exe` and `llvm-nm.exe`.
- An extracted iPhoneOS SDK containing
  `System/Library/Frameworks`.
- The repository's normal CMake/FetchContent network access for pinned
  dependencies.

Set these environment variables:

```powershell
$env:LLVM_ROOT = "C:\\LLVM"
$env:IOS_SDK_ROOT = "D:\\AppleSDK\\iPhoneOS.sdk"
```

The SDK path must point to the SDK directory itself, not to the parent
`iPhoneOS.platform` directory.

Run the diagnostic:

```powershell
py win/doctor.py
```

Then build the initial smoke target:

```powershell
py win/build_ios.py --config Release --jobs 8
```

The default target is `oot3d_metal_shader_translation`. The output is a
static library in `build-ios-windows`; no `.app`, IPA, signing or device
installation is performed.

## Metal compiler tools

The current translator uses SPIRV-Cross to generate MSL source and is designed
to let the iOS Metal runtime compile that source into a Metal library. Apple
Metal Developer Tools for Windows (`metal.exe` and `metallib.exe`) are not
required for this stage. Offline precompiled `.metallib` generation remains
a separate option, subject to Apple's licence terms.

Before distributing or using any Windows-hosted Apple toolchain, independently
review the current Apple Developer / Xcode / Metal Developer Tools licence
terms for the exact SDK and tool versions. Availability of a Windows binary
does not itself grant permission for every target, use or redistribution.
This repository does not bundle Apple's SDK or Metal tools.

## Next implementation milestones

1. Compile the shaderc + SPIRV-Cross MSL translation library with the Windows
   iOS cross toolchain and validate generated source on a host test runner.
2. Add a minimal UIKit/SDL iOS app host and produce an unsigned device
   `.app`/IPA from Windows.
3. Implement the native PICA Metal resource model: guest memory transfers,
   textures, render targets, samplers, depth/stencil and command retirement.
4. Implement PICA graphics pipelines and draw/transfer/fill execution using
   the translated MSL and Metal argument buffers. Do not route the modern
   renderer through the legacy Fast3D Metal class.
5. Port renderer-neutral title passes, scene presentation and state snapshots;
   gate Vulkan/NRI-only effects by capability.
6. Validate on the target iPad, then add signing/sideloading separately.

## Troubleshooting

- `IOS_SDK_ROOT` must contain `System/Library/Frameworks`.
- `LLVM_ROOT` must contain a `bin` directory with Clang and LLD.
- CMake must be invoked with `-DCMAKE_TOOLCHAIN_FILE=...` on the first
  configure; including a toolchain file after `project()` is too late. The
  runtime's legacy iOS toolchain bootstrap is now skipped when an explicit
  toolchain file is supplied.
- iOS dependencies are configured once in `runtime/three_ds_recomp`; the
  duplicate late `ios.cmake` inclusion has been removed.
- Delete the build directory after changing SDK or compiler versions.
