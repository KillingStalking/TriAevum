#pragma once

#include <array>
#include <cstdint>
#include <string>

namespace MTL {
class CommandBuffer;
class RenderCommandEncoder;
class Texture;
}

namespace NS {
class AutoreleasePool;
}

namespace Fast::Backends {

struct GfxMetalPicaRenderTargetClearValues {
    std::array<double, 4> Color{0.0, 0.0, 0.0, 0.0};
    double Depth = 1.0;
    uint32_t Stencil = 0U;
};

// Owns one offscreen PICA color/depth target. It deliberately accepts Metal
// pixel formats from the caller; native PICA format conversion remains a
// separate, validated frontend responsibility.
class GfxMetalPicaRenderTarget {
  public:
    GfxMetalPicaRenderTarget() = default;
    ~GfxMetalPicaRenderTarget();

    GfxMetalPicaRenderTarget(const GfxMetalPicaRenderTarget&) = delete;
    GfxMetalPicaRenderTarget& operator=(const GfxMetalPicaRenderTarget&) = delete;

    [[nodiscard]] bool Create(
        MTL::Device* device,
        uint32_t width,
        uint32_t height,
        uint32_t colorPixelFormat,
        uint32_t depthPixelFormat,
        uint32_t stencilPixelFormat = 0,
        uint32_t sampleCount = 1,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool Begin(
        MTL::CommandBuffer* commandBuffer,
        bool clearColor,
        bool clearDepth,
        bool clearStencil,
        std::string* error = nullptr);
    [[nodiscard]] bool Begin(
        MTL::CommandBuffer* commandBuffer,
        bool clearColor,
        bool clearDepth,
        bool clearStencil,
        const GfxMetalPicaRenderTargetClearValues& clearValues,
        std::string* error = nullptr);
    [[nodiscard]] MTL::RenderCommandEncoder* Encoder() const;
    void End();
    [[nodiscard]] bool IsValid() const;
    [[nodiscard]] bool IsActive() const;

    [[nodiscard]] MTL::Texture* ColorTexture() const;
    [[nodiscard]] MTL::Texture* DepthTexture() const;
    [[nodiscard]] uint32_t Width() const;
    [[nodiscard]] uint32_t Height() const;
    [[nodiscard]] uint32_t ColorPixelFormat() const;
    [[nodiscard]] uint32_t DepthPixelFormat() const;
    [[nodiscard]] uint32_t StencilPixelFormat() const;
    [[nodiscard]] uint32_t SampleCount() const;

  private:
    NS::AutoreleasePool* mAutoreleasePool = nullptr;
    MTL::Texture* mColorTexture = nullptr;
    MTL::Texture* mDepthTexture = nullptr;
    MTL::RenderCommandEncoder* mEncoder = nullptr;
    uint32_t mWidth = 0;
    uint32_t mHeight = 0;
    uint32_t mColorPixelFormat = 0;
    uint32_t mDepthPixelFormat = 0;
    uint32_t mStencilPixelFormat = 0;
    uint32_t mSampleCount = 0;
    bool mHasBeenInitialized = false;
};

} // namespace Fast::Backends
