#pragma once

#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <set>
#include <span>
#include <string>
#include <tuple>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/extension/pica_display_transfer.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class CommandBuffer;
class ComputePipelineState;
class RenderPipelineState;
class Texture;
}

namespace Fast::Backends {

// Retains the GPU result of an ordered PICA display transfer. The cache is
// intentionally separate from sampled guest textures: a display image is a
// render-graph product, not a CPU-owned guest-memory texture.
class GfxMetalPicaDisplayTransferCache {
  public:
    static constexpr size_t kDefaultBudgetBytes = 64U * 1024U * 1024U;

    GfxMetalPicaDisplayTransferCache() = default;
    ~GfxMetalPicaDisplayTransferCache();

    GfxMetalPicaDisplayTransferCache(const GfxMetalPicaDisplayTransferCache&) = delete;
    GfxMetalPicaDisplayTransferCache& operator=(const GfxMetalPicaDisplayTransferCache&) = delete;

    void Clear();
    // Retain only immutable producer captures referenced by the current native
    // texture plan. An empty set is an explicit release of all prior captures.
    [[nodiscard]] bool SetPinnedCaptures(
        std::span<const Renderer3ds::PicaTextureCopyReference> copies,
        std::string* error = nullptr);
    [[nodiscard]] bool Submit(
        GfxMetalPicaDevice& device,
        MTL::CommandBuffer* commandBuffer,
        MTL::Texture* source,
        const Renderer3ds::PicaDisplayTransferView& transfer,
        const Extension::PicaDisplayTransferPlan& plan,
        std::string* error = nullptr);
    [[nodiscard]] bool CaptureRenderTarget(
        GfxMetalPicaDevice& device,
        MTL::CommandBuffer* commandBuffer,
        MTL::Texture* source,
        uint64_t renderTargetNamespace,
        uint64_t completionId,
        uint64_t afterDrawSubmissionId,
        uint32_t physicalAddress,
        std::string* error = nullptr);
    [[nodiscard]] MTL::Texture* FindCapturedRenderTarget(
        uint64_t renderTargetNamespace,
        uint64_t completionId,
        uint64_t afterDrawSubmissionId) const;
    [[nodiscard]] bool Present(
        GfxMetalPicaDevice& device,
        MTL::CommandBuffer* commandBuffer,
        MTL::Texture* source,
        MTL::Texture* drawable,
        Renderer3ds::PicaPresentationMode mode,
        std::string* error = nullptr);
    [[nodiscard]] MTL::Texture* Find(
        uint64_t renderTargetNamespace,
        uint32_t outputPhysicalAddress) const;
    [[nodiscard]] size_t ResidentBytes() const;

  private:
    struct Key {
        uint64_t RenderTargetNamespace = 0;
        uint32_t OutputPhysicalAddress = 0;
        auto operator<=>(const Key&) const = default;
    };
    using CaptureKey = std::tuple<uint64_t, uint64_t, uint64_t>;
    struct Entry {
        MTL::Texture* Texture = nullptr;
        uint32_t Width = 0;
        uint32_t Height = 0;
        size_t Bytes = 0;
        uint64_t LastUsedFrame = 0;
    };

    [[nodiscard]] bool EnsurePresentPipeline(
        GfxMetalPicaDevice& device,
        uint32_t pixelFormat,
        Renderer3ds::PicaPresentationMode mode,
        std::string* error);
    [[nodiscard]] bool EnsurePipeline(
        GfxMetalPicaDevice& device,
        std::string* error);

    MTL::Device* mDevice = nullptr;
    MTL::ComputePipelineState* mPipeline = nullptr;
    std::map<uint64_t, MTL::RenderPipelineState*> mPresentPipelines;
    std::map<Key, Entry> mEntries;
    std::map<CaptureKey, MTL::Texture*> mCapturedRenderTargets;
    std::set<uint64_t> mPinnedCompletionIds;
    bool mHasPinnedCaptureSet = false;
    size_t mResidentBytes = 0;
    size_t mBudgetBytes = kDefaultBudgetBytes;
    uint64_t mFrame = 0;
};

} // namespace Fast::Backends
