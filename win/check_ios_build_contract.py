#!/usr/bin/env python3
"""Static regression checks for the Windows-hosted iOS build boundary."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"[FAIL] {message}")
    print(f"[OK] {message}")


def main() -> int:
    root_runtime_cmake = read("runtime/three_ds_recomp/CMakeLists.txt")
    game_cmake = read("CMake/oot3d/game.cmake")
    pica_contract = read("runtime/three_ds_recomp/include/fast/renderer3ds/pica_render_backend.h")
    legacy_metal_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal.h")
    toolchain = read("cmake/toolchains/ios-windows.cmake")
    apple_toolchain = read("cmake/toolchains/ios-apple.cmake")
    apple_workflow = read(".github/workflows/ios-metal-translation.yml")
    metal_deps = read("runtime/three_ds_recomp/cmake/dependencies/metal-pica.cmake")
    metal_shader = read("runtime/three_ds_recomp/src/fast/renderer3ds/pica_msl_shader.cpp")
    metal_device = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_device.mm")
    metal_device_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_device.h")
    metal_backend = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_backend.mm")
    metal_backend_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_backend.h")
    metal_frame = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_frame.mm")
    metal_frame_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_frame.h")
    metal_render_target = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_render_target.mm")
    metal_render_target_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_render_target.h")
    metal_render_target_cache = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_render_target_cache.mm")
    metal_render_target_cache_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_render_target_cache.h")
    metal_argument_buffer = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_argument_buffer.mm")
    metal_argument_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_argument_buffer.h")
    metal_draw_resources = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_draw_resources.mm")
    metal_draw_resources_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_draw_resources.h")
    metal_draw_encoder = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_draw_encoder.mm")
    metal_draw_encoder_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_draw_encoder.h")
    metal_draw_executor = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_draw_executor.mm")
    metal_draw_executor_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_draw_executor.h")
    metal_pipeline = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_pipeline.mm")
    metal_pipeline_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_pipeline.h")
    metal_shader_compile = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_shader.mm")
    metal_shader_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_shader.h")
    metal_vertex_input = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_vertex_input.mm")
    metal_vertex_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_vertex_input.h")
    metal_texture = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_texture.mm")
    metal_texture_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_texture.h")
    metal_texture_cache = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_texture_cache.mm")
    metal_texture_cache_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_texture_cache.h")
    metal_depth_stencil = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_depth_stencil.mm")
    metal_depth_stencil_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_depth_stencil.h")
    metal_raster = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_raster_state.mm")
    metal_raster_header = read("runtime/three_ds_recomp/include/fast/backends/gfx_metal_pica_raster_state.h")
    vulkan_pica_internal = read("runtime/three_ds_recomp/src/fast/backends/gfx_vulkan_pica_internal.h")
    pica_msl_header = read("runtime/three_ds_recomp/include/fast/renderer3ds/pica_msl_shader.h")
    pica_memory_fill_decode = read("runtime/three_ds_recomp/include/fast/renderer3ds/pica_memory_fill_decode.h")
    metal_render_target_source = read("runtime/three_ds_recomp/src/fast/backends/gfx_metal_pica_render_target.mm")
    source_runtime_cmake = read("runtime/three_ds_recomp/src/CMakeLists.txt")
    fast_cmake = read("runtime/three_ds_recomp/src/fast/CMakeLists.txt")
    build_driver = read("win/build_ios.py")

    require(root_runtime_cmake.count("include(cmake/dependencies/ios.cmake)") == 1,
            "iOS dependencies are included exactly once")
    require(
        'if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND NOT CMAKE_TOOLCHAIN_FILE)' in root_runtime_cmake,
        "legacy iOS toolchain bootstrap is skipped when an explicit toolchain is passed",
    )
    require(
        "if(NOT ANDROID AND OOT3D_ENABLE_VULKAN_RENDERER)" in game_cmake,
        "the native pipeline-preparation helper is gated by Vulkan",
    )
    for method in (
        "SubmitPicaDraw",
        "SubmitPicaDisplayTransfer",
        "ClearPicaRenderTarget",
        "SubmitPicaMemoryFill",
    ):
        require(f"virtual bool {method}(" in pica_contract,
                f"modern PICA backend contract includes {method}")
    require("class GfxRenderingAPIMetal final" in legacy_metal_header,
            "legacy Fast3D Metal backend remains separate")
    require("SubmitPicaDraw" not in legacy_metal_header,
            "legacy Metal class is not misrepresented as a modern PICA implementation")
    require('set(CMAKE_SYSTEM_NAME iOS)' in toolchain,
            "Windows cross-toolchain targets iOS rather than macOS")
    require("arm64-apple-ios15.0" in toolchain,
            "Windows cross-toolchain selects arm64 iOS device ABI")
    require("THREE_DS_RECOMP_ENABLE_METAL_PICA" in root_runtime_cmake and "oot3d_metal_shader_translation" in source_runtime_cmake,
            "the runtime has an explicit native Metal PICA build option")
    require("57e4efcc84112abcd426dc5ec248b5339bee04f2" in metal_deps,
            "SPIRV-Cross is pinned to a reproducible commit")
    require("spirv-cross-msl" in metal_deps,
            "the MSL compiler target is enabled")
    require("TranslatePicaGlslToMsl" in metal_shader and
            "TranslatePicaSpirvToMsl" in metal_shader and
            "CompilerMSL" in metal_shader and "CompileGlslToSpv" in metal_shader,
            "the PICA GLSL to SPIR-V to MSL translator is implemented")
    require("kPicaNriDescriptorBindings" in metal_shader and
            "add_msl_resource_binding" in metal_shader and
            "PicaMslShaderArtifact" in metal_shader,
            "the MSL artifact preserves and validates the PICA descriptor ABI")
    require("renderer_3ds_pica_shader_contract" in fast_cmake and
            "ThreeDsRecomp::PicaShaderContract" in source_runtime_cmake,
            "the shared PICA descriptor contract is linked without Vulkan/NRI")
    require("Options::iOS" in metal_shader and "set_msl_version(2, 3)" in metal_shader,
            "the translator targets iOS Metal Shading Language 2.3")
    require("ArgumentBuffersTier::Tier2" in metal_shader,
            "the translator enables iOS tier-2 argument buffers")
    require("oot3d_metal_shader_translation" in build_driver and
            "THREE_DS_RECOMP_ENABLE_METAL_PICA=ON" in build_driver,
            "the Windows build driver compiles the Metal shader translator")
    require("gfx_metal_pica_backend.mm" in source_runtime_cmake and
            "class GfxMetalPicaBackend final : public Renderer3ds::PicaRenderBackend" in metal_backend_header and
            "GfxMetalPicaDrawExecutor::Encode" in metal_backend and
            "draw.UberFragmentShaderSource" in metal_backend and
            "fallback.CanonicalPipelineId = 0U" in metal_backend and
            "fallback.FragmentShaderSourceIdentity = draw.UberFragmentShaderSourceIdentity" in metal_backend and
            "commandBuffer->commandQueue() != mDevice.CommandQueue()" in metal_backend and
            "mRenderTargetCache.Clear" in metal_backend and
            "mRenderTargetCache.SubmitMemoryFill" in metal_backend and
            "native PICA Metal display transfers are not implemented yet" in metal_backend,
            "the concrete Metal PICA backend owns draw, clear and memory-fill submission and fails closed for unimplemented display transfer")
    require("gfx_metal_pica_device.mm" in source_runtime_cmake and
            "GfxMetalPicaDevice::Initialize" in metal_device and
            "GfxMetalPicaDevice::WaitIdle" in metal_device and
            "SDL_RenderGetMetalLayer" in metal_device and
            "Initialize(SDL_Renderer*" in metal_device_header and
            "MTL::CommandQueue" in metal_device_header,
            "the Metal device/queue owner is part of the iOS build target")
    require("gfx_metal_pica_frame.mm" in source_runtime_cmake and
            "nextDrawable()" in metal_frame and
            "renderCommandEncoder" in metal_frame and
            "presentDrawable" in metal_frame and
            "EndAndPresent" in metal_frame_header and
            "CommandBuffer() const" in metal_frame_header and
            "EndEncoding(" in metal_frame and
            "BeginDrawablePass(" in metal_frame and
            "HasActiveEncoder() const" in metal_frame,
            "the Metal frame context supports offscreen command encoders before final drawable presentation")
    require("gfx_metal_pica_render_target.mm" in source_runtime_cmake and
            "TextureUsageRenderTarget" in metal_render_target and
            "TextureUsageShaderRead" in metal_render_target and
            "depthAttachment()" in metal_render_target and
            "stencilAttachment()" in metal_render_target and
            "sampleCount != 1U" in metal_render_target and
            "mHasBeenInitialized" in metal_render_target and
            "effectiveClearColor" in metal_render_target and
            "effectiveClearDepth" in metal_render_target and
            "ColorTexture()" in metal_render_target_header,
            "Metal owns offscreen PICA color/depth/stencil targets with explicit single-sample limits")
    require("DecodePicaMemoryFillColor" in pica_memory_fill_decode and
            "DecodePicaMemoryFillDepthStencil" in pica_memory_fill_decode and
            "PicaColorBytesPerPixel" in pica_memory_fill_decode and
            "PicaDepthBytesPerPixel" in pica_memory_fill_decode and
            "DecodePicaMemoryFillColor" in vulkan_pica_internal and
            "DecodePicaMemoryFillDepthStencil" in vulkan_pica_internal,
            "PICA memory-fill decoding is shared across renderer backends")
    require("gfx_metal_pica_render_target_cache.mm" in source_runtime_cmake and
            "PicaDrawView" in metal_render_target_cache and
            "RenderTargetNamespace" in metal_render_target_cache and
            "ColorPhysicalAddress" in metal_render_target_cache and
            "needsDepth" in metal_render_target_cache and
            "FramebufferDepthPhysicalAddress == 0U" in metal_render_target_cache and
            "draw.Stencil.Enabled && draw.FramebufferDepthFormat != 3U" in metal_render_target_cache and
            "metalStencilPixelFormat != metalDepthPixelFormat" in metal_render_target_cache and
            "kDefaultBudgetBytes = 192U * 1024U * 1024U" in metal_render_target_cache_header and
            "LastUsedFrame" in metal_render_target_cache and
            "refusing to discard live render-target contents" in metal_render_target_cache and
            "GfxMetalPicaRenderTargetCache::Clear" in metal_render_target_cache and
            "target.Begin(" in metal_render_target_cache and
            "target.End()" in metal_render_target_cache_header + metal_render_target_cache and
            "SubmitMemoryFill" in metal_render_target_cache_header and
            "mPendingMemoryFills" in metal_render_target_cache_header and
            "ApplyPendingMemoryFills" in metal_render_target_cache and
            "PicaColorBytesPerPixel" in metal_render_target_cache and
            "DecodePicaMemoryFillDepthStencil" in metal_render_target_cache and
            "clearValues" in metal_render_target_source,
            "PICA physical framebuffer identities reuse offscreen Metal targets with frame-aware LRU residency")
    require("overlapsColor" in metal_render_target_cache and
            "overlapsDepth" in metal_render_target_cache and
            "partially overlaps a framebuffer attachment" in metal_render_target_cache and
            "if ((overlapsColor && !coversColor)" in metal_render_target_cache,
            "Metal memory fills fail closed on partial framebuffer attachment overlap instead of silently leaving stale pixels")
    require("gfx_metal_pica_argument_buffer.mm" in source_runtime_cmake and
            "newArgumentEncoder(0)" in metal_argument_buffer and
            "setArgumentBuffer" in metal_argument_buffer and
            "setVertexBuffer" in metal_argument_buffer and
            "setFragmentBuffer" in metal_argument_buffer and
            "SetStorageTexture" in metal_argument_header and
            "SetNativePicaTexture" in metal_argument_buffer and
            "SetBufferBytes" in metal_argument_buffer and
            "TrackResource" in metal_argument_buffer and
            "useResource(resource, MTL::ResourceUsageRead, stages)" in metal_argument_buffer and
            "mReferencedResources" in metal_argument_buffer and
            "SetPicaUniforms" in metal_argument_buffer and
            "VertexUniformBytes" in metal_argument_buffer and
            "FragmentUniformBytes" in metal_argument_buffer and
            "1U + texture.Slot" in metal_argument_buffer and
            "7U + texture.Slot" in metal_argument_buffer and
            "cache.Resolve(device, texture, error)" in metal_argument_buffer,
            "the Metal binder resolves cached PICA texture/sampler pairs into canonical bindings")
    require("gfx_metal_pica_draw_resources.mm" in source_runtime_cmake and
            "ValidateStageResources" in metal_draw_resources and
            "SetPicaUniforms" in metal_draw_resources and
            "SetNativePicaTexture" in metal_draw_resources and
            "mVertexInput.Create" in metal_draw_resources and
            "mVertexInput.Bind" in metal_draw_resources and
            "EncodeDraw" in metal_draw_resources and
            "bool Prepare(" in metal_draw_resources_header,
            "a PICA draw prepares uniforms, sampled textures, argument sets and vertex/index streams with fail-closed descriptor validation")
    require("gfx_metal_pica_draw_encoder.mm" in source_runtime_cmake and
            "target.Begin(" in metal_draw_encoder and
            "pipeline.Bind(" in metal_draw_encoder and
            "resources.Bind(" in metal_draw_encoder and
            "resources.EncodeDraw(" in metal_draw_encoder and
            "target.End()" in metal_draw_encoder and
            "target.ColorPixelFormat() != pipeline.ColorPixelFormat()" in metal_draw_encoder and
            "target.DepthPixelFormat() != pipeline.DepthPixelFormat()" in metal_draw_encoder and
            "target.SampleCount() != pipeline.SampleCount()" in metal_draw_encoder and
            "ColorPixelFormat() const" in metal_pipeline_header and
            "static bool Encode(" in metal_draw_encoder_header and
            "#include <cmath>" in metal_draw_encoder and
            "std::isfinite(draw.ViewportX)" in metal_draw_encoder and
            "draw.ViewportWidth > 0.0F" in metal_draw_encoder and
            "encoder->setViewport(viewport)" in metal_draw_encoder and
            "pica_exclude_scissor.h" in metal_draw_encoder and
            "draw.ScissorMode == 3U" in metal_draw_encoder and
            "draw.ScissorMode == 1U" in metal_draw_encoder and
            "ExcludePicaScissor(fullTarget, excluded)" in metal_draw_encoder and
            "encoder->setScissorRect(metalScissor)" in metal_draw_encoder,
            "the ordered Metal PICA draw encoder binds resources and applies only finite, non-empty PICA viewport state")
    require("gfx_metal_pica_draw_executor.mm" in source_runtime_cmake and
            "TranslatePicaGlslToMsl" in metal_draw_executor and
            "ResolveAttachmentFormats" in metal_draw_executor_header and
            "PixelFormatRGBA8Unorm" in metal_draw_executor and
            "PixelFormatDepth32Float_Stencil8" in metal_draw_executor and
            "draw.FramebufferDepthFormat == 3U" in metal_draw_executor and
            "draw.FramebufferDepthFormat == 3U" in metal_render_target_cache and
            "PixelFormatDepth32Float_Stencil8" in metal_pipeline and
            "mStencilPixelFormat =" in metal_pipeline and
            "PixelFormatDepth32Float_Stencil8" in metal_pipeline_header + metal_pipeline and
            "mShaderCache" in metal_draw_executor_header and
            "kMaximumCachedShaders = 128U" in metal_draw_executor and
            "kMaximumCachedPipelines = 256U" in metal_draw_executor and
            "CanonicalRasterStateId" in metal_draw_executor_header and
            "CanonicalPipelineId" in metal_draw_executor and
            "BuildVertexLayoutIdentity(draw)" in metal_draw_executor and
            "BuildRenderStateIdentity(draw)" in metal_draw_executor and
            "RenderStateIdentity" in metal_draw_executor_header and
            "draw.Stencil.WriteMask" in metal_draw_executor and
            "mPipelineCache" in metal_draw_executor_header and
            "entry.Device = device.Device()" in metal_draw_executor and
            "vertexShader->Shader->Function()" in metal_draw_executor and
            "fragmentShader->Shader->Function()" in metal_draw_executor and
            "resources.Prepare" in metal_draw_executor and
            "resources.VertexDescriptor()" in metal_draw_executor and
            "pipeline.Create" in metal_draw_executor and
            "renderTargetCache.Resolve" in metal_draw_executor and
            "GfxMetalPicaDrawEncoder::Encode" in metal_draw_executor and
            "colorPixelFormat" in metal_draw_executor_header,
            "the Metal PICA draw executor translates both shader stages, prepares descriptors/resources, creates the matching pipeline and encodes into a cached target")
    require("gfx_metal_pica_pipeline.mm" in source_runtime_cmake and
            "newRenderPipelineState" in metal_pipeline and
            "setRenderPipelineState" in metal_pipeline and
            "ConfigurePicaMetalColorAttachment" in metal_pipeline and
            "GfxMetalPicaDepthStencilState" in metal_pipeline and
            "BindPicaMetalRasterState" in metal_pipeline and
            "draw->DepthTestEnabled" in metal_pipeline and
            "setStencilAttachmentPixelFormat" in metal_pipeline and
            "compatible Metal depth attachment format" in metal_pipeline and
            "draw->Blend" in metal_pipeline and
            "bool Create(" in metal_pipeline_header,
            "the Metal foundation creates and binds render pipelines")
    require("gfx_metal_pica_shader.mm" in source_runtime_cmake and
            "newLibrary(source, options" in metal_shader_compile and
            "LanguageVersion2_3" in metal_shader_compile and
            "newFunction(entryPoint)" in metal_shader_compile and
            "MTL::Function* Function()" in metal_shader_header,
            "the translated MSL is compiled to a native Metal shader function")
    require("gfx_metal_pica_vertex_input.mm" in source_runtime_cmake and
            "PicaDrawView" in metal_vertex_header and
            "VertexFormatFloat4" in metal_vertex_input and
            "newBuffer(" in metal_vertex_input and "packed.data()" in metal_vertex_input and
            "setVertexBuffer(" in metal_vertex_input and
            "binding.Binding) + 1U" in metal_vertex_input,
            "PICA vertex streams are packed into Metal buffers with slot zero reserved for argument buffers")
    require("TriangleFan" in metal_vertex_input and
            "fanIndices.push_back(sourceIndices[0])" in metal_vertex_input and
            "drawIndexedPrimitives(" in metal_vertex_input and
            "drawPrimitives(" in metal_vertex_input and
            "IndexTypeUInt16" in metal_vertex_input and
            "TriangleStrip" in metal_vertex_input,
            "Metal encodes PICA triangle lists, strips and fans with correct index widths")
    require("gfx_metal_pica_texture.mm" in source_runtime_cmake and
            "oot3d_renderer_texture_decode" in source_runtime_cmake and
            "DecodePicaTextureRgba8" in metal_texture and
            "CopyReferences.empty()" in metal_texture and
            "NativeType == 2U" in metal_texture and
            "newTexture(textureDescriptor)" in metal_texture and
            "newSamplerState(samplerDescriptor)" in metal_texture and
            "setSupportArgumentBuffers(true)" in metal_texture and
            "NativeMipLevelCount" in metal_texture and
            "replaceRegion(" in metal_texture and
            "setMipFilter(" in metal_texture and
            "MTL::Texture* Texture()" in metal_texture_header,
            "CPU-owned PICA textures decode to Metal RGBA8 resources with argument-buffer samplers; GPU copy producers are not misread")
    require("gfx_metal_pica_texture_cache.mm" in source_runtime_cmake and
            "kDefaultBudgetBytes" in metal_texture_cache_header and
            "BeginFrame" in metal_texture_cache_header and
            "EvictToBudget" in metal_texture_cache and
            "LastUsedFrame" in metal_texture_cache and
            "mDevice != device.Device()" in metal_texture_cache,
            "Metal PICA texture resources use a frame-aware, budgeted, device-local cache")
    require("gfx_metal_pica_depth_stencil.mm" in source_runtime_cmake and
            "ToMetalCompare" in metal_depth_stencil and
            "ToMetalStencilOperation" in metal_depth_stencil and
            "setFrontFaceStencil" in metal_depth_stencil and
            "setBackFaceStencil" in metal_depth_stencil and
            "setStencilReferenceValue" in metal_depth_stencil and
            "PICA depth compare function is invalid" in metal_depth_stencil and
            "PICA stencil state contains an invalid compare or operation" in metal_depth_stencil and
            "return false;" in metal_depth_stencil and
            "Create(" in metal_depth_stencil_header,
            "PICA depth, compare, stencil operations and reference values map to native Metal state")
    require("gfx_metal_pica_raster_state.mm" in source_runtime_cmake and
            "ToMetalBlendFactor" in metal_raster and
            "ToMetalBlendOperation" in metal_raster and
            "setWriteMask" in metal_raster and
            "PicaLogicOperation::Copy" in metal_raster and
            "PICA blend state contains an invalid operation or factor" in metal_raster and
            "return false;" in metal_raster and
            "setCullMode" in metal_raster and
            "setFrontFacingWinding" in metal_raster and
            "NativeCullMode::KeepCounterClockwise" in metal_raster and
            "MTL::WindingClockwise" in metal_raster and
            "PICA cull mode is invalid" in metal_raster and
            "KeepCounterClockwise ? Extension::PicaSceneFrontFace::Clockwise" in vulkan_pica_internal and
            "cullMode == Renderer3ds::NativeCullMode::KeepCounterClockwise" in metal_raster and
            "setBlendColor" in metal_raster and
            "ConfigurePicaMetalColorAttachment" in metal_raster_header,
            "PICA blend factors/equations, write mask, culling and winding map to Metal; unsupported logic ops fail explicitly")
    require("gfx_metal_pica_texture_cache.mm" in source_runtime_cmake and
            "NativeContentHashAvailable" in metal_texture_cache and
            "CopyReferences.empty()" in metal_texture_cache and
            "std::map<Key, Entry>" in metal_texture_cache_header and
            "kDefaultBudgetBytes = 128U * 1024U * 1024U" in metal_texture_cache_header and
            "EvictToBudget" in metal_texture_cache and
            "EstimateRgbaMipChainBytes" in metal_texture_cache and
            "LastUsedFrame" in metal_texture_cache,
            "Metal PICA textures are reused by content identity with a frame-aware 128 MiB residency budget")
    require("std::span<const uint32_t>" in pica_msl_header and
            "std::string_view glslSource" in pica_msl_header,
            "the translator accepts canonical GLSL and SPIR-V inputs")
    require("CMAKE_HOST_APPLE" in apple_toolchain and
            "set(CMAKE_SYSTEM_NAME iOS)" in apple_toolchain,
            "the Apple CI toolchain is selected before project()")
    require("macos-15" in apple_workflow and
            "oot3d_metal_shader_translation" in apple_workflow,
            "CI compiles the Metal translation target against the iPhoneOS SDK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
