#include "fast/backends/gfx_metal_pica_draw_executor.h"

#include "fast/backends/gfx_metal_pica_draw_encoder.h"
#include "fast/backends/gfx_metal_pica_pipeline.h"
#include "fast/backends/gfx_metal_pica_draw_resources.h"
#include "fast/backends/gfx_metal_pica_shader.h"
#include "fast/renderer3ds/pica_msl_shader.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

} // namespace

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

    Renderer3ds::PicaMslShaderArtifact vertexArtifact;
    if (!Renderer3ds::TranslatePicaGlslToMsl(
            draw.VertexShaderSource,
            Renderer3ds::PicaMslShaderStage::Vertex,
            vertexArtifact,
            error)) {
        return false;
    }

    Renderer3ds::PicaMslShaderArtifact fragmentArtifact;
    if (!Renderer3ds::TranslatePicaGlslToMsl(
            draw.FragmentShaderSource,
            Renderer3ds::PicaMslShaderStage::Fragment,
            fragmentArtifact,
            error)) {
        return false;
    }

    GfxMetalPicaShader vertexShader;
    if (!vertexShader.Compile(device.Device(), vertexArtifact, error)) {
        return false;
    }
    GfxMetalPicaShader fragmentShader;
    if (!fragmentShader.Compile(device.Device(), fragmentArtifact, error)) {
        return false;
    }

    GfxMetalPicaDrawResources resources;
    if (!resources.Prepare(
            device, textureCache, draw,
            vertexArtifact, vertexShader.Function(),
            fragmentArtifact, fragmentShader.Function(),
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
            vertexShader.Function(),
            fragmentShader.Function(),
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

    return GfxMetalPicaDrawEncoder::Encode(
        commandBuffer, *target, pipeline, resources, draw,
        clearColor, clearDepth, clearStencil, error);
}

} // namespace Fast::Backends
