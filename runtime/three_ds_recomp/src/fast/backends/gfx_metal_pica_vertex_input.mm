#include "fast/backends/gfx_metal_pica_vertex_input.h"

#include <Metal/Metal.hpp>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstring>
#include <limits>

namespace Fast::Backends {
namespace {

uint32_t ScalarSize(Renderer3ds::PicaVertexFormat format) {
    switch (format) {
        case Renderer3ds::PicaVertexFormat::SignedByte:
        case Renderer3ds::PicaVertexFormat::UnsignedByte:
            return 1U;
        case Renderer3ds::PicaVertexFormat::SignedShort:
            return 2U;
        case Renderer3ds::PicaVertexFormat::Float:
            return 4U;
    }
    return 0U;
}

float DecodeScalar(Renderer3ds::PicaVertexFormat format, const uint8_t* source) {
    switch (format) {
        case Renderer3ds::PicaVertexFormat::SignedByte: {
            int8_t value = 0;
            std::memcpy(&value, source, sizeof(value));
            return static_cast<float>(value);
        }
        case Renderer3ds::PicaVertexFormat::UnsignedByte:
            return static_cast<float>(*source);
        case Renderer3ds::PicaVertexFormat::SignedShort: {
            int16_t value = 0;
            std::memcpy(&value, source, sizeof(value));
            return static_cast<float>(value);
        }
        case Renderer3ds::PicaVertexFormat::Float: {
            float value = 0.0F;
            std::memcpy(&value, source, sizeof(value));
            return value;
        }
    }
    return 0.0F;
}

void SetError(std::string* error, const char* message) {
    if (error != nullptr) {
        *error = message;
    }
}

} // namespace

GfxMetalPicaVertexInput::~GfxMetalPicaVertexInput() {
    Reset();
}

bool GfxMetalPicaVertexInput::Create(
    MTL::Device* device,
    const Renderer3ds::PicaDrawView& draw,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr || draw.VertexCount == 0 ||
        draw.VertexBindings.empty() || draw.VertexAttributes.empty()) {
        SetError(error, "PICA Metal vertex input requires a device, streams, attributes and vertices");
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    mDescriptor = MTL::VertexDescriptor::alloc()->init();
    if (mDescriptor == nullptr) {
        pool->release();
        SetError(error, "Metal could not allocate a vertex descriptor");
        return false;
    }

    for (size_t i = 0; i < draw.VertexBindings.size(); ++i) {
        const auto& binding = draw.VertexBindings[i];
        if (binding.ByteStride == 0 ||
            std::any_of(draw.VertexBindings.begin(),
                        draw.VertexBindings.begin() + static_cast<std::ptrdiff_t>(i),
                        [&](const auto& previous) {
                            return previous.Binding == binding.Binding;
                        })) {
            pool->release();
            Reset();
            SetError(error, "PICA Metal vertex input contains an invalid or duplicate binding");
            return false;
        }
    }

    for (size_t i = 0; i < draw.VertexAttributes.size(); ++i) {
        const auto& attribute = draw.VertexAttributes[i];
        const auto binding = std::find_if(
            draw.VertexBindings.begin(), draw.VertexBindings.end(),
            [&](const auto& candidate) {
                return candidate.Binding == attribute.Binding;
            });
        const uint32_t scalarSize = ScalarSize(attribute.Format);
        if (binding == draw.VertexBindings.end() || attribute.Location >= 31U ||
            attribute.ComponentCount == 0 || attribute.ComponentCount > 4 ||
            scalarSize == 0 ||
            static_cast<uint32_t>(attribute.ByteOffset) +
                    scalarSize * attribute.ComponentCount >
                binding->ByteStride ||
            std::any_of(draw.VertexAttributes.begin(),
                        draw.VertexAttributes.begin() + static_cast<std::ptrdiff_t>(i),
                        [&](const auto& previous) {
                            return previous.Location == attribute.Location;
                        })) {
            pool->release();
            Reset();
            SetError(error, "PICA Metal vertex input contains an invalid attribute");
            return false;
        }
    }

    bool hasInstanceStream = false;
    uint32_t instanceCount = std::numeric_limits<uint32_t>::max();
    for (const auto& binding : draw.VertexBindings) {
        std::vector<Renderer3ds::PicaVertexAttributeView> attributes;
        for (const auto& attribute : draw.VertexAttributes) {
            if (attribute.Binding == binding.Binding) {
                attributes.push_back(attribute);
            }
        }
        if (attributes.empty()) {
            continue;
        }
        if (binding.Binding >= 30U || binding.Bytes.empty() ||
            binding.Bytes.size() % binding.ByteStride != 0U) {
            pool->release();
            Reset();
            SetError(error, "PICA Metal vertex stream has an unsupported slot or invalid byte range");
            return false;
        }
        std::sort(attributes.begin(), attributes.end(),
                  [](const auto& left, const auto& right) {
                      return left.Location < right.Location;
                  });
        const uint32_t packedStride =
            static_cast<uint32_t>(attributes.size()) * 4U * sizeof(float);
        const size_t elementCount = binding.Bytes.size() / binding.ByteStride;
        if (elementCount == 0 ||
            elementCount > std::numeric_limits<size_t>::max() / packedStride) {
            pool->release();
            Reset();
            SetError(error, "PICA Metal vertex stream size overflows");
            return false;
        }

        std::vector<uint8_t> packed(elementCount * packedStride);
        for (size_t element = 0; element < elementCount; ++element) {
            const uint8_t* sourceElement =
                binding.Bytes.data() + element * binding.ByteStride;
            uint8_t* packedElement = packed.data() + element * packedStride;
            for (size_t attributeIndex = 0;
                 attributeIndex < attributes.size(); ++attributeIndex) {
                const auto& attribute = attributes[attributeIndex];
                std::array<float, 4> value{0.0F, 0.0F, 0.0F, 1.0F};
                const uint32_t scalarSize = ScalarSize(attribute.Format);
                for (uint32_t component = 0;
                     component < attribute.ComponentCount; ++component) {
                    value[component] = DecodeScalar(
                        attribute.Format,
                        sourceElement + attribute.ByteOffset +
                            component * scalarSize);
                }
                std::memcpy(
                    packedElement + attributeIndex * 4U * sizeof(float),
                    value.data(), sizeof(value));
            }
        }

        MTL::Buffer* buffer = device->newBuffer(
            packed.data(), packed.size(), MTL::ResourceStorageModeShared);
        if (buffer == nullptr) {
            pool->release();
            Reset();
            SetError(error, "Metal could not allocate a packed PICA vertex stream");
            return false;
        }
        mStreams.push_back({binding.Binding, buffer});

        const NS::UInteger metalSlot =
            static_cast<NS::UInteger>(binding.Binding) + 1U;
        auto* layout = mDescriptor->layouts()->object(metalSlot);
        layout->setStride(packedStride);
        layout->setStepFunction(
            binding.PerInstance
                ? MTL::VertexStepFunctionPerInstance
                : MTL::VertexStepFunctionPerVertex);
        layout->setStepRate(1);

        for (size_t attributeIndex = 0;
             attributeIndex < attributes.size(); ++attributeIndex) {
            const auto& attribute = attributes[attributeIndex];
            auto* metalAttribute =
                mDescriptor->attributes()->object(attribute.Location);
            metalAttribute->setFormat(MTL::VertexFormatFloat4);
            metalAttribute->setOffset(
                attributeIndex * 4U * sizeof(float));
            metalAttribute->setBufferIndex(metalSlot);
        }

        if (binding.PerInstance) {
            hasInstanceStream = true;
            instanceCount = std::min(
                instanceCount, static_cast<uint32_t>(std::min<size_t>(
                    elementCount, std::numeric_limits<uint32_t>::max())));
        }
    }

    if (mStreams.empty()) {
        pool->release();
        Reset();
        SetError(error, "PICA Metal vertex input has no usable streams");
        return false;
    }

    mInstanceCount = hasInstanceStream ? instanceCount : 1U;
    if (mInstanceCount == 0U) {
        pool->release();
        Reset();
        SetError(error, "PICA Metal instance stream contains no instances");
        return false;
    }
    mVertexCount = draw.VertexCount;
    mBaseVertex = draw.Indexed ? draw.BaseVertex : 0;
    mIndexed = draw.Indexed;
    mIndicesAre16Bit = draw.Indexed && draw.IndicesAre16Bit;
    mTopology = draw.Topology;

    if (draw.Topology == Renderer3ds::PicaTopology::GeometryShader) {
        pool->release();
        Reset();
        SetError(error, "Metal does not support the PICA geometry-shader topology");
        return false;
    }

    if (draw.Topology == Renderer3ds::PicaTopology::TriangleFan) {
        if (draw.VertexCount < 3U ||
            static_cast<uint64_t>(draw.VertexCount - 2U) >
                std::numeric_limits<uint32_t>::max() / 3U) {
            pool->release();
            Reset();
            SetError(error, "PICA triangle fan has an invalid index count");
            return false;
        }
        const uint32_t sourceIndexSize =
            draw.Indexed ? (draw.IndicesAre16Bit ? 2U : 4U) : 0U;
        const uint64_t sourceBytes =
            static_cast<uint64_t>(draw.VertexCount) * sourceIndexSize;
        if (draw.Indexed &&
            (draw.IndexBytes.empty() || sourceBytes > draw.IndexBytes.size())) {
            pool->release();
            Reset();
            SetError(error, "PICA triangle-fan index data is shorter than the draw count");
            return false;
        }

        std::vector<uint32_t> sourceIndices(draw.VertexCount);
        for (uint32_t index = 0; index < draw.VertexCount; ++index) {
            if (!draw.Indexed) {
                sourceIndices[index] = index;
            } else if (draw.IndicesAre16Bit) {
                uint16_t value = 0;
                std::memcpy(&value, draw.IndexBytes.data() +
                    static_cast<size_t>(index) * sizeof(value), sizeof(value));
                sourceIndices[index] = value;
            } else {
                uint32_t value = 0;
                std::memcpy(&value, draw.IndexBytes.data() +
                    static_cast<size_t>(index) * sizeof(value), sizeof(value));
                sourceIndices[index] = value;
            }
        }

        std::vector<uint32_t> fanIndices;
        fanIndices.reserve(static_cast<size_t>(draw.VertexCount - 2U) * 3U);
        for (uint32_t index = 1; index + 1U < draw.VertexCount; ++index) {
            fanIndices.push_back(sourceIndices[0]);
            fanIndices.push_back(sourceIndices[index]);
            fanIndices.push_back(sourceIndices[index + 1U]);
        }
        mIndexBuffer = device->newBuffer(
            fanIndices.data(), fanIndices.size() * sizeof(uint32_t),
            MTL::ResourceStorageModeShared);
        if (mIndexBuffer == nullptr) {
            pool->release();
            Reset();
            SetError(error, "Metal could not allocate the expanded PICA triangle-fan index buffer");
            return false;
        }
        mIndexed = true;
        mIndicesAre16Bit = false;
        mIndexCount = static_cast<uint32_t>(fanIndices.size());
    } else if (mIndexed) {
        const uint32_t indexSize = draw.IndicesAre16Bit ? 2U : 4U;
        const uint64_t requiredBytes =
            static_cast<uint64_t>(draw.VertexCount) * indexSize;
        if (draw.IndexBytes.empty() ||
            requiredBytes > draw.IndexBytes.size()) {
            pool->release();
            Reset();
            SetError(error, "PICA Metal index data is shorter than the draw count");
            return false;
        }
        mIndexBuffer = device->newBuffer(
            draw.IndexBytes.data(), requiredBytes,
            MTL::ResourceStorageModeShared);
        if (mIndexBuffer == nullptr) {
            pool->release();
            Reset();
            SetError(error, "Metal could not allocate the PICA index buffer");
            return false;
        }
        mIndexCount = draw.VertexCount;
    }

    pool->release();
    return true;
}

void GfxMetalPicaVertexInput::Reset() {
    for (auto& stream : mStreams) {
        if (stream.Buffer != nullptr) {
            stream.Buffer->release();
        }
    }
    mStreams.clear();
    if (mIndexBuffer != nullptr) {
        mIndexBuffer->release();
        mIndexBuffer = nullptr;
    }
    if (mDescriptor != nullptr) {
        mDescriptor->release();
        mDescriptor = nullptr;
    }
    mIndexCount = 0;
    mVertexCount = 0;
    mInstanceCount = 1;
    mBaseVertex = 0;
    mIndexed = false;
    mIndicesAre16Bit = false;
    mTopology = Renderer3ds::PicaTopology::TriangleList;
}

bool GfxMetalPicaVertexInput::Bind(MTL::RenderCommandEncoder* encoder) const {
    if (encoder == nullptr || !IsValid()) {
        return false;
    }
    for (const auto& stream : mStreams) {
        encoder->setVertexBuffer(
            stream.Buffer, 0, static_cast<NS::UInteger>(stream.Binding) + 1U);
    }
    return true;
}

MTL::VertexDescriptor* GfxMetalPicaVertexInput::Descriptor() const {
    return mDescriptor;
}

MTL::Buffer* GfxMetalPicaVertexInput::IndexBuffer() const {
    return mIndexBuffer;
}

uint32_t GfxMetalPicaVertexInput::IndexCount() const {
    return mIndexCount;
}

uint32_t GfxMetalPicaVertexInput::VertexCount() const {
    return mVertexCount;
}

uint32_t GfxMetalPicaVertexInput::InstanceCount() const {
    return mInstanceCount;
}

int32_t GfxMetalPicaVertexInput::BaseVertex() const {
    return mBaseVertex;
}

bool GfxMetalPicaVertexInput::IsIndexed() const {
    return mIndexed;
}

bool GfxMetalPicaVertexInput::IndicesAre16Bit() const {
    return mIndicesAre16Bit;
}

bool GfxMetalPicaVertexInput::EncodeDraw(
    MTL::RenderCommandEncoder* encoder,
    Renderer3ds::PicaTopology topology,
    std::string* error) const {
    if (error != nullptr) {
        error->clear();
    }
    if (encoder == nullptr || !IsValid()) {
        SetError(error, "PICA Metal draw has no valid encoder or vertex input");
        return false;
    }
    if (topology != mTopology) {
        SetError(error, "PICA Metal draw topology differs from the prepared vertex input");
        return false;
    }

    MTL::PrimitiveType primitive = MTL::PrimitiveTypeTriangle;
    switch (topology) {
        case Renderer3ds::PicaTopology::TriangleList:
        case Renderer3ds::PicaTopology::TriangleFan:
            primitive = MTL::PrimitiveTypeTriangle;
            break;
        case Renderer3ds::PicaTopology::TriangleStrip:
            primitive = MTL::PrimitiveTypeTriangleStrip;
            break;
        case Renderer3ds::PicaTopology::GeometryShader:
            SetError(error, "Metal does not support the PICA geometry-shader topology");
            return false;
    }

    if (mIndexed) {
        encoder->drawIndexedPrimitives(
            primitive, mIndexCount,
            mIndicesAre16Bit ? MTL::IndexTypeUInt16 : MTL::IndexTypeUInt32,
            mIndexBuffer, 0, mInstanceCount, mBaseVertex, 0);
    } else {
        encoder->drawPrimitives(
            primitive, 0, mVertexCount, mInstanceCount, 0);
    }
    return true;
}

bool GfxMetalPicaVertexInput::IsValid() const {
    return mDescriptor != nullptr && !mStreams.empty() &&
           mVertexCount != 0 &&
           (!mIndexed || (mIndexBuffer != nullptr && mIndexCount != 0));
}

} // namespace Fast::Backends
