#pragma once

#include <string>

#include "fast/backends/gfx_metal_pica_draw_resources.h"
#include "fast/backends/gfx_metal_pica_pipeline.h"
#include "fast/backends/gfx_metal_pica_render_target.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class CommandBuffer;
}

namespace Fast::Backends {

// Encodes one ordered PICA draw into an already resolved offscreen target.
// The caller owns command-buffer submission and serializes calls in PICA order.
class GfxMetalPicaDrawEncoder {
  public:
    [[nodiscard]] static bool Encode(
        MTL::CommandBuffer* commandBuffer,
        GfxMetalPicaRenderTarget& target,
        const GfxMetalPicaPipeline& pipeline,
        const GfxMetalPicaDrawResources& resources,
        const Renderer3ds::PicaDrawView& draw,
        bool clearColor = false,
        bool clearDepth = false,
        bool clearStencil = false,
        std::string* error = nullptr);
};

} // namespace Fast::Backends
