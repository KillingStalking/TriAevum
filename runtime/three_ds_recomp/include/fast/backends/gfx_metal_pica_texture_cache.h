#pragma once

#include <compare>
#include <cstddef>
#include <cstdint>
#include <map>
#include <memory>
#include <string>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_texture.h"
#include "fast/renderer3ds/pica_native_state.h"

namespace Fast::Backends {

// Frame-aware cache for CPU-owned native PICA textures. GPU TextureCopy
// producers remain a separate ordered resource path and are never replaced
// with stale guest-memory bytes.
class GfxMetalPicaTextureCache {
  public:
    static constexpr size_t kDefaultBudgetBytes = 128U * 1024U * 1024U;

    GfxMetalPicaTextureCache() = default;
    ~GfxMetalPicaTextureCache();

    GfxMetalPicaTextureCache(const GfxMetalPicaTextureCache&) = delete;
    GfxMetalPicaTextureCache& operator=(const GfxMetalPicaTextureCache&) = delete;

    void BeginFrame(uint64_t frame);
    void SetBudgetBytes(size_t bytes);
    void Clear();

    [[nodiscard]] GfxMetalPicaTextureResource* Resolve(
        GfxMetalPicaDevice& device,
        const Renderer3ds::PicaTextureView& texture,
        std::string* error = nullptr);

    [[nodiscard]] size_t EntryCount() const;
    [[nodiscard]] size_t ResidentBytes() const;
    [[nodiscard]] size_t BudgetBytes() const;

  private:
    struct Key {
        uint64_t ContentHash = 0;
        uint32_t PhysicalAddress = 0;
        uint16_t Width = 0;
        uint16_t Height = 0;
        uint8_t NativeFormat = 0;
        uint8_t NativeType = 0;
        uint8_t WrapS = 0;
        uint8_t WrapT = 0;
        bool MinLinear = false;
        bool MagLinear = false;
        bool MipLinear = false;
        int16_t LodBiasRaw = 0;
        uint8_t MinMipLevel = 0;
        uint8_t MaxMipLevel = 0;

        auto operator<=>(const Key&) const = default;
    };

    struct Entry {
        std::unique_ptr<GfxMetalPicaTextureResource> Resource;
        size_t Bytes = 0;
        uint64_t LastUsedFrame = 0;
    };

    [[nodiscard]] static bool MakeKey(
        const Renderer3ds::PicaTextureView& texture,
        Key& key,
        std::string* error);
    void EvictToBudget();

    MTL::Device* mDevice = nullptr;
    std::map<Key, Entry> mEntries;
    size_t mResidentBytes = 0;
    size_t mBudgetBytes = kDefaultBudgetBytes;
    uint64_t mCurrentFrame = 0;
};

} // namespace Fast::Backends
