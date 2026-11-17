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
5. `Fast3dWindow` exposes the OOT3D Vulkan backend only after native-host opt-in. Its current constructor still advertises desktop OpenGL and, on Apple, the legacy Metal backend.
6. A macOS runtime target exists at `ports/macos/runtime/CMakeLists.txt`. It enables Vulkan and NRI, while disabling desktop-only upscaler integrations. The macOS packaging documentation describes a bundled Vulkan loader and MoltenVK ICD.

## Blocking gaps for iOS

- There is no `ports/ios/` application/runtime target or UIKit host in the current tree.
- The existing `ios.cmake` dependency file does not add Vulkan-Headers, a Vulkan loader, or MoltenVK. The current Vulkan dependency path reuses `android-vulkan.cmake`, which locates a system Vulkan library; that is not an iOS packaging strategy.
- The iOS dependency file is not selected by the platform dependency dispatch in `runtime/three_ds_recomp/CMakeLists.txt`; it must be wired deliberately.
- The current Vulkan surface path is generic SDL. iOS must be validated against the SDL UIKit video driver and the MoltenVK Metal surface implementation, including view/layer lifetime and foreground/background transitions.
- The current runtime's window/input model is desktop-oriented (mouse, keyboard, resizable window, fullscreen modes). An iPad host needs a touch-first input and lifecycle adapter; simply compiling the desktop host is not sufficient.
- NRI is pinned by the project and configured for Vulkan in the desktop/macOS path. Its exact support policy for the pinned revision and iOS must be verified before treating NRI as available on iOS. If the pinned NRI revision excludes Vulkan on iOS, the current NRI interop layer will need a narrow platform decision: either a supported Vulkan build configuration or a separate renderer backend. Do not silently disable NRI and claim renderer parity.

## PR #16 relationship

PR #16 is a useful implementation reference for macOS MoltenVK packaging and portability handling, but it is not an iOS port. Its branch is based on a much older common ancestor than the current `main`; transplanting the entire branch would risk reverting or conflicting with substantial upstream changes. Port individual reviewed ideas only.

## Work sequence

1. Establish a minimal iOS Vulkan probe: SDL UIKit window/view, MoltenVK instance, physical-device enumeration, iOS Metal surface, swapchain, one clear/present loop.
2. Build and validate the pinned NRI revision for iOS independently. Record exact supported backend flags and required shader toolchain.
3. Add a dedicated `ports/ios/runtime` CMake target that reuses the existing title/runtime targets and applies an explicit iOS feature policy.
4. Add an iOS host for app lifecycle, touch/controller input, document/ROM selection, save paths, audio session, and safe renderer pause/resume.
5. Integrate shader and pipeline preparation only after runtime rendering is proven.
6. Package an IPA through macOS CI; test on the target iPad.

## Validation policy

No iOS build, device launch, swapchain presentation, NRI initialization, or game boot is claimed by this audit. Each is a separate acceptance gate. The first code milestone should be the minimal Vulkan presentation probe, not a full game build.
