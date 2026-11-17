#include "fast/backends/gfx_metal_pica_draw_executor.h"

#include "fast/backends/gfx_metal_pica_draw_encoder.h"
#include "fast/backends/gfx_metal_pica_pipeline.h"
#include "fast/backends/gfx_metal_pica_draw_resources.h"
#include "fast/backends/gfx_metal_pica_shader.h"
#include "fast/renderer3ds/pica_msl_shader.h"

#include <Metal/Metal.hpp>

#include <algorithm>
#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

} // namespace

GfxMetalPicaDrawExecutor::CachedShader*
GfxMetalPicaDrawExecutor::ResolveShader(
    GfxMetalPicaDevice& device,
    std::string_view source,
    Renderer3ds::PicaMslShaderStage stage,
    std::string* error) {
    std::string key;
    key.reserve(source.size() + 1U);
    key.push_back(static_cast<char>(stage));
    key.append(source.data(), source.size());

    auto found = mShaderCache.find(key);
    if (found != mShaderCache.end() &&
        found->second.Device == device.Device()) {
        found->second.LastUsed = ++mShaderCacheClock;
        return &found->second;
    }
    if (found != mShaderCache.end()) {
        mShaderCache.erase(found);
    }

    CachedShader entry;
    if (!Renderer3ds::TranslatePicaGlslToMsl(
            source, stage, entry.Artifact, error)) {
        return nullptr;
    }
    entry.Shader = std::make_unique<GfxMetalPicaShader>();
    if (!entry.Shader->Compile(device.Device(), entry.Artifact, error)) {
        return nullptr;
    }
    entry.Device = device.Device();
    entry.LastUsed = ++mShaderCacheClock;
    auto [inserted, wasInserted] =
        mShaderCache.emplace(std::move(key), std::move(entry));
    if (!wasInserted) {
        SetError(error, "Metal PICA shader cache insertion failed");
        return nullptr;
    }

    return &inserted->second;
}

void GfxMetalPicaDrawExecutor::PruneShaderCache() {
    constexpr size_t kMaximumCachedShaders = 128U;
    while (mShaderCache.size() > kMaximumCachedShaders) {
        const auto oldest = std::min_element(
            mShaderCache.begin(), mShaderCache.end(),
            [](const auto& left, const auto& right) {
                return left.second.LastUsed < right.second.LastUsed;
            });
        if (oldest == mShaderCache.end()) {
            break;
        }
        mShaderCache.erase(oldest);
    }
}

GfxMetalPicaPipeline* GfxMetalPicaDrawExecutor::ResolvePipeline(
    GfxMetalPicaDevice& device,
    MTL::Function* vertexFunction,
    MTL::Function* fragmentFunction,
    MTL::VertexDescriptor* vertexDescriptor,
    const Renderer3ds::PicaDrawView& draw,
    uint32_t colorPixelFormat,
    uint32_t depthPixelFormat,
    std::unique_ptr<GfxMetalPicaPipeline>& transient,
    std::string* error) {
    const bool cacheable =
        draw.CanonicalPipelineId != 0U &&
        draw.CanonicalVertexProgramId != 0U &&
        draw.CanonicalFragmentProgramId != 0U;
    if (cacheable) {
        const PipelineKey key{
            draw.CanonicalPipelineId,
            draw.CanonicalVertexProgramId,
            draw.CanonicalFragmentProgramId,
            draw.CanonicalRasterStateId,
            draw.VertexShaderKey,
            draw.FragmentShaderKey,
            reinterpret_cast<uintptr_t>(device.Device()),
            colorPixelFormat,
            depthPixelFormat,
        };
        const auto found = mPipelineCache.find(key);
        if (found != mPipelineCache.end()) {
            found->second.LastUsed = ++mPipelineCacheClock;
            return found->second.Pipeline.get();
        }

        transient = std::make_unique<GfxMetalPicaPipeline>();
        if (!transient->Create(
                device.Device(),
                vertexFunction,
                fragmentFunction,
                vertexDescriptor,
                colorPixelFormat,
                depthPixelFormat,
                1U,
                &draw,
                error)) {
            transient.reset();
            return nullptr;
        }

        CachedPipeline entry;
        entry.Pipeline = std::move(transient);
        entry.LastUsed = ++mPipelineCacheClock;
        auto [inserted, wasInserted] =
            mPipelineCache.emplace(key, std::move(entry));
        if (!wasInserted) {
            SetError(error, "Metal PICA pipeline cache insertion failed");
            return nullptr;
        }
        return inserted->second.Pipeline.get();
    }

    transient = std::make_unique<GfxMetalPicaPipeline>();
    if (!transient->Create(
            device.Device(),
            vertexFunction,
            fragmentFunction,
            vertexDescriptor,
            colorPixelFormat,
            depthPixelFormat,
            1U,
            &draw,
            error)) {
        transient.reset();
        return nullptr;
    }
    return transient.get();
}

void GfxMetalPicaDrawExecutor::PrunePipelineCache() {
    constexpr size_t kMaximumCachedPipelines = 256U;
    while (mPipelineCache.size() > kMaximumCachedPipelines) {
        const auto oldest = std::min_element(
            mPipelineCache.begin(), mPipelineCache.end(),
            [](const auto& left, const auto& right) {
                return left.second.LastUsed < right.second.LastUsed;
            });
        if (oldest == mPipelineCache.end()) {
            break;
        }
        mPipelineCache.erase(oldest);
    }
}

void GfxMetalPicaDrawExecutor::ClearPipelineCache() {
    mPipelineCache.clear();
    mPipelineCacheClock = 0;
}

size_t GfxMetalPicaDrawExecutor::CachedPipelineCount() const {
    return mPipelineCache.size();
}

void GfxMetalPicaDrawExecutor::ClearShaderCache() {
    mShaderCache.clear();
    mShaderCacheClock = 0;
}

size_t GfxMetalPicaDrawExecutor::CachedShaderCount() const {
    return mShaderCache.size();
}

bool GfxMetalPicaDrawExecutor::ResolveAttachmentFormats(
    const Renderer3ds::PicaDrawView& draw,
    uint32_t& colorPixelFormat,
    uint32_t& depthPixelFormat,
    uint32_t& stencilPixelFormat,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    colorPixelFormat = 0U;
    depthPixelFormat = 0U;
    stencilPixelFormat = 0U;

    if (draw.FramebufferColorPhysicalAddress == 0U ||
        draw.FramebufferWidth == 0U || draw.FramebufferHeight == 0U ||
        draw.FramebufferDepthFormat > 3U) {
        SetError(error, "PICA Metal attachment policy received an invalid framebuffer identity or extent");
        return false;
    }

    colorPixelFormat = static_cast<uint32_t>(MTL::PixelFormatRGBA8Unorm);
    if (draw.FramebufferDepthPhysicalAddress == 0U) {
        if (draw.DepthTestEnabled || draw.DepthWriteEnabled ||
            draw.Stencil.Enabled) {
            colorPixelFormat = 0U;
            SetError(error, "PICA draw requires depth/stencil state but has no depth attachment");
            return false;
        }
        return true;
    }

    if (draw.FramebufferDepthFormat == 3U) {
        depthPixelFormat =
            static_cast<uint32_t>(MTL::PixelFormatDepth32Float_Stencil8);
        // The native target owns a combined depth/stencil image even when a
        // particular draw has stencil testing disabled.
        stencilPixelFormat = depthPixelFormat;
    } else {
        if (draw.Stencil.Enabled) {
            colorPixelFormat = 0U;
            SetError(error, "PICA stencil state requires the native combined depth/stencil format");
            return false;
        }
        depthPixelFormat =
            static_cast<uint32_t>(MTL::PixelFormatDepth32Float);
    }
    return true;
}

bool GfxMetalPicaDrawExecutor::Encode(
    GfxMetalPicaDevice& device,
    GfxMetalPicaTextureCache& textureCache,
    GfxMetalPicaRenderTargetCache& renderTargetCache,
    MTL::CommandBuffer* commandBuffer,
    const Renderer3ds::PicaDrawView& draw,
    bool clearColor,
    bool clearDepth,
    bool clearStencil,
    std::string* error) {
    uint32_t colorPixelFormat = 0U;
    uint32_t depthPixelFormat = 0U;
    uint32_t stencilPixelFormat = 0U;
    if (!ResolveAttachmentFormats(
            draw, colorPixelFormat, depthPixelFormat,
            stencilPixelFormat, error)) {
        return false;
    }
    return Encode(
        device, textureCache, renderTargetCache, commandBuffer, draw,
        colorPixelFormat, depthPixelFormat, stencilPixelFormat,
        clearColor, clearDepth, clearStencil, error);
}

bool GfxMetalPicaDrawExecutor::Encode(
    GfxMetalPicaDevice& device,
    GfxMetalPicaTextureCache& textureCache,
    GfxMetalPicaRenderTargetCache& renderTargetCache,
    MTL::CommandBuffer* commandBuffer,
    const Renderer3ds::PicaDrawView& draw,
    uint32_t colorPixelFormat,
    uint32_t depthPixelFormat,
    uint32_t stencilPixelFormat,
    bool clearColor,
    bool clearDepth,
    bool clearStencil,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!device.IsReady() || commandBuffer == nullptr) {
        SetError(error, "Metal PICA draw executor requires a ready device and active command buffer");
        return false;
    }
    if (draw.VertexShaderSource.empty() || draw.FragmentShaderSource.empty()) {
        SetError(error, "Metal PICA draw executor requires both canonical shader sources");
        return false;
    }

    CachedShader* vertexShader = ResolveShader(
        device, draw.VertexShaderSource,
        Renderer3ds::PicaMslShaderStage::Vertex, error);
    if (vertexShader == nullptr) {
        return false;
    }
    CachedShader* fragmentShader = ResolveShader(
        device, draw.FragmentShaderSource,
        Renderer3ds::PicaMslShaderStage::Fragment, error);
    if (fragmentShader == nullptr) {
        return false;
    }

    GfxMetalPicaDrawResources resources;
    if (!resources.Prepare(
            device, textureCache, draw,
            vertexShader->Artifact, vertexShader->Shader->Function(),
            fragmentShader->Artifact, fragmentShader->Shader->Function(),
            error)) {
        return false;
    }
    MTL::VertexDescriptor* vertexDescriptor = resources.VertexDescriptor();
    if (vertexDescriptor == nullptr) {
        SetError(error, "Metal PICA draw resources did not produce a vertex descriptor");
        return false;
    }

    std::unique_ptr<GfxMetalPicaPipeline> transientPipeline;
    GfxMetalPicaPipeline* pipeline = ResolvePipeline(
        device, vertexShader->Shader->Function(),
        fragmentShader->Shader->Function(), vertexDescriptor, draw,
        colorPixelFormat, depthPixelFormat,
        transientPipeline, error);
    if (pipeline == nullptr) {
        return false;
    }

    GfxMetalPicaRenderTarget* target = renderTargetCache.Resolve(
        device, draw, colorPixelFormat, depthPixelFormat,
        stencilPixelFormat, error);
    if (target == nullptr) {
        return false;
    }

    const bool encoded = GfxMetalPicaDrawEncoder::Encode(
        commandBuffer, *target, *pipeline, resources, draw,
        clearColor, clearDepth, clearStencil, error);
    vertexShader->LastUsed = ++mShaderCacheClock;
    fragmentShader->LastUsed = ++mShaderCacheClock;
    PruneShaderCache();
    PrunePipelineCache();
    return encoded;
}

} // namespace Fast::Backends
