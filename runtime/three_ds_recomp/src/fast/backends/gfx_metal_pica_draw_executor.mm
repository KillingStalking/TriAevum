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

void GfxMetalPicaDrawExecutor::ClearShaderCache() {
    mShaderCache.clear();
    mShaderCacheClock = 0;
}

size_t GfxMetalPicaDrawExecutor::CachedShaderCount() const {
    return mShaderCache.size();
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

    GfxMetalPicaPipeline pipeline;
    if (!pipeline.Create(
            device.Device(),
            vertexShader->Shader->Function(),
            fragmentShader->Shader->Function(),
            vertexDescriptor,
            colorPixelFormat,
            depthPixelFormat,
            1U,
            &draw,
            error)) {
        return false;
    }

    GfxMetalPicaRenderTarget* target = renderTargetCache.Resolve(
        device, draw, colorPixelFormat, depthPixelFormat,
        stencilPixelFormat, error);
    if (target == nullptr) {
        return false;
    }

    const bool encoded = GfxMetalPicaDrawEncoder::Encode(
        commandBuffer, *target, pipeline, resources, draw,
        clearColor, clearDepth, clearStencil, error);
    vertexShader->LastUsed = ++mShaderCacheClock;
    fragmentShader->LastUsed = ++mShaderCacheClock;
    PruneShaderCache();
    return encoded;
}

} // namespace Fast::Backends
