#pragma once

#include <cstdint>
#include <string>

#include "fast/renderer3ds/pica_native_state.h"

#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class DepthStencilState;
class Device;
class Function;
class RenderCommandEncoder;
class RenderPipelineState;
class VertexDescriptor;
}

namespace Fast::Backends {

// Owns one compiled Metal render pipeline. Pipeline cache keys and PICA
// specialization handling are supplied by the higher-level renderer.
class GfxMetalPicaPipeline {
  public:
    GfxMetalPicaPipeline() = default;
    ~GfxMetalPicaPipeline();

    GfxMetalPicaPipeline(const GfxMetalPicaPipeline&) = delete;
    GfxMetalPicaPipeline& operator=(const GfxMetalPicaPipeline&) = delete;

    [[nodiscard]] bool Create(
        MTL::Device* device,
        MTL::Function* vertexFunction,
        MTL::Function* fragmentFunction,
        MTL::VertexDescriptor* vertexDescriptor,
        uint32_t colorPixelFormat,
        uint32_t depthPixelFormat = 0,
        uint32_t sampleCount = 1,
        const Renderer3ds::PicaDrawView* draw = nullptr,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool Bind(
        MTL::RenderCommandEncoder* encoder,
        const Renderer3ds::PicaDrawView* draw = nullptr) const;
    [[nodiscard]] bool IsValid() const;
    [[nodiscard]] MTL::RenderPipelineState* State() const;
    [[nodiscard]] uint32_t ColorPixelFormat() const;
    [[nodiscard]] uint32_t DepthPixelFormat() const;
    [[nodiscard]] uint32_t StencilPixelFormat() const;
    [[nodiscard]] uint32_t SampleCount() const;

  private:
    MTL::RenderPipelineState* mState = nullptr;
    MTL::DepthStencilState* mDepthStencilState = nullptr;
    uint32_t mColorPixelFormat = 0;
    uint32_t mDepthPixelFormat = 0;
    uint32_t mStencilPixelFormat = 0;
    uint32_t mSampleCount = 0;
};

} // namespace Fast::Backends
