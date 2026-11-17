#pragma once

#include <string>

#include "fast/renderer3ds/pica_native_state.h"

namespace MTL {
class DepthStencilState;
class Device;
class RenderCommandEncoder;
}

namespace Fast::Backends {

// Converts the portable PICA depth/stencil state into a native Metal state.
// PICA exposes one stencil face state, so the same descriptor is installed
// for front and back faces.
class GfxMetalPicaDepthStencilState {
  public:
    GfxMetalPicaDepthStencilState() = default;
    ~GfxMetalPicaDepthStencilState();

    GfxMetalPicaDepthStencilState(const GfxMetalPicaDepthStencilState&) = delete;
    GfxMetalPicaDepthStencilState& operator=(const GfxMetalPicaDepthStencilState&) = delete;

    [[nodiscard]] bool Create(
        MTL::Device* device,
        bool depthTestEnabled,
        bool depthWriteEnabled,
        Renderer3ds::PicaCompareFunction depthCompare,
        const Renderer3ds::PicaStencilState& stencil,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool Bind(
        MTL::RenderCommandEncoder* encoder,
        uint8_t stencilReference = 0) const;
    [[nodiscard]] bool IsValid() const;
    [[nodiscard]] MTL::DepthStencilState* State() const;

  private:
    MTL::DepthStencilState* mState = nullptr;
};

} // namespace Fast::Backends
