#pragma once

#include <cstdint>
#include <string>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_draw_executor.h"
#include "fast/backends/gfx_metal_pica_frame.h"
#include "fast/backends/gfx_metal_pica_render_target_cache.h"
#include "fast/backends/gfx_metal_pica_texture_cache.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class CommandBuffer;
}

struct SDL_Renderer;

namespace Fast::Backends {

// Concrete native-Metal implementation of the renderer-neutral PICA
// submission contract. The host owns drawable acquisition/presentation and
// supplies its active command buffer for each frame.
class GfxMetalPicaBackend final : public Renderer3ds::PicaRenderBackend {
  public:
    GfxMetalPicaBackend() = default;
    ~GfxMetalPicaBackend() override;

    GfxMetalPicaBackend(const GfxMetalPicaBackend&) = delete;
    GfxMetalPicaBackend& operator=(const GfxMetalPicaBackend&) = delete;

    [[nodiscard]] bool Initialize(
        SDL_Renderer* renderer,
        std::string* error = nullptr);
    [[nodiscard]] bool BeginFrame(
        MTL::CommandBuffer* commandBuffer,
        std::string* error = nullptr);
    void EndFrame();
    [[nodiscard]] bool Shutdown(std::string* error = nullptr);

    [[nodiscard]] bool SubmitPicaDraw(
        const Renderer3ds::PicaDrawView& draw,
        std::string* error = nullptr) override;
    [[nodiscard]] bool SubmitPicaDisplayTransfer(
        const Renderer3ds::PicaDisplayTransferView& transfer,
        std::string* error = nullptr) override;
    [[nodiscard]] bool ClearPicaRenderTarget(
        uint64_t renderTargetNamespace,
        uint32_t colorPhysicalAddress,
        std::string* error = nullptr) override;
    [[nodiscard]] bool SubmitPicaMemoryFill(
        const Renderer3ds::PicaMemoryFillView& fill,
        std::string* error = nullptr) override;
    [[nodiscard]] bool ResetPicaState(
        std::string* error = nullptr) override;

    [[nodiscard]] bool IsReady() const;
    [[nodiscard]] bool HasActiveFrame() const;
    [[nodiscard]] GfxMetalPicaDevice& Device();

  private:
    GfxMetalPicaDevice mDevice;
    GfxMetalPicaFrame mUnusedFrame;
    GfxMetalPicaTextureCache mTextureCache;
    GfxMetalPicaRenderTargetCache mRenderTargetCache;
    GfxMetalPicaDrawExecutor mDrawExecutor;
    MTL::CommandBuffer* mCommandBuffer = nullptr;
    uint64_t mFrameIndex = 0;
};

} // namespace Fast::Backends
