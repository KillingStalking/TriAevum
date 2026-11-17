#include "fast/backends/gfx_metal_pica_draw_encoder.h"

#include <Metal/Metal.hpp>

#include <cmath>

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

    // PICA viewport coordinates are supplied in framebuffer pixels.
    // Metal consumes the same pixel-space rectangle; reject missing or invalid
    // viewport state rather than silently drawing with an undefined viewport.
    const bool validViewport =
        std::isfinite(draw.ViewportX) &&
        std::isfinite(draw.ViewportY) &&
        std::isfinite(draw.ViewportWidth) &&
        std::isfinite(draw.ViewportHeight) &&
        draw.ViewportWidth > 0.0F &&
        draw.ViewportHeight > 0.0F;
    if (!validViewport) {
        target.End();
        if (error != nullptr) {
            *error = "PICA Metal draw has an invalid or empty framebuffer viewport";
        }
        return false;
    }

    const MTL::Viewport viewport{
        static_cast<double>(draw.ViewportX),
        static_cast<double>(draw.ViewportY),
        static_cast<double>(draw.ViewportWidth),
        static_cast<double>(draw.ViewportHeight),
        0.0,
        1.0,
    };
    encoder->setViewport(viewport);

    const bool encoded = resources.EncodeDraw(encoder, error);
    target.End();
    return encoded;
}

} // namespace Fast::Backends
