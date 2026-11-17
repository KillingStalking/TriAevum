#include "fast/backends/gfx_metal_pica_draw_encoder.h"

#include "fast/renderer3ds/pica_exclude_scissor.h"

#include <Metal/Metal.hpp>

#include <algorithm>
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

    // PICA mode 0 disables scissoring, mode 3 includes the register
    // rectangle, and mode 1 excludes it. Metal exposes one scissor rectangle
    // per draw, so the shared disjoint partition helper expands exclude mode
    // into up to four non-overlapping draws.
    const Renderer3ds::PicaScissorRect fullTarget{
        0, 0, target.Width(), target.Height()};
    Renderer3ds::PicaScissorParts scissorParts;
    if (draw.ScissorMode == 0U) {
        scissorParts.Rects[0] = fullTarget;
        scissorParts.Count = 1U;
    } else if (draw.ScissorMode == 3U) {
        const int64_t x1 = std::clamp<int64_t>(
            draw.ScissorX1, 0, target.Width());
        const int64_t y1 = std::clamp<int64_t>(
            draw.ScissorY1, 0, target.Height());
        const int64_t x2 = std::clamp<int64_t>(
            static_cast<int64_t>(draw.ScissorX2) + 1, 0, target.Width());
        const int64_t y2 = std::clamp<int64_t>(
            static_cast<int64_t>(draw.ScissorY2) + 1, 0, target.Height());
        if (x2 > x1 && y2 > y1) {
            scissorParts.Rects[0] = {
                static_cast<int32_t>(x1), static_cast<int32_t>(y1),
                static_cast<uint32_t>(x2 - x1),
                static_cast<uint32_t>(y2 - y1)};
            scissorParts.Count = 1U;
        }
    } else if (draw.ScissorMode == 1U) {
        const uint32_t x2 = static_cast<uint32_t>(draw.ScissorX2) + 1U;
        const uint32_t y2 = static_cast<uint32_t>(draw.ScissorY2) + 1U;
        const Renderer3ds::PicaScissorRect excluded{
            static_cast<int32_t>(draw.ScissorX1),
            static_cast<int32_t>(draw.ScissorY1),
            x2 > draw.ScissorX1 ? x2 - draw.ScissorX1 : 0U,
            y2 > draw.ScissorY1 ? y2 - draw.ScissorY1 : 0U};
        scissorParts =
            Renderer3ds::ExcludePicaScissor(fullTarget, excluded);
    } else {
        target.End();
        if (error != nullptr) {
            *error = "PICA Metal draw has an unsupported scissor mode";
        }
        return false;
    }

    for (uint32_t i = 0; i < scissorParts.Count; ++i) {
        const auto& rect = scissorParts.Rects[i];
        const MTL::ScissorRect metalScissor{
            static_cast<NS::UInteger>(rect.X),
            static_cast<NS::UInteger>(rect.Y),
            static_cast<NS::UInteger>(rect.Width),
            static_cast<NS::UInteger>(rect.Height)};
        encoder->setScissorRect(metalScissor);
        if (!resources.EncodeDraw(encoder, error)) {
            target.End();
            return false;
        }
    }
    target.End();
    return true;
}

} // namespace Fast::Backends
