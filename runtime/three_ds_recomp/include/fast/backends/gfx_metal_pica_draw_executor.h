#pragma once

#include <cstdint>
#include <string>

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_render_target_cache.h"
#include "fast/backends/gfx_metal_pica_texture_cache.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class CommandBuffer;
}

namespace Fast::Backends {

// Complete single-draw orchestration for the native Metal PICA path. This
// deliberately leaves frame ordering, display transfers and command-buffer
// submission to the owning renderer.
class GfxMetalPicaDrawExecutor {
  public:
    [[nodiscard]] static bool Encode(
        GfxMetalPicaDevice& device,
        GfxMetalPicaTextureCache& textureCache,
        GfxMetalPicaRenderTargetCache& renderTargetCache,
        MTL::CommandBuffer* commandBuffer,
        const Renderer3ds::PicaDrawView& draw,
        uint32_t colorPixelFormat,
        uint32_t depthPixelFormat,
        uint32_t stencilPixelFormat,
        bool clearColor = false,
        bool clearDepth = false,
        bool clearStencil = false,
        std::string* error = nullptr);
};

} // namespace Fast::Backends
