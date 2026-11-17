# iOS Port Audit — TriAevum

Status: initial source audit, not a successful iOS build.

Target: iPadOS on Apple Silicon. The existing renderer is the native OOT3D Vulkan renderer with NRI interop; the preferred first experiment is to preserve that renderer and use MoltenVK, rather than begin a second PICA renderer.

## Repository baseline

- Repository: `KillingStalking/TriAevum`
- Base branch: `main`
- Base commit at audit time: `672d13f15cb336bc7651c861d23cf45924a9f936`
- Working branch: `feature/ios-moltenvk-port`
- The fork's `main` currently points at the same commit as upstream `coccofresco/TriAevum`.

## What already exists

1. `runtime/three_ds_recomp/cmake/ios-toolchain-populate.cmake` fetches and includes the `ios-cmake` toolchain.
2. `runtime/three_ds_recomp/cmake/dependencies/ios.cmake` already defines SDL2, JSON, tinyxml2, spdlog, libzip, Metal-cpp, and the ImGui Metal backend.
3. `runtime/three_ds_recomp/src/fast/CMakeLists.txt` includes Vulkan renderer and NRI/PICA execution sources when `THREE_DS_RECOMP_ENABLE_VULKAN` is enabled.
4. The Vulkan renderer creates its surface through `SDL_Vulkan_CreateSurface` on non-Windows platforms, and its instance/device creation already contains Apple portability-enumeration and portability-subset handling.
5. The pinned SDL2 `release-2.32.10` source contains a UIKit Vulkan implementation. It creates a Metal-backed surface using `VK_EXT_metal_surface` (preferred) or the legacy `VK_MVK_ios_surface` path, so the SDL surface layer is a plausible route for iOS; it still needs an on-device presentation test.
6. The pinned NRI revision (`4b485316463969f182db15e67aad2aec2f40a3d7`) does not reject `APPLE` and its CMake builds `NRI_VK` when `NRI_ENABLE_VK_SUPPORT` is enabled. Its Apple Vulkan target compiles with `VK_USE_PLATFORM_METAL_EXT`. This is strong evidence that the pinned NRI code can be attempted on iOS, but its README does not explicitly list iOS as a supported platform and no iOS build has been run.
7. `Fast3dWindow` exposes the OOT3D Vulkan backend only after native-host opt-in. Its current constructor still advertises desktop OpenGL and, on Apple, the legacy Metal backend.
8. A macOS runtime target exists at `ports/macos/runtime/CMakeLists.txt`. It enables Vulkan and NRI, while disabling desktop-only upscaler integrations. The macOS packaging documentation describes a bundled Vulkan loader and MoltenVK ICD.

## Blocking gaps for iOS

- There is no `ports/ios/` application/runtime target or UIKit host in the current tree.
- The existing `ios.cmake` dependency file is not selected by the platform dependency dispatch. The Vulkan path instead includes `android-vulkan.cmake` for all `APPLE` builds; that file downloads Vulkan-Headers/shaderc sources but then calls `find_library(Vulkan_LIBRARY NAMES vulkan vulkan-1 REQUIRED)`. This does not provision an iOS-compatible Vulkan loader or MoltenVK framework/XCFramework.
- The current macOS packaging flow bundles a dynamic Vulkan loader and MoltenVK dylib. iOS needs a separate static/framework/XCFramework link and app-bundle strategy; copying the macOS dylibs is not valid.
- The current Vulkan surface path is generic SDL. iOS must be validated against the SDL UIKit video driver and the MoltenVK Metal surface implementation, including view/layer lifetime and foreground/background transitions.
- The current runtime's window/input model is desktop-oriented (mouse, keyboard, resizable window, fullscreen modes). An iPad host needs a touch-first input and lifecycle adapter; simply compiling the desktop host is not sufficient.
- NRI is pinned by the project and its pinned CMake does build the Vulkan backend under `APPLE`, using `VK_USE_PLATFORM_METAL_EXT`. However, iOS is not explicitly named in that revision's supported-platform list. The correct next gate is a standalone compile of the exact pinned NRI target with an iPhoneOS SDK, followed by runtime initialization; do not infer full support from the CMake branch alone.

## PR #16 relationship

PR #16 is a useful implementation reference for macOS MoltenVK packaging and portability handling, but it is not an iOS port. Its branch is based on a much older common ancestor than the current `main`; transplanting the entire branch would risk reverting or conflicting with substantial upstream changes. Port individual reviewed ideas only.

## Work sequence

1. Provision the iOS Vulkan link inputs (Vulkan-Headers, loader entry points, and the official MoltenVK iOS binary/framework) with pinned versions and license notices.
2. Establish a minimal iOS Vulkan probe: SDL UIKit window/view, MoltenVK instance, physical-device enumeration, iOS Metal surface, swapchain, one clear/present loop.
3. Build and validate the pinned NRI revision for iOS independently. Record exact supported backend flags and required shader toolchain.
4. Add a dedicated `ports/ios/runtime` CMake target that reuses the existing title/runtime targets and applies an explicit iOS feature policy.
5. Add an iOS host for app lifecycle, touch/controller input, document/ROM selection, save paths, audio session, and safe renderer pause/resume.
6. Integrate shader and pipeline preparation only after runtime rendering is proven.
7. Package an IPA through macOS CI; test on the target iPad.

## Validation policy

No iOS build, device launch, swapchain presentation, NRI initialization, or game boot is claimed by this audit. Each is a separate acceptance gate. The first code milestone should be the minimal Vulkan presentation probe, not a full game build.


## MoltenVK dependency implementation

The iOS Vulkan dependency is now isolated from the Android/macOS loader path:

- `vulkan-compiler-dependencies.cmake` owns the pinned Vulkan-Headers, SPIR-V and shaderc build inputs.
- `android-vulkan.cmake` reuses those compiler dependencies and locates the Android/desktop Vulkan loader as before.
- `ios-vulkan.cmake` requires an explicitly supplied static `MoltenVK.xcframework`; it does not search for a system Vulkan loader.
- `scripts/ios/build_moltenvk.sh` checks out MoltenVK at commit `5189f8de86ec365860f63bf1da736815cfaea5cd`, builds its iOS dependencies, and runs the official `make ios` packaging target.
- `.github/workflows/ios-moltenvk-dependency.yml` runs that build on a macOS runner and publishes the XCFramework as a 14-day workflow artifact.

Local macOS command:

```sh
bash scripts/ios/build_moltenvk.sh
```

The script prints the exact `THREE_DS_RECOMP_MOLTENVK_XCFRAMEWORK` path to pass to the iOS CMake configure step. This dependency-only workflow is not a TriAevum iOS app build and does not claim that the renderer or game launches yet.
