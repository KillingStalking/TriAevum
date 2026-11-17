#include "fast/backends/gfx_metal_pica_render_target_cache.h"

#include <algorithm>
#include <limits>
#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

size_t EstimateTargetBytes(
    uint32_t width,
    uint32_t height,
    uint32_t depthPixelFormat) {
    const uint64_t bytesPerPixel = depthPixelFormat == 0U ? 4U : 12U;
    const uint64_t bytes =
        static_cast<uint64_t>(width) * height * bytesPerPixel;
    return bytes > std::numeric_limits<size_t>::max()
        ? std::numeric_limits<size_t>::max()
        : static_cast<size_t>(bytes);
}

} // namespace

GfxMetalPicaRenderTargetCache::~GfxMetalPicaRenderTargetCache() {
    Clear();
}

void GfxMetalPicaRenderTargetCache::BeginFrame(uint64_t frame) {
    mCurrentFrame = frame;
    EvictToBudget();
}

void GfxMetalPicaRenderTargetCache::SetBudgetBytes(size_t bytes) {
    mBudgetBytes = bytes;
    EvictToBudget();
}

void GfxMetalPicaRenderTargetCache::Clear() {
    mEntries.clear();
    mDevice = nullptr;
    mResidentBytes = 0;
}

GfxMetalPicaRenderTarget* GfxMetalPicaRenderTargetCache::Resolve(
    GfxMetalPicaDevice& device,
    const Renderer3ds::PicaDrawView& draw,
    uint32_t metalColorPixelFormat,
    uint32_t metalDepthPixelFormat,
    uint32_t metalStencilPixelFormat,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!device.IsReady()) {
        SetError(error, "PICA Metal render-target cache requires an initialized device");
        return nullptr;
    }
    if (mDevice != nullptr && mDevice != device.Device()) {
        SetError(error, "PICA Metal render-target cache cannot mix resources from different Metal devices");
        return nullptr;
    }
    const bool needsDepth =
        draw.DepthTestEnabled || draw.DepthWriteEnabled || draw.Stencil.Enabled;
    if (draw.FramebufferColorPhysicalAddress == 0U ||
        draw.FramebufferWidth == 0U || draw.FramebufferHeight == 0U ||
        metalColorPixelFormat == 0U ||
        draw.FramebufferWidth > 16384U || draw.FramebufferHeight > 16384U ||
        (metalDepthPixelFormat != 0U &&
         draw.FramebufferDepthPhysicalAddress == 0U) ||
        (needsDepth && metalDepthPixelFormat == 0U) ||
        (draw.Stencil.Enabled != (metalStencilPixelFormat != 0U))) {
        SetError(error, "PICA Metal render-target identity or extent is invalid");
        return nullptr;
    }

    Key key{
        draw.RenderTargetNamespace,
        draw.FramebufferColorPhysicalAddress,
        draw.FramebufferDepthPhysicalAddress,
        draw.FramebufferWidth,
        draw.FramebufferHeight,
        draw.FramebufferColorFormat,
        draw.FramebufferDepthFormat,
        metalColorPixelFormat,
        metalDepthPixelFormat,
        metalStencilPixelFormat,
        1U,
    };
    const auto found = mEntries.find(key);
    if (found != mEntries.end()) {
        found->second.LastUsedFrame = mCurrentFrame;
        return found->second.Target.get();
    }

    const size_t bytes = EstimateTargetBytes(
        draw.FramebufferWidth, draw.FramebufferHeight,
        metalDepthPixelFormat);
    if (bytes == std::numeric_limits<size_t>::max() ||
        bytes > std::numeric_limits<size_t>::max() - mResidentBytes) {
        SetError(error, "PICA Metal render-target cache byte estimate overflowed");
        return nullptr;
    }

    auto target = std::make_unique<GfxMetalPicaRenderTarget>();
    if (!target->Create(
            device.Device(),
            draw.FramebufferWidth,
            draw.FramebufferHeight,
            metalColorPixelFormat,
            metalDepthPixelFormat,
            metalStencilPixelFormat,
            1U,
            error)) {
        return nullptr;
    }

    Entry entry;
    entry.Target = std::move(target);
    entry.Bytes = bytes;
    entry.LastUsedFrame = mCurrentFrame;
    auto [inserted, wasInserted] = mEntries.emplace(std::move(key), std::move(entry));
    if (!wasInserted) {
        SetError(error, "PICA Metal render-target cache insertion failed");
        return nullptr;
    }
    mResidentBytes += inserted->second.Bytes;
    mDevice = device.Device();
    EvictToBudget();
    return inserted->second.Target.get();
}

void GfxMetalPicaRenderTargetCache::EvictToBudget() {
    while (mResidentBytes > mBudgetBytes && !mEntries.empty()) {
        auto oldest = mEntries.end();
        for (auto candidate = mEntries.begin(); candidate != mEntries.end(); ++candidate) {
            if (candidate->second.LastUsedFrame == mCurrentFrame ||
                candidate->second.Target->IsActive()) {
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

size_t GfxMetalPicaRenderTargetCache::EntryCount() const {
    return mEntries.size();
}

size_t GfxMetalPicaRenderTargetCache::ResidentBytes() const {
    return mResidentBytes;
}

size_t GfxMetalPicaRenderTargetCache::BudgetBytes() const {
    return mBudgetBytes;
}

} // namespace Fast::Backends
