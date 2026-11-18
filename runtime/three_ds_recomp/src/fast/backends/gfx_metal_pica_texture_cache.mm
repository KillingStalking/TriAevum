#include "fast/backends/gfx_metal_pica_texture_cache.h"

#include <algorithm>
#include <limits>
#include <span>
#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

uint64_t HashBytes(const std::span<const uint8_t> bytes) {
    uint64_t hash = 1469598103934665603ULL;
    for (const uint8_t byte : bytes) {
        hash ^= byte;
        hash *= 1099511628211ULL;
    }
    return hash == 0 ? 1 : hash;
}

size_t EstimateRgbaMipChainBytes(uint32_t width, uint32_t height, uint32_t maxMipLevel) {
    uint64_t total = 0;
    uint32_t levels = 1;
    uint32_t levelWidth = width;
    uint32_t levelHeight = height;
    while (levelWidth > 8U && levelHeight > 8U) {
        ++levels;
        levelWidth >>= 1U;
        levelHeight >>= 1U;
    }
    levels = std::min(levels, maxMipLevel + 1U);
    for (uint32_t level = 0; level < levels; ++level) {
        const uint64_t mipWidth = std::max(1U, width >> level);
        const uint64_t mipHeight = std::max(1U, height >> level);
        total += mipWidth * mipHeight * 4U;
    }
    return total > std::numeric_limits<size_t>::max()
        ? std::numeric_limits<size_t>::max()
        : static_cast<size_t>(total);
}

} // namespace

GfxMetalPicaTextureCache::~GfxMetalPicaTextureCache() {
    Clear();
}

void GfxMetalPicaTextureCache::BeginFrame(uint64_t frame) {
    mCurrentFrame = frame;
    EvictToBudget();
}

void GfxMetalPicaTextureCache::SetBudgetBytes(size_t bytes) {
    mBudgetBytes = bytes;
    EvictToBudget();
}

void GfxMetalPicaTextureCache::Clear() {
    mEntries.clear();
    mResidentBytes = 0;
    mDevice = nullptr;
}

bool GfxMetalPicaTextureCache::MakeKey(
    const Renderer3ds::PicaTextureView& texture,
    Key& key,
    std::string* error) {
    if (texture.Width == 0 || texture.Height == 0) {
        SetError(error, "PICA Metal texture cache rejects zero-sized textures");
        return false;
    }
    if (!texture.CopyReferences.empty()) {
        SetError(error, "PICA Metal texture cache cannot own an ordered GPU TextureCopy producer");
        return false;
    }
    if (texture.NativeBytes.empty()) {
        SetError(error, "PICA Metal texture cache requires CPU-owned source bytes");
        return false;
    }

    const uint64_t pixelCount =
        static_cast<uint64_t>(texture.Width) * texture.Height;
    if (pixelCount > std::numeric_limits<size_t>::max() / 4U) {
        SetError(error, "PICA Metal texture dimensions overflow RGBA8 storage");
        return false;
    }

    const uint64_t contentHash = texture.NativeContentHashAvailable
        ? texture.NativeContentHash
        : HashBytes(texture.NativeBytes);
    if (contentHash == 0) {
        SetError(error, "PICA Metal texture cache requires a nonzero content identity");
        return false;
    }

    key = {
        contentHash,
        texture.PhysicalAddress,
        texture.Width,
        texture.Height,
        texture.NativeFormat,
        texture.NativeType,
        texture.NativeWrapS,
        texture.NativeWrapT,
        texture.MinLinear,
        texture.MagLinear,
        texture.MipLinear,
        texture.LodBiasRaw,
        texture.MinMipLevel,
        texture.MaxMipLevel,
    };
    return true;
}

GfxMetalPicaTextureResource* GfxMetalPicaTextureCache::Resolve(
    GfxMetalPicaDevice& device,
    const Renderer3ds::PicaTextureView& texture,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!device.IsReady()) {
        SetError(error, "PICA Metal texture cache requires an initialized device");
        return nullptr;
    }

    if (mDevice != nullptr && mDevice != device.Device()) {
        SetError(error, "PICA Metal texture cache cannot mix resources from different Metal devices");
        return nullptr;
    }

    Key key;
    if (!MakeKey(texture, key, error)) {
        return nullptr;
    }

    const auto found = mEntries.find(key);
    if (found != mEntries.end()) {
        found->second.LastUsedFrame = mCurrentFrame;
        return found->second.Resource.get();
    }

    const size_t bytes = EstimateRgbaMipChainBytes(
        texture.Width, texture.Height, texture.MaxMipLevel);
    if (bytes == std::numeric_limits<size_t>::max()) {
        SetError(error, "PICA Metal texture mip-chain size overflows size_t");
        return nullptr;
    }

    auto resource = std::make_unique<GfxMetalPicaTextureResource>();
    if (!resource->Create(device.Device(), texture, error)) {
        return nullptr;
    }

    Entry entry;
    entry.Resource = std::move(resource);
    entry.Bytes = bytes;
    entry.LastUsedFrame = mCurrentFrame;
    auto [inserted, wasInserted] = mEntries.emplace(std::move(key), std::move(entry));
    if (!wasInserted) {
        SetError(error, "PICA Metal texture cache insertion raced with another owner");
        return nullptr;
    }
    if (inserted->second.Bytes >
        std::numeric_limits<size_t>::max() - mResidentBytes) {
        mEntries.erase(inserted);
        SetError(error, "PICA Metal texture cache resident-byte counter overflowed");
        return nullptr;
    }
    mResidentBytes += inserted->second.Bytes;
    mDevice = device.Device();
    EvictToBudget();
    return inserted->second.Resource.get();
}

void GfxMetalPicaTextureCache::EvictToBudget() {
    while (mResidentBytes > mBudgetBytes && !mEntries.empty()) {
        auto oldest = mEntries.end();
        for (auto candidate = mEntries.begin(); candidate != mEntries.end(); ++candidate) {
            if (candidate->second.LastUsedFrame == mCurrentFrame) {
                continue;
            }
            if (oldest == mEntries.end() ||
                candidate->second.LastUsedFrame < oldest->second.LastUsedFrame) {
                oldest = candidate;
            }
        }
        if (oldest == mEntries.end()) {
            break;
        }
        mResidentBytes -= oldest->second.Bytes;
        mEntries.erase(oldest);
    }
}

size_t GfxMetalPicaTextureCache::EntryCount() const {
    return mEntries.size();
}

size_t GfxMetalPicaTextureCache::ResidentBytes() const {
    return mResidentBytes;
}

size_t GfxMetalPicaTextureCache::BudgetBytes() const {
    return mBudgetBytes;
}

} // namespace Fast::Backends
