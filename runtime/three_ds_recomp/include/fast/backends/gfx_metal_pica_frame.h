#pragma once

#include <string>

#include "fast/backends/gfx_metal_pica_device.h"

namespace MTL {
class CommandBuffer;
class RenderCommandEncoder;
}

namespace CA {
class MetalDrawable;
}

namespace NS {
class AutoreleasePool;
}

namespace Fast::Backends {

struct GfxMetalPicaClearColor {
    double Red = 0.0;
    double Green = 0.0;
    double Blue = 0.0;
    double Alpha = 1.0;
};

// Owns one drawable, command buffer and render encoder until presentation.
class GfxMetalPicaFrame {
  public:
    GfxMetalPicaFrame() = default;
    ~GfxMetalPicaFrame();

    GfxMetalPicaFrame(const GfxMetalPicaFrame&) = delete;
    GfxMetalPicaFrame& operator=(const GfxMetalPicaFrame&) = delete;

    [[nodiscard]] bool Begin(
        GfxMetalPicaDevice& device,
        GfxMetalPicaClearColor clearColor = {},
        std::string* error = nullptr);
    [[nodiscard]] MTL::RenderCommandEncoder* Encoder() const;
    [[nodiscard]] bool EndAndPresent(std::string* error = nullptr);
    void Cancel();
    [[nodiscard]] bool IsActive() const;

  private:
    NS::AutoreleasePool* mAutoreleasePool = nullptr;
    CA::MetalDrawable* mDrawable = nullptr;
    MTL::CommandBuffer* mCommandBuffer = nullptr;
    MTL::RenderCommandEncoder* mEncoder = nullptr;
};

} // namespace Fast::Backends
