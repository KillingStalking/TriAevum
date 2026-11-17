#include "fast/backends/gfx_metal_pica_display_transfer.h"

#include <Metal/Metal.hpp>

#include <algorithm>
#include <limits>
#include <string>
#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

const char* kDisplayTransferShader = R"msl(
#include <metal_stdlib>
using namespace metal;

struct TransferState {
    uint2 sourceExtent;
    uint2 destinationExtent;
    uint2 sampleCount;
};

kernel void pica_display_transfer(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::write> destination [[texture(1)]],
    constant TransferState& state [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (any(gid >= state.destinationExtent)) {
        return;
    }
    const uint2 origin = gid * state.sampleCount;
    const uint2 maximum = state.sourceExtent - uint2(1);
    float4 value = source.read(min(origin, maximum));
    if (state.sampleCount.x == 2) {
        value += source.read(min(origin + uint2(1, 0), maximum));
        value *= 0.5;
    }
    if (state.sampleCount.y == 2) {
        float4 lower = source.read(min(origin + uint2(0, 1), maximum));
        if (state.sampleCount.x == 2) {
            lower += source.read(min(origin + uint2(1, 1), maximum));
            lower *= 0.5;
        }
        value = (value + lower) * 0.5;
    }
    destination.write(value, gid);
}
)msl";

struct TransferState {
    uint32_t SourceExtent[2];
    uint32_t DestinationExtent[2];
    uint32_t SampleCount[2];
};

} // namespace

GfxMetalPicaDisplayTransferCache::~GfxMetalPicaDisplayTransferCache() {
    Clear();
}

void GfxMetalPicaDisplayTransferCache::Clear() {
    for (auto& [key, entry] : mEntries) {
        (void)key;
        if (entry.Texture != nullptr) {
            entry.Texture->release();
        }
    }
    mEntries.clear();
    mResidentBytes = 0;
    if (mPipeline != nullptr) {
        mPipeline->release();
        mPipeline = nullptr;
    }
    mDevice = nullptr;
}

bool GfxMetalPicaDisplayTransferCache::EnsurePipeline(
    GfxMetalPicaDevice& device,
    std::string* error) {
    if (mPipeline != nullptr && mDevice == device.Device()) {
        return true;
    }
    if (!device.IsReady()) {
        SetError(error, "PICA Metal display transfer requires an initialized device");
        return false;
    }
    if (mDevice != nullptr && mDevice != device.Device()) {
        SetError(error, "PICA Metal display transfer cache cannot mix Metal devices");
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    NS::Error* nativeError = nullptr;
    NS::String* source = NS::String::string(
        kDisplayTransferShader, NS::UTF8StringEncoding);
    MTL::CompileOptions* options = MTL::CompileOptions::alloc()->init();
    MTL::Library* library = device.Device()->newLibrary(
        source, options, &nativeError);
    options->release();
    if (library == nullptr) {
        const char* description = nativeError != nullptr
            ? nativeError->localizedDescription()->utf8String()
            : "unknown Metal shader compiler error";
        SetError(error, std::string("PICA Metal display-transfer shader compilation failed: ") +
            (description != nullptr ? description : "unknown error"));
        pool->release();
        return false;
    }
    NS::String* entryName = NS::String::string(
        "pica_display_transfer", NS::UTF8StringEncoding);
    MTL::Function* function = library->newFunction(entryName);
    if (function == nullptr) {
        library->release();
        pool->release();
        SetError(error, "PICA Metal display-transfer kernel entry point is missing");
        return false;
    }
    MTL::ComputePipelineState* pipeline =
        device.Device()->newComputePipelineState(function, &nativeError);
    function->release();
    library->release();
    if (pipeline == nullptr) {
        const char* description = nativeError != nullptr
            ? nativeError->localizedDescription()->utf8String()
            : "unknown Metal pipeline error";
        SetError(error, std::string("PICA Metal display-transfer pipeline creation failed: ") +
            (description != nullptr ? description : "unknown error"));
        pool->release();
        return false;
    }
    mPipeline = pipeline;
    mDevice = device.Device();
    pool->release();
    return true;
}

bool GfxMetalPicaDisplayTransferCache::Submit(
    GfxMetalPicaDevice& device,
    MTL::CommandBuffer* commandBuffer,
    MTL::Texture* source,
    const Renderer3ds::PicaDisplayTransferView& transfer,
    const Extension::PicaDisplayTransferPlan& plan,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (commandBuffer == nullptr || source == nullptr ||
        transfer.OutputPhysicalAddress == 0U ||
        transfer.RenderTargetNamespace == 0U ||
        !plan.SamplingFitsSource() ||
        source->width() < plan.SourceWidth ||
        source->height() < plan.SourceHeight ||
        plan.DestinationWidth > 16384U ||
        plan.DestinationHeight > 16384U) {
        SetError(error, "PICA Metal display transfer has an invalid source, identity or extent");
        return false;
    }
    if (transfer.Present) {
        SetError(error, "PICA Metal display image is captured, but drawable composition is not connected to the host frame yet");
        return false;
    }
    if (!EnsurePipeline(device, error)) {
        return false;
    }

    const Key key{transfer.RenderTargetNamespace, transfer.OutputPhysicalAddress};
    auto found = mEntries.find(key);
    if (found != mEntries.end() &&
        (found->second.Width != plan.DestinationWidth ||
         found->second.Height != plan.DestinationHeight)) {
        mResidentBytes -= found->second.Bytes;
        found->second.Texture->release();
        mEntries.erase(found);
        found = mEntries.end();
    }

    if (found == mEntries.end()) {
        const uint64_t bytes = static_cast<uint64_t>(plan.DestinationWidth) *
            plan.DestinationHeight * 4U;
        if (bytes > std::numeric_limits<size_t>::max() ||
            bytes > mBudgetBytes || mResidentBytes > mBudgetBytes - bytes) {
            SetError(error, "PICA Metal display-image budget is exhausted; refusing to evict an image still addressable by guest display state");
            return false;
        }
        MTL::TextureDescriptor* descriptor =
            MTL::TextureDescriptor::texture2DDescriptor(
                MTL::PixelFormatRGBA8Unorm,
                plan.DestinationWidth, plan.DestinationHeight, false);
        if (descriptor == nullptr) {
            SetError(error, "Metal could not allocate a PICA display-image descriptor");
            return false;
        }
        descriptor->setStorageMode(MTL::StorageModePrivate);
        descriptor->setUsage(
            MTL::TextureUsageShaderRead | MTL::TextureUsageShaderWrite);
        MTL::Texture* texture = device.Device()->newTexture(descriptor);
        if (texture == nullptr) {
            SetError(error, "Metal could not allocate the PICA display image");
            return false;
        }
        Entry entry;
        entry.Texture = texture;
        entry.Width = plan.DestinationWidth;
        entry.Height = plan.DestinationHeight;
        entry.Bytes = static_cast<size_t>(bytes);
        auto inserted = mEntries.emplace(key, entry);
        found = inserted.first;
        mResidentBytes += entry.Bytes;
    }

    TransferState state{
        {plan.SourceWidth, plan.SourceHeight},
        {plan.DestinationWidth, plan.DestinationHeight},
        {plan.HorizontalSamples, plan.VerticalSamples},
    };
    MTL::ComputeCommandEncoder* encoder = commandBuffer->computeCommandEncoder();
    if (encoder == nullptr) {
        SetError(error, "Metal could not create a PICA display-transfer compute encoder");
        return false;
    }
    encoder->setComputePipelineState(mPipeline);
    encoder->setTexture(source, 0);
    encoder->setTexture(found->second.Texture, 1);
    encoder->setBytes(&state, sizeof(state), 0);
    const MTL::Size threads = MTL::Size::Make(
        plan.DestinationWidth, plan.DestinationHeight, 1);
    const MTL::Size group = MTL::Size::Make(8, 8, 1);
    encoder->dispatchThreads(threads, group);
    encoder->endEncoding();
    found->second.LastUsedFrame = ++mFrame;
    return true;
}

MTL::Texture* GfxMetalPicaDisplayTransferCache::Find(
    uint64_t renderTargetNamespace,
    uint32_t outputPhysicalAddress) const {
    const auto found = mEntries.find({renderTargetNamespace, outputPhysicalAddress});
    return found == mEntries.end() ? nullptr : found->second.Texture;
}

size_t GfxMetalPicaDisplayTransferCache::ResidentBytes() const {
    return mResidentBytes;
}

void GfxMetalPicaDisplayTransferCache::PruneToBudget() {
    // Display images are externally addressable by guest physical identity.
    // No eviction is safe until the runtime supplies explicit retirement.
}

} // namespace Fast::Backends
