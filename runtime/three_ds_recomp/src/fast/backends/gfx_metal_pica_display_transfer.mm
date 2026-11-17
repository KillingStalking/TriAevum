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


const char* kDisplayPresentShader = R"msl(
#include <metal_stdlib>
using namespace metal;

struct PresentVertex {
    float4 position [[position]];
    float2 uv;
};

vertex PresentVertex pica_present_vertex(uint vertexId [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
    };
    PresentVertex out;
    const float2 position = positions[vertexId];
    out.position = float4(position, 0.0, 1.0);
    out.uv = float2((position.x + 1.0) * 0.5, (1.0 - position.y) * 0.5);
    return out;
}

fragment float4 pica_present_fragment(
    PresentVertex in [[stage_in]],
    texture2d<float> source [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]) {
    return source.sample(sourceSampler, in.uv);
}
)msl";

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
    for (auto& [key, pipeline] : mPresentPipelines) {
        (void)key;
        if (pipeline != nullptr) pipeline->release();
    }
    mPresentPipelines.clear();
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
        !plan.SamplingFitsSource() ||
        source->width() < plan.SourceWidth ||
        source->height() < plan.SourceHeight ||
        plan.DestinationWidth > 16384U ||
        plan.DestinationHeight > 16384U) {
        SetError(error, "PICA Metal display transfer has an invalid source, identity or extent");
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


bool GfxMetalPicaDisplayTransferCache::EnsurePresentPipeline(
    GfxMetalPicaDevice& device,
    uint32_t pixelFormat,
    Renderer3ds::PicaPresentationMode mode,
    std::string* error) {
    const uint64_t key = (static_cast<uint64_t>(pixelFormat) << 8U) |
        static_cast<uint8_t>(mode);
    if (mPresentPipelines.contains(key)) return true;
    if (!device.IsReady() || (mode != Renderer3ds::PicaPresentationMode::Replace &&
        mode != Renderer3ds::PicaPresentationMode::AlphaOverlay)) {
        SetError(error, "PICA Metal compositor received an unsupported device or presentation mode");
        return false;
    }
    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    NS::Error* nativeError = nullptr;
    NS::String* source = NS::String::string(kDisplayPresentShader, NS::UTF8StringEncoding);
    MTL::CompileOptions* options = MTL::CompileOptions::alloc()->init();
    MTL::Library* library = device.Device()->newLibrary(source, options, &nativeError);
    options->release();
    if (library == nullptr) {
        const char* description = nativeError != nullptr
            ? nativeError->localizedDescription()->utf8String() : "unknown Metal shader compiler error";
        SetError(error, std::string("PICA Metal compositor shader compilation failed: ") +
            (description != nullptr ? description : "unknown error"));
        pool->release();
        return false;
    }
    NS::String* vertexName = NS::String::string("pica_present_vertex", NS::UTF8StringEncoding);
    NS::String* fragmentName = NS::String::string("pica_present_fragment", NS::UTF8StringEncoding);
    MTL::Function* vertex = library->newFunction(vertexName);
    MTL::Function* fragment = library->newFunction(fragmentName);
    MTL::RenderPipelineDescriptor* descriptor = MTL::RenderPipelineDescriptor::alloc()->init();
    if (vertex == nullptr || fragment == nullptr || descriptor == nullptr) {
        if (vertex) vertex->release();
        if (fragment) fragment->release();
        if (descriptor) descriptor->release();
        library->release();
        pool->release();
        SetError(error, "PICA Metal compositor shader entry point or pipeline descriptor is missing");
        return false;
    }
    descriptor->setVertexFunction(vertex);
    descriptor->setFragmentFunction(fragment);
    MTL::RenderPipelineColorAttachmentDescriptor* attachment =
        descriptor->colorAttachments()->object(0);
    attachment->setPixelFormat(static_cast<MTL::PixelFormat>(pixelFormat));
    if (mode == Renderer3ds::PicaPresentationMode::AlphaOverlay) {
        attachment->setBlendingEnabled(true);
        attachment->setRgbBlendOperation(MTL::BlendOperationAdd);
        attachment->setAlphaBlendOperation(MTL::BlendOperationAdd);
        attachment->setSourceRGBBlendFactor(MTL::BlendFactorSourceAlpha);
        attachment->setDestinationRGBBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
        attachment->setSourceAlphaBlendFactor(MTL::BlendFactorOne);
        attachment->setDestinationAlphaBlendFactor(MTL::BlendFactorOneMinusSourceAlpha);
    }
    MTL::RenderPipelineState* pipeline =
        device.Device()->newRenderPipelineState(descriptor, &nativeError);
    descriptor->release();
    vertex->release();
    fragment->release();
    library->release();
    if (pipeline == nullptr) {
        const char* description = nativeError != nullptr
            ? nativeError->localizedDescription()->utf8String() : "unknown Metal pipeline error";
        SetError(error, std::string("PICA Metal compositor pipeline creation failed: ") +
            (description != nullptr ? description : "unknown error"));
        pool->release();
        return false;
    }
    mPresentPipelines.emplace(key, pipeline);
    pool->release();
    return true;
}

bool GfxMetalPicaDisplayTransferCache::Present(
    GfxMetalPicaDevice& device,
    MTL::CommandBuffer* commandBuffer,
    MTL::Texture* source,
    MTL::Texture* drawable,
    Renderer3ds::PicaPresentationMode mode,
    std::string* error) {
    if (error != nullptr) error->clear();
    if (commandBuffer == nullptr || source == nullptr || drawable == nullptr ||
        source->width() == 0U || source->height() == 0U ||
        drawable->width() == 0U || drawable->height() == 0U ||
        source->pixelFormat() != MTL::PixelFormatRGBA8Unorm) {
        SetError(error, "PICA Metal compositor received an invalid source, drawable or extent");
        return false;
    }
    if (!EnsurePresentPipeline(device, static_cast<uint32_t>(drawable->pixelFormat()), mode, error))
        return false;
    const uint64_t key = (static_cast<uint64_t>(drawable->pixelFormat()) << 8U) |
        static_cast<uint8_t>(mode);
    MTL::SamplerDescriptor* samplerDescriptor = MTL::SamplerDescriptor::alloc()->init();
    if (samplerDescriptor == nullptr) {
        SetError(error, "Metal could not allocate the PICA compositor sampler descriptor");
        return false;
    }
    samplerDescriptor->setMinFilter(MTL::SamplerMinMagFilterLinear);
    samplerDescriptor->setMagFilter(MTL::SamplerMinMagFilterLinear);
    samplerDescriptor->setSAddressMode(MTL::SamplerAddressModeClampToEdge);
    samplerDescriptor->setTAddressMode(MTL::SamplerAddressModeClampToEdge);
    MTL::SamplerState* sampler = device.Device()->newSamplerState(samplerDescriptor);
    samplerDescriptor->release();
    if (sampler == nullptr) {
        SetError(error, "Metal could not create the PICA compositor sampler");
        return false;
    }
    MTL::RenderPassDescriptor* pass = MTL::RenderPassDescriptor::renderPassDescriptor();
    if (pass == nullptr) {
        sampler->release();
        SetError(error, "Metal could not allocate the PICA compositor render pass");
        return false;
    }
    MTL::RenderPassColorAttachmentDescriptor* color = pass->colorAttachments()->object(0);
    color->setTexture(drawable);
    color->setLoadAction(mode == Renderer3ds::PicaPresentationMode::AlphaOverlay
        ? MTL::LoadActionLoad : MTL::LoadActionClear);
    color->setStoreAction(MTL::StoreActionStore);
    MTL::RenderCommandEncoder* encoder = commandBuffer->renderCommandEncoder(pass);
    if (encoder == nullptr) {
        sampler->release();
        SetError(error, "Metal could not create the PICA compositor render encoder");
        return false;
    }
    encoder->setRenderPipelineState(mPresentPipelines.at(key));
    encoder->setFragmentTexture(source, 0);
    encoder->setFragmentSamplerState(sampler, 0);
    encoder->drawPrimitives(MTL::PrimitiveTypeTriangle, 0, 3);
    encoder->endEncoding();
    sampler->release();
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


} // namespace Fast::Backends
