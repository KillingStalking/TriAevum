# Native PICA renderer on Metal: implementation boundary

## Current state

The iOS dependency file already fetches SDL2, Metal-cpp and the Dear ImGui
Metal backend. The legacy Fast3D renderer also has gfx_metal.cpp and
GfxRenderingAPIMetal. These facts do not mean the current OoT3D native
renderer can run on Metal.

The current native renderer is GfxRenderingAPIVulkan. It implements three
contracts:

- GfxRenderingAPI (the legacy graphics API plus the common PICA transport);
- Extension::TitleRenderBackend (OoT3D presentation and scene-view hooks);
- Renderer3ds::PicaProgramPreparationBackend (startup shader/program work).

GfxRenderingAPI itself inherits Renderer3ds::PicaRenderBackend. The old
GfxRenderingAPIMetal does not implement the modern PICA submission contract
and is not a substitute for GfxRenderingAPIVulkan.

## Implemented first primitive: shader translation

The branch now has an opt-in iOS-only `THREE_DS_RECOMP_ENABLE_METAL_PICA`
build option and a separate `oot3d_metal_shader_translation` library. Its
`TranslatePicaGlslToMsl` entry point compiles canonical GLSL with shaderc,
normalizes the fragment sampler declarations to the existing PICA descriptor
contract, validates reflected resource kinds/stages/bindings, and uses a
pinned SPIRV-Cross MSL compiler to generate iOS MSL 2.3 with tier-2 Metal
argument buffers. The returned shader artifact includes the MSL entry-point name and validated
descriptor metadata. The same target now contains `GfxMetalPicaDevice`, an
Objective-C++ owner for the SDL-provided `CAMetalLayer`'s Metal device and a
dedicated command queue, including a queue-idle fence for orderly shutdown.
`GfxMetalPicaFrame` now acquires a drawable and command buffer, creates the
initial clear pass, and presents/commits the frame. It can end that initial
drawable encoder, keep the same command buffer alive while offscreen PICA
render targets are encoded, then reopen the drawable for the final composition
pass. This establishes the ordered command-buffer lifecycle needed to render
native PICA targets before presenting them. The Windows
iOS build driver enables this option and builds that library by default.

These are foundation components only. The device/frame wrappers are not yet
wired into the game window lifecycle. `GfxMetalPicaDrawResources` now composes
the per-stage argument buffers, canonical uniform uploads, cached native
texture/sampler pairs, and packed vertex/index streams for one draw. It checks
shader-stage ownership and rejects descriptor kinds that the current Metal
resource path cannot satisfy. Its caller must still bind the matching pipeline
and active render pass before encoding the draw. `GfxMetalPicaDrawEncoder`
now performs that sequence for one ordered draw: begin the offscreen target,
bind pipeline and prepared resources, apply the validated framebuffer-pixel
viewport, encode the vertex/index draw, then end the pass. It maps PICA scissor
mode 3 to an inclusive rectangle and mode 1 to up to four disjoint rectangles
using the shared renderer-neutral exclusion helper; the partition keeps blend
and stencil effects from executing more than once per retained fragment. Mode
0 covers the full target. It verifies framebuffer extent, color/depth/stencil
formats and sample count against the pipeline before recording commands.
The concrete `GfxMetalPicaBackend` now implements the renderer-neutral PICA contract for draw, target clear and memory-fill submissions using a host-provided command buffer from the backend's own Metal command queue (the host can acquire a drawable through `GfxMetalPicaFrame` using `GfxMetalPicaBackend::Device()`); the host still owns drawable acquisition, display transfer and presentation. The new `GfxMetalPicaDrawExecutor` now provides the complete single-draw orchestration boundary: translate both canonical GLSL stages to validated MSL artifacts, compile both Metal functions, prepare uniforms/textures/vertex streams, create a pipeline from the prepared vertex descriptor, resolve the compatible cached framebuffer, and encode the ordered draw. It provides a validated native-target format policy (RGBA8 color, Depth32Float depth, and Depth32Float_Stencil8 for native depth format 3) plus an explicit-format overload for platform capability selection. The combined stencil attachment remains allocated for format 3 even on draws that do not enable stencil testing, preserving one target identity across draws. The executor retains translated MSL artifacts and compiled Metal functions in a per-device LRU cache capped at 128 shader stages, avoiding repeated shader compilation for unchanged source. It also caches render pipeline/depth-stencil states by canonical pipeline, vertex/fragment program, raster-state, exact vertex binding/attribute layout, blend/depth/stencil state, device and attachment-format identity, capped at 256 entries; draws without canonical identities use a transient pipeline rather than risking a false cache hit. The executor is not yet selected by the title runtime, and native display transfer, composition, snapshot/restore and GPU texture-copy producer resolution remain outstanding before real-time gameplay. `GfxMetalPicaRenderTarget`
now allocates offscreen color and optional combined depth/stencil textures,
creates render encoders on a caller-owned command buffer, and supports clear or
load/store attachment actions with caller-supplied clear values. The target
cache can clear every cached variant for a guest color attachment and queues
native PICA memory fills until a matching target is available; fill coverage is
checked against guest physical byte ranges, and color/depth/stencil values are
decoded by the renderer-neutral `pica_memory_fill_decode.h` shared with
Vulkan. `GfxMetalPicaBackend` routes the public
`PicaRenderBackend::ClearPicaRenderTarget` and `SubmitPicaMemoryFill` entry
points into these ordered operations. Display transfer still returns an
explicit unsupported error rather than presenting stale or incomplete output.
The first implementation explicitly rejects multisampling and requires
depth/stencil to share one compatible Metal format. A stage-specific argument-buffer binder
now allocates an MTL argument buffer from the translated function, validates
resource kinds against the reflected PICA descriptor ABI, encodes constant and
structured buffers, sampled textures and samplers, and binds storage textures
through the direct Metal texture slots required by the iOS MSL path.
`SetPicaUniforms` now uploads the draw's vertex and fragment uniform snapshots
to the canonical stage bindings (0 and 4), retaining the Metal buffers with the
argument-buffer owner until it is shut down. The binder also retains encoded
buffers/textures and declares their per-stage residency with
`MTL::RenderCommandEncoder::useResource`; storage textures are declared
read/write before direct binding.
`GfxMetalPicaShader` compiles the generated MSL source through
`MTL::Device::newLibrary` at runtime and resolves the translated entry point.
`GfxMetalPicaPipeline` creates a native `MTL::RenderPipelineState` from the
compiled vertex/fragment functions and a supplied vertex descriptor. When
given a `PicaDrawView`, it maps PICA blend equations/factors, RGBA write mask,
depth comparison/write and front/back stencil operations to Metal state,
applies blend constants and culling at bind time, and rejects non-copy
framebuffer logic operations rather than silently changing their result.
Invalid compare, stencil, blend-factor and blend-equation values also fail
closed instead of being coerced to a default Metal enum. It also
consumes the PICA draw's blend/color-mask state when creating the pipeline and
binds the corresponding depth/stencil, cull/winding and blend-constant state.
This avoids requiring Apple's Windows Metal command-line compiler for the
runtime shader path. `GfxMetalPicaVertexInput` now converts each PICA vertex stream into
float4 Metal vertex data, builds a matching `MTL::VertexDescriptor`, reserves
Metal vertex buffer slot zero for the stage argument buffer, and creates the
index buffer when needed. Its draw encoder handles triangle lists and strips,
and expands triangle fans into an indexed triangle list. Geometry-shader
topology is rejected explicitly because Metal has no geometry-shader stage.
`GfxMetalPicaTextureResource` uses the shared PICA decoder to upload CPU-owned
texture snapshots as `RGBA8Unorm`, creates a Metal sampler, and enables
argument-buffer sampler support. It rejects snapshots with active GPU
`TextureCopy` producers rather than accidentally uploading stale guest bytes.
The uploader decodes and uploads the native PICA mip chain, then configures
Metal minification, magnification, mip filtering and LOD clamps. It rejects
clamp-to-border/asymmetric wrap modes until the corresponding PICA border and
wrap state is available to the backend. `GfxMetalPicaTextureCache` adds a
frame-aware 128 MiB default budget, content/sampler-aware identity, device
ownership checks and LRU eviction between frames. The PICA render-target cache
has a 192 MiB default budget but deliberately does not evict live guest
framebuffer contents: when the budget is exhausted it rejects new targets until
explicit retirement or snapshot support can preserve their contents. `GfxMetalPicaDepthStencilState`
maps PICA depth compare/write and stencil compare/fail/depth-fail/pass
operations to `MTL::DepthStencilState`; the PICA stencil configuration is
applied to both Metal faces and its reference value is set when binding.
`ConfigurePicaMetalColorAttachment` maps PICA blend factors, equations and
RGBA write masks to a Metal pipeline attachment. `BindPicaMetalRasterState`
maps cull/winding and the dynamic blend constant to the render encoder.
Non-COPY PICA logic operations are rejected because the Metal blend unit
cannot reproduce their bitwise semantics.

These are resource and draw-encoding primitives, not yet a complete ordered
PICA draw submission: GPU copy producer resolution, packed Shadow2D resources,
clamp-to-border/asymmetric wrap, full multi-attachment output mapping,
resource binding, render-target ownership and the backend interface are still
outstanding. Non-COPY logic operations are rejected explicitly. The runtime therefore does not select it as a renderer.

## Required backend surface

A native Metal backend must implement at least:

### Common graphics API

The pure virtual operations declared by
runtime/three_ds_recomp/include/fast/backends/gfx_rendering_api.h:
shader lifetime, textures and samplers, depth/blend/cull state, draw submission,
frame lifecycle, framebuffer allocation and updates, copies, readback,
presentation, and ImGui texture access.

### PICA transport

The pure virtual methods declared by
runtime/three_ds_recomp/include/fast/renderer3ds/pica_render_backend.h:

- SubmitPicaDraw
- SubmitPicaDisplayTransfer
- ClearPicaRenderTarget
- SubmitPicaMemoryFill

The backend must also preserve the state contracts around ordered submissions,
physical-memory reads/commits/deferred writes, completion tokens, pinned texture
copies, render-target snapshots, presentation snapshots, reset and temporal
samples. Returning success without implementing those semantics is invalid.

### Title and preparation hooks

Implement Extension::TitleRenderBackend for presentation settings, overlay
preparation and title scene-view publication. Implement
Renderer3ds::PicaProgramPreparationBackend for native vertex/fragment program
preparation and readiness reporting.

The existing NRI PICA executor and Vulkan extension passes cannot be reused as
a Metal implementation: their public interfaces include Vulkan handles and
NRI objects. Metal requires its own resource, command, synchronization and
pipeline implementations, while reusing the renderer-neutral PICA data
contracts and scheduling logic.

## Recommended implementation sequence

1. Introduce GfxRenderingAPIMetalPica in separate gfx_metal_pica.h/.mm
   files. Do not expand the legacy Fast3D class into the modern backend.
2. Add a renderer selection value for native PICA Metal and route it only on
   iOS after Metal device and CAMetalLayer availability checks.
3. Implement resource ownership first: textures, render targets, depth targets,
   staging/readback buffers, sampler state and command-buffer retirement.
4. Implement the ordered PICA operations: draw, display transfer, target clear
   and memory fill. Preserve the guest physical-memory and completion contracts.
5. Implement shader identity, source generation and MSL pipeline caching.
   SPIR-V-to-MSL conversion must preserve descriptor bindings, vertex layouts,
   specialization constants and attachment formats.
6. Port only renderer-neutral scene passes first. Vulkan/NRI-only effects must
   report unavailable capabilities and be disabled explicitly rather than
   silently approximated.
7. Add the iOS UIKit/SDL app host, application metadata, data-directory policy,
   input/touch mapping, orientation and lifecycle recovery.
8. Validate on a physical iPad: startup, title screen, scene rendering,
   framebuffer transfers, save/load, suspend/resume, memory pressure and
   long-running stability.

## Acceptance gates

- A C++ unit suite covers PICA draw ordering, texture-copy ownership,
  completion delivery and snapshot restore independently of Metal.
- Metal API validation is clean for a full representative scene.
- The runtime selects Metal explicitly; it never silently falls back to an
  unsupported renderer.
- A signed test build launches on the target iPad and completes a full gameplay
  loop. A successful cross-compile alone is not runtime validation.
