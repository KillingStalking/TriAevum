#pragma once

#include <string>

#include "fast/renderer3ds/pica_native_state.h"

namespace MTL {
class Device;
class SamplerState;
class Texture;
}

namespace Fast::Backends {

// Uploads a CPU-owned PICA texture snapshot as RGBA8 and creates its sampler.
// GPU-produced TextureCopy versions are rejected until the ordered Metal copy
// producer registry is available; stale guest bytes are never substituted.
class GfxMetalPicaTextureResource {
  public:
    GfxMetalPicaTextureResource() = default;
    ~GfxMetalPicaTextureResource();

    GfxMetalPicaTextureResource(const GfxMetalPicaTextureResource&) = delete;
    GfxMetalPicaTextureResource& operator=(const GfxMetalPicaTextureResource&) = delete;

    [[nodiscard]] bool Create(
        MTL::Device* device,
        const Renderer3ds::PicaTextureView& texture,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool IsValid() const;
    [[nodiscard]] MTL::Texture* Texture() const;
    [[nodiscard]] MTL::SamplerState* Sampler() const;
    [[nodiscard]] uint32_t Width() const;
    [[nodiscard]] uint32_t Height() const;

  private:
    MTL::Texture* mTexture = nullptr;
    MTL::SamplerState* mSampler = nullptr;
    uint32_t mWidth = 0;
    uint32_t mHeight = 0;
};

} // namespace Fast::Backends
