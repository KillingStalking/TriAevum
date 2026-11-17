#pragma once

#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_render_target.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace Fast::Backends {

// Reuses offscreen targets by the full PICA framebuffer identity. Metal pixel
// formats are supplied by the backend's validated format/capability policy.
class GfxMetalPicaRenderTargetCache {
  public:
    static constexpr size_t kDefaultBudgetBytes = 192U * 1024U * 1024U;

    GfxMetalPicaRenderTargetCache() = default;
    ~GfxMetalPicaRenderTargetCache();

    GfxMetalPicaRenderTargetCache(const GfxMetalPicaRenderTargetCache&) = delete;
    GfxMetalPicaRenderTargetCache& operator=(const GfxMetalPicaRenderTargetCache&) = delete;

    void BeginFrame(uint64_t frame);
    void SetBudgetBytes(size_t bytes);
    void Clear();

    // Clears every cached extent/depth variant for one guest color
    // attachment, matching the native PICA target-clear identity.
    [[nodiscard]] bool Clear(
        uint64_t renderTargetNamespace,
        uint32_t colorPhysicalAddress,
        MTL::CommandBuffer* commandBuffer,
        std::string* error = nullptr);

    [[nodiscard]] GfxMetalPicaRenderTarget* Resolve(
        GfxMetalPicaDevice& device,
        const Renderer3ds::PicaDrawView& draw,
        uint32_t metalColorPixelFormat,
        uint32_t metalDepthPixelFormat,
        uint32_t metalStencilPixelFormat,
        MTL::CommandBuffer* commandBuffer,
        std::string* error = nullptr);

    [[nodiscard]] bool SubmitMemoryFill(
        const Renderer3ds::PicaMemoryFillView& fill,
        MTL::CommandBuffer* commandBuffer,
        std::string* error = nullptr);

    [[nodiscard]] size_t EntryCount() const;
    [[nodiscard]] size_t ResidentBytes() const;
    [[nodiscard]] size_t BudgetBytes() const;

  private:
    struct Key {
        uint64_t RenderTargetNamespace = 0;
        uint32_t ColorPhysicalAddress = 0;
        uint32_t DepthPhysicalAddress = 0;
        uint16_t Width = 0;
        uint16_t Height = 0;
        uint8_t NativeColorFormat = 0;
        uint8_t NativeDepthFormat = 0;
        uint32_t MetalColorPixelFormat = 0;
        uint32_t MetalDepthPixelFormat = 0;
        uint32_t MetalStencilPixelFormat = 0;
        uint32_t SampleCount = 1;

        auto operator<=>(const Key&) const = default;
    };

    struct Entry {
        std::unique_ptr<GfxMetalPicaRenderTarget> Target;
        size_t Bytes = 0;
        uint64_t LastUsedFrame = 0;
    };

    [[nodiscard]] bool ApplyPendingMemoryFills(
        const Key& key,
        Entry& entry,
        MTL::CommandBuffer* commandBuffer,
        std::string* error);

    std::map<Key, Entry> mEntries;
    std::vector<Renderer3ds::PicaMemoryFillView> mPendingMemoryFills;
    MTL::Device* mDevice = nullptr;
    size_t mResidentBytes = 0;
    size_t mBudgetBytes = kDefaultBudgetBytes;
    uint64_t mCurrentFrame = 0;
};

} // namespace Fast::Backends
