#include "fast/backends/gfx_metal_pica_render_target_cache.h"

#include "fast/renderer3ds/pica_memory_fill_decode.h"

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
}

void GfxMetalPicaRenderTargetCache::SetBudgetBytes(size_t bytes) {
    mBudgetBytes = bytes;
}

void GfxMetalPicaRenderTargetCache::Clear() {
    mEntries.clear();
    mPendingMemoryFills.clear();
    mDevice = nullptr;
    mResidentBytes = 0;
}

bool GfxMetalPicaRenderTargetCache::Clear(
    uint64_t renderTargetNamespace,
    uint32_t colorPhysicalAddress,
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (commandBuffer == nullptr || colorPhysicalAddress == 0U) {
        SetError(error, "PICA Metal target clear requires a command buffer and color attachment address");
        return false;
    }

    bool foundTarget = false;
    for (auto& [key, entry] : mEntries) {
        if (key.RenderTargetNamespace != renderTargetNamespace ||
            key.ColorPhysicalAddress != colorPhysicalAddress) {
            continue;
        }
        foundTarget = true;
        if (!ApplyPendingMemoryFills(key, entry, commandBuffer, error)) {
            return false;
        }
        auto& target = *entry.Target;
        if (!target.Begin(
                commandBuffer,
                true,
                target.DepthTexture() != nullptr,
                target.StencilPixelFormat() != 0U,
                error)) {
            return false;
        }
        target.End();
        entry.LastUsedFrame = mCurrentFrame;
    }
    if (!foundTarget) {
        const bool hasPendingFill = std::any_of(
            mPendingMemoryFills.begin(), mPendingMemoryFills.end(),
            [renderTargetNamespace](const auto& fill) {
                return fill.RenderTargetNamespace == renderTargetNamespace;
            });
        if (hasPendingFill) {
            SetError(error, "PICA Metal cannot order a target clear behind an unresolved memory fill without an allocated framebuffer");
            return false;
        }
    }
    // A target that has not been allocated yet starts with the same transparent
    // color, default depth and zero stencil on its first draw.
    return true;
}

GfxMetalPicaRenderTarget* GfxMetalPicaRenderTargetCache::Resolve(
    GfxMetalPicaDevice& device,
    const Renderer3ds::PicaDrawView& draw,
    uint32_t metalColorPixelFormat,
    uint32_t metalDepthPixelFormat,
    uint32_t metalStencilPixelFormat,
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!device.IsReady() || commandBuffer == nullptr) {
        SetError(error, "PICA Metal render-target cache requires an initialized device and active command buffer");
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
        (draw.Stencil.Enabled && draw.FramebufferDepthFormat != 3U) ||
        (draw.FramebufferDepthFormat == 3U &&
         (metalDepthPixelFormat == 0U ||
          metalStencilPixelFormat != metalDepthPixelFormat)) ||
        (draw.FramebufferDepthFormat != 3U &&
         metalStencilPixelFormat != 0U)) {
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
        if (!ApplyPendingMemoryFills(
                key, found->second, commandBuffer, error)) {
            return nullptr;
        }
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
    if (bytes > mBudgetBytes ||
        mResidentBytes > mBudgetBytes - bytes) {
        SetError(error, "PICA Metal framebuffer residency budget is exhausted; refusing to discard live render-target contents");
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
    if (!ApplyPendingMemoryFills(
            inserted->first, inserted->second, commandBuffer, error)) {
        return nullptr;
    }
    return inserted->second.Target.get();
}

bool GfxMetalPicaRenderTargetCache::SubmitMemoryFill(
    const Renderer3ds::PicaMemoryFillView& fill,
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (commandBuffer == nullptr || fill.StartPhysicalAddress == 0U ||
        fill.EndPhysicalAddress <= fill.StartPhysicalAddress ||
        (fill.Control & 1U) == 0U) {
        SetError(error, "native PICA Metal memory fill is incomplete");
        return false;
    }

    const auto previous = std::find_if(
        mPendingMemoryFills.begin(), mPendingMemoryFills.end(),
        [&](const auto& pending) {
            return pending.StartPhysicalAddress == fill.StartPhysicalAddress &&
                   pending.EndPhysicalAddress == fill.EndPhysicalAddress &&
                   pending.RenderTargetNamespace == fill.RenderTargetNamespace;
        });
    if (previous != mPendingMemoryFills.end()) {
        *previous = fill;
    } else {
        mPendingMemoryFills.push_back(fill);
    }

    for (auto& [key, entry] : mEntries) {
        if (key.RenderTargetNamespace != fill.RenderTargetNamespace) {
            continue;
        }
        if (!ApplyPendingMemoryFills(key, entry, commandBuffer, error)) {
            return false;
        }
    }
    return true;
}

bool GfxMetalPicaRenderTargetCache::ApplyPendingMemoryFills(
    const Key& key,
    Entry& entry,
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (mPendingMemoryFills.empty()) {
        return true;
    }
    if (commandBuffer == nullptr) {
        SetError(error, "native PICA Metal memory fill has no command buffer");
        return false;
    }

    const uint64_t pixelCount =
        static_cast<uint64_t>(key.Width) * key.Height;
    const uint64_t colorEnd =
        static_cast<uint64_t>(key.ColorPhysicalAddress) +
        pixelCount * Renderer3ds::PicaColorBytesPerPixel(
            key.NativeColorFormat);
    const uint64_t depthEnd = key.DepthPhysicalAddress != 0U
        ? static_cast<uint64_t>(key.DepthPhysicalAddress) +
              pixelCount * Renderer3ds::PicaDepthBytesPerPixel(
                  key.NativeDepthFormat)
        : 0U;

    auto fill = mPendingMemoryFills.begin();
    while (fill != mPendingMemoryFills.end()) {
        if (fill->RenderTargetNamespace != key.RenderTargetNamespace) {
            ++fill;
            continue;
        }
        const bool coversColor =
            fill->StartPhysicalAddress <= key.ColorPhysicalAddress &&
            fill->EndPhysicalAddress >= colorEnd;
        const bool coversDepth =
            key.DepthPhysicalAddress != 0U &&
            fill->StartPhysicalAddress <= key.DepthPhysicalAddress &&
            fill->EndPhysicalAddress >= depthEnd;
        if (!coversColor && !coversDepth) {
            ++fill;
            continue;
        }

        GfxMetalPicaRenderTargetClearValues clearValues;
        if (coversColor) {
            const auto decodedColor =
                Renderer3ds::DecodePicaMemoryFillColor(
                    *fill, key.NativeColorFormat);
            for (size_t channel = 0; channel < clearValues.Color.size(); ++channel) {
                clearValues.Color[channel] = decodedColor.Value[channel];
            }
        }
        if (coversDepth) {
            const auto decoded =
                Renderer3ds::DecodePicaMemoryFillDepthStencil(
                    *fill, key.NativeDepthFormat);
            clearValues.Depth = decoded.Depth;
            clearValues.Stencil = decoded.Stencil;
        }

        auto& target = *entry.Target;
        if (!target.Begin(
                commandBuffer,
                coversColor,
                coversDepth,
                coversDepth && key.NativeDepthFormat == 3U,
                clearValues,
                error)) {
            return false;
        }
        target.End();
        entry.LastUsedFrame = mCurrentFrame;
        fill = mPendingMemoryFills.erase(fill);
    }
    return true;
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
