#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <vector>

#include "fast/renderer3ds/pica_msl_shader.h"

namespace Fast::Renderer3ds {
struct PicaTextureView;
struct PicaDrawView;
}

namespace Fast::Backends {
class GfxMetalPicaDevice;
class GfxMetalPicaTextureCache;
}

namespace MTL {
class ArgumentEncoder;
class Buffer;
class Device;
class Function;
class RenderCommandEncoder;
class Resource;
class SamplerState;
class Texture;
}

namespace Fast::Backends {

// Encodes one shader stage's canonical PICA descriptor set (set zero).
// Storage images use the direct Metal texture-binding path required by the
// iOS MSL backend; other resources use the MSL argument buffer.
class GfxMetalPicaArgumentBuffer {
  public:
    GfxMetalPicaArgumentBuffer() = default;
    ~GfxMetalPicaArgumentBuffer();

    GfxMetalPicaArgumentBuffer(const GfxMetalPicaArgumentBuffer&) = delete;
    GfxMetalPicaArgumentBuffer& operator=(const GfxMetalPicaArgumentBuffer&) = delete;

    [[nodiscard]] bool Initialize(
        MTL::Device* device,
        MTL::Function* function,
        const Renderer3ds::PicaMslShaderArtifact& artifact,
        std::string* error = nullptr);
    void Shutdown();

    [[nodiscard]] bool SetBuffer(
        uint32_t binding, MTL::Buffer* buffer, uint64_t offset = 0);
    [[nodiscard]] bool SetBufferBytes(
        MTL::Device* device,
        uint32_t binding,
        std::span<const uint8_t> bytes,
        std::string* error = nullptr);
    [[nodiscard]] bool SetPicaUniforms(
        MTL::Device* device,
        const Renderer3ds::PicaDrawView& draw,
        std::string* error = nullptr);
    [[nodiscard]] bool SetTexture(uint32_t binding, MTL::Texture* texture);
    [[nodiscard]] bool SetSampler(uint32_t binding, MTL::SamplerState* sampler);
    [[nodiscard]] bool SetNativePicaTexture(
        GfxMetalPicaTextureCache& cache,
        GfxMetalPicaDevice& device,
        const Renderer3ds::PicaTextureView& texture,
        std::string* error = nullptr);
    [[nodiscard]] bool SetStorageTexture(
        MTL::RenderCommandEncoder* renderEncoder,
        uint32_t binding,
        MTL::Texture* texture);

    [[nodiscard]] bool Bind(MTL::RenderCommandEncoder* renderEncoder) const;
    [[nodiscard]] bool IsInitialized() const;
    [[nodiscard]] MTL::Buffer* Buffer() const;

  private:
    [[nodiscard]] const Renderer3ds::PicaNriDescriptorBinding* FindBinding(
        uint32_t binding) const;
    [[nodiscard]] bool TrackResource(MTL::Resource* resource);

    MTL::ArgumentEncoder* mArgumentEncoder = nullptr;
    MTL::Buffer* mArgumentBuffer = nullptr;
    Renderer3ds::PicaMslShaderStage mStage =
        Renderer3ds::PicaMslShaderStage::Vertex;
    std::vector<Renderer3ds::PicaNriDescriptorBinding> mBindings;
    std::vector<MTL::Buffer*> mOwnedBuffers;
    std::vector<MTL::Resource*> mReferencedResources;
    bool mInitialized = false;
};

} // namespace Fast::Backends
