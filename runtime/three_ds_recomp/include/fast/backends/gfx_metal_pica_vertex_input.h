#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "fast/renderer3ds/pica_render_backend.h"

namespace MTL {
class Buffer;
class Device;
class RenderCommandEncoder;
class VertexDescriptor;
}

namespace Fast::Backends {

// Builds Metal-compatible float4 vertex streams from the transient PICA draw
// view. Buffer slot zero is reserved for the shader argument buffer; PICA
// vertex binding N is therefore installed at Metal vertex buffer slot N + 1.
class GfxMetalPicaVertexInput {
  public:
    GfxMetalPicaVertexInput() = default;
    ~GfxMetalPicaVertexInput();

    GfxMetalPicaVertexInput(const GfxMetalPicaVertexInput&) = delete;
    GfxMetalPicaVertexInput& operator=(const GfxMetalPicaVertexInput&) = delete;

    [[nodiscard]] bool Create(
        MTL::Device* device,
        const Renderer3ds::PicaDrawView& draw,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool Bind(MTL::RenderCommandEncoder* encoder) const;
    [[nodiscard]] MTL::VertexDescriptor* Descriptor() const;
    [[nodiscard]] MTL::Buffer* IndexBuffer() const;
    [[nodiscard]] uint32_t IndexCount() const;
    [[nodiscard]] uint32_t VertexCount() const;
    [[nodiscard]] uint32_t InstanceCount() const;
    [[nodiscard]] int32_t BaseVertex() const;
    [[nodiscard]] bool IsIndexed() const;
    [[nodiscard]] bool IndicesAre16Bit() const;
    [[nodiscard]] bool EncodeDraw(
        MTL::RenderCommandEncoder* encoder,
        Renderer3ds::PicaTopology topology,
        std::string* error = nullptr) const;
    [[nodiscard]] bool IsValid() const;

  private:
    struct VertexStream {
        uint32_t Binding = 0;
        MTL::Buffer* Buffer = nullptr;
    };

    std::vector<VertexStream> mStreams;
    MTL::VertexDescriptor* mDescriptor = nullptr;
    MTL::Buffer* mIndexBuffer = nullptr;
    uint32_t mIndexCount = 0;
    uint32_t mVertexCount = 0;
    uint32_t mInstanceCount = 1;
    int32_t mBaseVertex = 0;
    bool mIndexed = false;
    bool mIndicesAre16Bit = false;
    Renderer3ds::PicaTopology mTopology = Renderer3ds::PicaTopology::TriangleList;
};

} // namespace Fast::Backends
