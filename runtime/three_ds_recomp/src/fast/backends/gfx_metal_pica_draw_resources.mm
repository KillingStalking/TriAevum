#include "fast/backends/gfx_metal_pica_draw_resources.h"

#include <algorithm>
#include <array>
#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

bool HasTextureSlot(
    const Renderer3ds::PicaDrawView& draw,
    uint8_t slot) {
    return std::any_of(
        draw.Textures.begin(), draw.Textures.end(),
        [slot](const Renderer3ds::PicaTextureView& texture) {
            return texture.Slot == slot;
        });
}

bool HasDescriptor(
    const Renderer3ds::PicaMslShaderArtifact& artifact,
    uint32_t binding,
    Renderer3ds::PicaNriDescriptorKind kind) {
    return std::any_of(
        artifact.Resources.begin(), artifact.Resources.end(),
        [binding, kind](const Renderer3ds::PicaNriDescriptorBinding& resource) {
            return resource.Binding == binding && resource.Kind == kind;
        });
}

} // namespace

GfxMetalPicaDrawResources::~GfxMetalPicaDrawResources() {
    Reset();
}

bool GfxMetalPicaDrawResources::ValidateStageResources(
    const Renderer3ds::PicaMslShaderArtifact& artifact,
    const Renderer3ds::PicaDrawView& draw,
    std::string* error) {
    const bool vertex =
        artifact.Stage == Renderer3ds::PicaMslShaderStage::Vertex;
    std::array<bool, 3> seenTextureSlots{};
    for (const auto& texture : draw.Textures) {
        if (texture.Slot >= seenTextureSlots.size() ||
            seenTextureSlots[texture.Slot]) {
            SetError(error, "PICA draw contains an invalid or duplicate sampled texture slot");
            return false;
        }
        seenTextureSlots[texture.Slot] = true;
    }
    for (const auto& resource : artifact.Resources) {
        const auto expectedStage = vertex
            ? Renderer3ds::PicaNriShaderStage::Vertex
            : Renderer3ds::PicaNriShaderStage::Fragment;
        if (resource.Stage != expectedStage) {
            SetError(error, "PICA shader artifact contains a descriptor from the wrong shader stage");
            return false;
        }
        if (vertex && resource.Binding == 0U &&
            resource.Kind == Renderer3ds::PicaNriDescriptorKind::ConstantBuffer) {
            continue;
        }
        if (!vertex && resource.Binding == 4U &&
            resource.Kind == Renderer3ds::PicaNriDescriptorKind::ConstantBuffer) {
            continue;
        }
        if (!vertex &&
            resource.Binding >= 1U && resource.Binding <= 3U &&
            resource.Kind == Renderer3ds::PicaNriDescriptorKind::Texture) {
            if (!HasTextureSlot(draw, static_cast<uint8_t>(resource.Binding - 1U))) {
                SetError(error, "PICA fragment shader requires a texture slot absent from this draw");
                return false;
            }
            continue;
        }
        if (!vertex &&
            resource.Binding >= 7U && resource.Binding <= 9U &&
            resource.Kind == Renderer3ds::PicaNriDescriptorKind::Sampler) {
            if (!HasTextureSlot(draw, static_cast<uint8_t>(resource.Binding - 7U))) {
                SetError(error, "PICA fragment shader requires a sampler slot absent from this draw");
                return false;
            }
            continue;
        }
        SetError(
            error,
            "PICA draw declares an extension/storage descriptor not yet supported by the direct Metal draw-resource path");
        return false;
    }

    for (const auto& texture : draw.Textures) {
        if (texture.Slot >= 3U) {
            SetError(error, "PICA draw contains a sampled texture outside native slots 0-2");
            return false;
        }
        const uint32_t textureBinding = 1U + texture.Slot;
        const uint32_t samplerBinding = 7U + texture.Slot;
        const bool hasTexture = HasDescriptor(
            artifact, textureBinding, Renderer3ds::PicaNriDescriptorKind::Texture);
        const bool hasSampler = HasDescriptor(
            artifact, samplerBinding, Renderer3ds::PicaNriDescriptorKind::Sampler);
        if (hasTexture != hasSampler) {
            SetError(error, "PICA shader exposes only half of a native texture/sampler pair");
            return false;
        }
    }
    return true;
}

bool GfxMetalPicaDrawResources::Prepare(
    GfxMetalPicaDevice& device,
    GfxMetalPicaTextureCache& textureCache,
    const Renderer3ds::PicaDrawView& draw,
    const Renderer3ds::PicaMslShaderArtifact& vertexArtifact,
    MTL::Function* vertexFunction,
    const Renderer3ds::PicaMslShaderArtifact& fragmentArtifact,
    MTL::Function* fragmentFunction,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (!device.IsReady() ||
        vertexArtifact.Stage != Renderer3ds::PicaMslShaderStage::Vertex ||
        fragmentArtifact.Stage != Renderer3ds::PicaMslShaderStage::Fragment ||
        vertexFunction == nullptr || fragmentFunction == nullptr) {
        SetError(error, "PICA Metal draw resources require a ready device and matching vertex/fragment shader functions");
        return false;
    }
    if (!ValidateStageResources(vertexArtifact, draw, error) ||
        !ValidateStageResources(fragmentArtifact, draw, error)) {
        Reset();
        return false;
    }

    if (!mVertexArguments.Initialize(
            device.Device(), vertexFunction, vertexArtifact, error) ||
        !mVertexArguments.SetPicaUniforms(device.Device(), draw, error)) {
        Reset();
        return false;
    }
    if (!mFragmentArguments.Initialize(
            device.Device(), fragmentFunction, fragmentArtifact, error) ||
        !mFragmentArguments.SetPicaUniforms(device.Device(), draw, error)) {
        Reset();
        return false;
    }

    for (const auto& texture : draw.Textures) {
        const uint32_t textureBinding = 1U + texture.Slot;
        if (!HasDescriptor(
                fragmentArtifact, textureBinding,
                Renderer3ds::PicaNriDescriptorKind::Texture)) {
            continue;
        }
        if (!mFragmentArguments.SetNativePicaTexture(
                textureCache, device, texture, error)) {
            Reset();
            return false;
        }
    }

    if (!mVertexInput.Create(device.Device(), draw, error)) {
        Reset();
        return false;
    }
    mTopology = draw.Topology;
    mPrepared = true;
    return true;
}

void GfxMetalPicaDrawResources::Reset() {
    mVertexInput.Reset();
    mFragmentArguments.Shutdown();
    mVertexArguments.Shutdown();
    mTopology = Renderer3ds::PicaTopology::TriangleList;
    mPrepared = false;
}

bool GfxMetalPicaDrawResources::Bind(
    MTL::RenderCommandEncoder* encoder) const {
    return mPrepared && encoder != nullptr &&
           mVertexArguments.Bind(encoder) &&
           mFragmentArguments.Bind(encoder) &&
           mVertexInput.Bind(encoder);
}

bool GfxMetalPicaDrawResources::EncodeDraw(
    MTL::RenderCommandEncoder* encoder,
    std::string* error) const {
    if (error != nullptr) {
        error->clear();
    }
    if (!mPrepared || encoder == nullptr) {
        SetError(error, "PICA Metal draw resources are not prepared or encoder is null");
        return false;
    }
    return mVertexInput.EncodeDraw(encoder, mTopology, error);
}

bool GfxMetalPicaDrawResources::IsPrepared() const {
    return mPrepared;
}

} // namespace Fast::Backends
