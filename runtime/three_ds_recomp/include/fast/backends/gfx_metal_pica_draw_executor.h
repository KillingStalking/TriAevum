#pragma once

#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <string_view>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_pipeline.h"
#include "fast/backends/gfx_metal_pica_render_target_cache.h"
#include "fast/backends/gfx_metal_pica_shader.h"
#include "fast/backends/gfx_metal_pica_texture_cache.h"
#include "fast/renderer3ds/pica_msl_shader.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class CommandBuffer;
class Function;
}

namespace Fast::Backends {

// Complete single-draw orchestration for the native Metal PICA path. This
// deliberately leaves frame ordering, display transfers and command-buffer
// submission to the owning renderer.
class GfxMetalPicaDrawExecutor {
  public:
    [[nodiscard]] static bool ResolveAttachmentFormats(
        const Renderer3ds::PicaDrawView& draw,
        uint32_t& colorPixelFormat,
        uint32_t& depthPixelFormat,
        uint32_t& stencilPixelFormat,
        std::string* error = nullptr);

    [[nodiscard]] bool Encode(
        GfxMetalPicaDevice& device,
        GfxMetalPicaTextureCache& textureCache,
        GfxMetalPicaRenderTargetCache& renderTargetCache,
        MTL::CommandBuffer* commandBuffer,
        const Renderer3ds::PicaDrawView& draw,
        bool clearColor = false,
        bool clearDepth = false,
        bool clearStencil = false,
        std::string* error = nullptr);

    [[nodiscard]] bool Encode(
        GfxMetalPicaDevice& device,
        GfxMetalPicaTextureCache& textureCache,
        GfxMetalPicaRenderTargetCache& renderTargetCache,
        MTL::CommandBuffer* commandBuffer,
        const Renderer3ds::PicaDrawView& draw,
        uint32_t colorPixelFormat,
        uint32_t depthPixelFormat,
        uint32_t stencilPixelFormat,
        bool clearColor = false,
        bool clearDepth = false,
        bool clearStencil = false,
        std::string* error = nullptr);

    void ClearShaderCache();
    [[nodiscard]] size_t CachedShaderCount() const;
    void ClearPipelineCache();
    void ClearCaches();
    [[nodiscard]] size_t CachedPipelineCount() const;

  private:
    struct CachedShader {
        Renderer3ds::PicaMslShaderArtifact Artifact;
        std::unique_ptr<GfxMetalPicaShader> Shader;
        MTL::Device* Device = nullptr;
        uint64_t LastUsed = 0;
    };

    [[nodiscard]] CachedShader* ResolveShader(
        GfxMetalPicaDevice& device,
        std::string_view source,
        Renderer3ds::PicaMslShaderStage stage,
        std::string* error);

    void PruneShaderCache();
    [[nodiscard]] GfxMetalPicaPipeline* ResolvePipeline(
        GfxMetalPicaDevice& device,
        MTL::Function* vertexFunction,
        MTL::Function* fragmentFunction,
        MTL::VertexDescriptor* vertexDescriptor,
        const Renderer3ds::PicaDrawView& draw,
        uint32_t colorPixelFormat,
        uint32_t depthPixelFormat,
        std::unique_ptr<GfxMetalPicaPipeline>& transient,
        std::string* error);
    void PrunePipelineCache();

    struct PipelineKey {
        uint64_t CanonicalPipelineId = 0;
        uint64_t CanonicalVertexProgramId = 0;
        uint64_t CanonicalFragmentProgramId = 0;
        uint64_t CanonicalRasterStateId = 0;
        uint64_t VertexShaderKey = 0;
        uint64_t FragmentShaderKey = 0;
        std::string VertexLayoutIdentity;
        std::string RenderStateIdentity;
        uintptr_t DeviceIdentity = 0;
        uint32_t ColorPixelFormat = 0;
        uint32_t DepthPixelFormat = 0;

        auto operator<=>(const PipelineKey&) const = default;
    };
    struct CachedPipeline {
        std::unique_ptr<GfxMetalPicaPipeline> Pipeline;
        uint64_t LastUsed = 0;
    };

    std::map<std::string, CachedShader> mShaderCache;
    std::map<PipelineKey, CachedPipeline> mPipelineCache;
    uint64_t mShaderCacheClock = 0;
    uint64_t mPipelineCacheClock = 0;
};

} // namespace Fast::Backends
