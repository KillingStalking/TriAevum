#pragma once

#include <string>

#include "fast/backends/gfx_metal_pica_argument_buffer.h"
#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_texture_cache.h"
#include "fast/backends/gfx_metal_pica_vertex_input.h"
#include "fast/renderer3ds/pica_msl_shader.h"
#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class Function;
class RenderCommandEncoder;
}

namespace Fast::Backends {

// Owns the per-draw Metal argument sets and vertex/index streams. The caller
// still owns the render target, pipeline cache and command-buffer ordering.
class GfxMetalPicaDrawResources {
  public:
    GfxMetalPicaDrawResources() = default;
    ~GfxMetalPicaDrawResources();

    GfxMetalPicaDrawResources(const GfxMetalPicaDrawResources&) = delete;
    GfxMetalPicaDrawResources& operator=(const GfxMetalPicaDrawResources&) = delete;

    [[nodiscard]] bool Prepare(
        GfxMetalPicaDevice& device,
        GfxMetalPicaTextureCache& textureCache,
        const Renderer3ds::PicaDrawView& draw,
        const Renderer3ds::PicaMslShaderArtifact& vertexArtifact,
        MTL::Function* vertexFunction,
        const Renderer3ds::PicaMslShaderArtifact& fragmentArtifact,
        MTL::Function* fragmentFunction,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool Bind(MTL::RenderCommandEncoder* encoder) const;
    [[nodiscard]] bool EncodeDraw(
        MTL::RenderCommandEncoder* encoder,
        std::string* error = nullptr) const;
    [[nodiscard]] bool IsPrepared() const;

  private:
    [[nodiscard]] static bool ValidateStageResources(
        const Renderer3ds::PicaMslShaderArtifact& artifact,
        const Renderer3ds::PicaDrawView& draw,
        std::string* error);

    GfxMetalPicaArgumentBuffer mVertexArguments;
    GfxMetalPicaArgumentBuffer mFragmentArguments;
    GfxMetalPicaVertexInput mVertexInput;
    Renderer3ds::PicaTopology mTopology =
        Renderer3ds::PicaTopology::TriangleList;
    bool mPrepared = false;
};

} // namespace Fast::Backends
