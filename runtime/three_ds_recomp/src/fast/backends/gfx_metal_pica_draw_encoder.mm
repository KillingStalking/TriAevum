#include "fast/backends/gfx_metal_pica_draw_encoder.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {

bool GfxMetalPicaDrawEncoder::Encode(
    MTL::CommandBuffer* commandBuffer,
    GfxMetalPicaRenderTarget& target,
    const GfxMetalPicaPipeline& pipeline,
    const GfxMetalPicaDrawResources& resources,
    const Renderer3ds::PicaDrawView& draw,
    bool clearColor,
    bool clearDepth,
    bool clearStencil,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (commandBuffer == nullptr || !target.IsValid() ||
        !pipeline.IsValid() || !resources.IsPrepared()) {
        if (error != nullptr) {
            *error = "PICA Metal draw requires a command buffer, render target, pipeline and prepared resources";
        }
        return false;
    }
    if (target.Width() != draw.FramebufferWidth ||
        target.Height() != draw.FramebufferHeight ||
        target.ColorPixelFormat() != pipeline.ColorPixelFormat() ||
        target.DepthPixelFormat() != pipeline.DepthPixelFormat() ||
        target.StencilPixelFormat() != pipeline.StencilPixelFormat() ||
        target.SampleCount() != pipeline.SampleCount()) {
        if (error != nullptr) {
            *error = "PICA draw framebuffer extent or attachment formats do not match its Metal pipeline";
        }
        return false;
    }
    if (!target.Begin(
            commandBuffer, clearColor, clearDepth, clearStencil, error)) {
        return false;
    }

    MTL::RenderCommandEncoder* encoder = target.Encoder();
    if (encoder == nullptr || !pipeline.Bind(encoder, &draw) ||
        !resources.Bind(encoder)) {
        target.End();
        if (error != nullptr) {
            *error = "PICA Metal pipeline or draw resources could not bind";
        }
        return false;
    }

    const bool encoded = resources.EncodeDraw(encoder, error);
    target.End();
    return encoded;
}

} // namespace Fast::Backends
