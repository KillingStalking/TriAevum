#include "fast/backends/gfx_metal_pica_argument_buffer.h"

#include "fast/backends/gfx_metal_pica_device.h"
#include "fast/backends/gfx_metal_pica_texture_cache.h"
#include "fast/renderer3ds/pica_render_backend.h"

#include <Metal/Metal.hpp>

#include <algorithm>
#include <new>

namespace Fast::Backends {

GfxMetalPicaArgumentBuffer::~GfxMetalPicaArgumentBuffer() {
    Shutdown();
}

bool GfxMetalPicaArgumentBuffer::Initialize(
    MTL::Device* device,
    MTL::Function* function,
    const Renderer3ds::PicaMslShaderArtifact& artifact,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (mInitialized) {
        if (error != nullptr) {
            *error = "PICA Metal argument buffer is already initialized";
        }
        return false;
    }
    if (device == nullptr || function == nullptr) {
        if (error != nullptr) {
            *error = "PICA Metal argument buffer requires a device and shader function";
        }
        return false;
    }

    mStage = artifact.Stage;
    mBindings = artifact.Resources;
    const bool hasArgumentResources = std::any_of(
        mBindings.begin(), mBindings.end(),
        [](const Renderer3ds::PicaNriDescriptorBinding& binding) {
            return binding.Kind != Renderer3ds::PicaNriDescriptorKind::StorageTexture;
        });
    if (!hasArgumentResources) {
        mInitialized = true;
        return true;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    mArgumentEncoder = function->newArgumentEncoder(0);
    if (mArgumentEncoder == nullptr) {
        pool->release();
        Shutdown();
        if (error != nullptr) {
            *error = "MSL function does not expose the PICA descriptor-set argument buffer";
        }
        return false;
    }

    const NS::UInteger length = mArgumentEncoder->encodedLength();
    if (length == 0) {
        pool->release();
        Shutdown();
        if (error != nullptr) {
            *error = "MSL argument encoder reported an empty descriptor buffer";
        }
        return false;
    }

    mArgumentBuffer = device->newBuffer(length, MTL::ResourceStorageModeShared);
    if (mArgumentBuffer == nullptr) {
        pool->release();
        Shutdown();
        if (error != nullptr) {
            *error = "Metal could not allocate the PICA argument buffer";
        }
        return false;
    }
    mArgumentEncoder->setArgumentBuffer(mArgumentBuffer, 0);
    mInitialized = true;
    pool->release();
    return true;
}

void GfxMetalPicaArgumentBuffer::Shutdown() {
    if (mArgumentBuffer != nullptr) {
        mArgumentBuffer->release();
        mArgumentBuffer = nullptr;
    }
    for (MTL::Buffer* buffer : mOwnedBuffers) {
        if (buffer != nullptr) {
            buffer->release();
        }
    }
    mOwnedBuffers.clear();
    if (mArgumentEncoder != nullptr) {
        mArgumentEncoder->release();
        mArgumentEncoder = nullptr;
    }
    for (MTL::Resource* resource : mReferencedResources) {
        if (resource != nullptr) {
            resource->release();
        }
    }
    mReferencedResources.clear();
    mBindings.clear();
    mInitialized = false;
}

const Renderer3ds::PicaNriDescriptorBinding*
GfxMetalPicaArgumentBuffer::FindBinding(uint32_t binding) const {
    const auto found = std::find_if(
        mBindings.begin(), mBindings.end(),
        [binding](const Renderer3ds::PicaNriDescriptorBinding& candidate) {
            return candidate.Binding == binding && candidate.Stage == (
                mStage == Renderer3ds::PicaMslShaderStage::Vertex
                    ? Renderer3ds::PicaNriShaderStage::Vertex
                    : Renderer3ds::PicaNriShaderStage::Fragment);
        });
    return found == mBindings.end() ? nullptr : &*found;
}

bool GfxMetalPicaArgumentBuffer::TrackResource(
    MTL::Resource* resource) {
    if (resource == nullptr) {
        return false;
    }
    if (std::find(mReferencedResources.begin(),
                  mReferencedResources.end(), resource) !=
        mReferencedResources.end()) {
        return true;
    }
    resource->retain();
    try {
        mReferencedResources.push_back(resource);
    } catch (const std::bad_alloc&) {
        resource->release();
        return false;
    }
    return true;
}

bool GfxMetalPicaArgumentBuffer::SetBuffer(
    uint32_t binding, MTL::Buffer* buffer, uint64_t offset) {
    const auto* descriptor = FindBinding(binding);
    if (!mInitialized || mArgumentEncoder == nullptr || buffer == nullptr ||
        descriptor == nullptr ||
        (descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::ConstantBuffer &&
         descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::StructuredBuffer)) {
        return false;
    }
    mArgumentEncoder->setBuffer(buffer, static_cast<NS::UInteger>(offset), binding);
    return TrackResource(buffer);
}

bool GfxMetalPicaArgumentBuffer::SetBufferBytes(
    MTL::Device* device,
    uint32_t binding,
    std::span<const uint8_t> bytes,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    const auto* descriptor = FindBinding(binding);
    if (!mInitialized || device == nullptr || bytes.empty() ||
        descriptor == nullptr ||
        (descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::ConstantBuffer &&
         descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::StructuredBuffer)) {
        if (error != nullptr) {
            *error = "PICA Metal uniform upload requires a declared buffer binding and nonempty bytes";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::Buffer* buffer = device->newBuffer(
        bytes.data(), bytes.size(), MTL::ResourceStorageModeShared);
    pool->release();
    if (buffer == nullptr) {
        if (error != nullptr) {
            *error = "Metal could not allocate the PICA uniform buffer";
        }
        return false;
    }

    if (!SetBuffer(binding, buffer, 0)) {
        buffer->release();
        if (error != nullptr) {
            *error = "Metal rejected the PICA uniform buffer binding";
        }
        return false;
    }
    try {
        mOwnedBuffers.push_back(buffer);
    } catch (const std::bad_alloc&) {
        buffer->release();
        if (error != nullptr) {
            *error = "Metal PICA uniform ownership allocation failed";
        }
        return false;
    }
    return true;
}

bool GfxMetalPicaArgumentBuffer::SetPicaUniforms(
    MTL::Device* device,
    const Renderer3ds::PicaDrawView& draw,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!mInitialized || device == nullptr) {
        if (error != nullptr) {
            *error = "PICA Metal uniform binding requires an initialized argument buffer and device";
        }
        return false;
    }

    const uint32_t binding =
        mStage == Renderer3ds::PicaMslShaderStage::Vertex ? 0U : 4U;
    const auto* descriptor = FindBinding(binding);
    if (descriptor == nullptr) {
        return true;
    }
    if (descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::ConstantBuffer) {
        if (error != nullptr) {
            *error = "canonical PICA stage-uniform binding is not a constant buffer";
        }
        return false;
    }

    const auto bytes =
        mStage == Renderer3ds::PicaMslShaderStage::Vertex
            ? draw.VertexUniformBytes
            : draw.FragmentUniformBytes;
    if (bytes.empty()) {
        if (error != nullptr) {
            *error = "PICA shader declares a stage uniform buffer but the draw supplied no uniform bytes";
        }
        return false;
    }
    return SetBufferBytes(device, binding, bytes, error);
}

bool GfxMetalPicaArgumentBuffer::SetTexture(
    uint32_t binding, MTL::Texture* texture) {
    const auto* descriptor = FindBinding(binding);
    if (!mInitialized || mArgumentEncoder == nullptr || texture == nullptr ||
        descriptor == nullptr ||
        descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::Texture) {
        return false;
    }
    mArgumentEncoder->setTexture(texture, binding);
    return TrackResource(texture);
}

bool GfxMetalPicaArgumentBuffer::SetSampler(
    uint32_t binding, MTL::SamplerState* sampler) {
    const auto* descriptor = FindBinding(binding);
    if (!mInitialized || mArgumentEncoder == nullptr || sampler == nullptr ||
        descriptor == nullptr ||
        descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::Sampler) {
        return false;
    }
    mArgumentEncoder->setSamplerState(sampler, binding);
    return true;
}

bool GfxMetalPicaArgumentBuffer::SetNativePicaTexture(
    GfxMetalPicaTextureCache& cache,
    GfxMetalPicaDevice& device,
    const Renderer3ds::PicaTextureView& texture,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!mInitialized ||
        mStage != Renderer3ds::PicaMslShaderStage::Fragment ||
        texture.Slot >= 3U) {
        if (error != nullptr) {
            *error = "native PICA sampled textures require a fragment argument buffer and slot 0-2";
        }
        return false;
    }

    const uint32_t textureBinding = 1U + texture.Slot;
    const uint32_t samplerBinding = 7U + texture.Slot;
    const auto* textureDescriptor = FindBinding(textureBinding);
    const auto* samplerDescriptor = FindBinding(samplerBinding);
    if (textureDescriptor == nullptr ||
        textureDescriptor->Kind != Renderer3ds::PicaNriDescriptorKind::Texture ||
        samplerDescriptor == nullptr ||
        samplerDescriptor->Kind != Renderer3ds::PicaNriDescriptorKind::Sampler) {
        if (error != nullptr) {
            *error = "translated PICA shader does not expose the canonical texture/sampler binding pair";
        }
        return false;
    }

    GfxMetalPicaTextureResource* resource =
        cache.Resolve(device, texture, error);
    if (resource == nullptr || !resource->IsValid()) {
        return false;
    }
    if (!SetTexture(textureBinding, resource->Texture()) ||
        !SetSampler(samplerBinding, resource->Sampler())) {
        if (error != nullptr) {
            *error = "Metal could not encode the canonical PICA texture/sampler pair";
        }
        return false;
    }
    return true;
}

bool GfxMetalPicaArgumentBuffer::SetStorageTexture(
    MTL::RenderCommandEncoder* renderEncoder,
    uint32_t binding,
    MTL::Texture* texture) {
    const auto* descriptor = FindBinding(binding);
    if (!mInitialized || renderEncoder == nullptr || texture == nullptr ||
        descriptor == nullptr ||
        descriptor->Kind != Renderer3ds::PicaNriDescriptorKind::StorageTexture ||
        !TrackResource(texture)) {
        return false;
    }
    if (mStage == Renderer3ds::PicaMslShaderStage::Vertex) {
        renderEncoder->useResource(
            texture, MTL::ResourceUsageRead | MTL::ResourceUsageWrite,
            MTL::RenderStageVertex);
        renderEncoder->setVertexTexture(texture, binding);
    } else {
        renderEncoder->useResource(
            texture, MTL::ResourceUsageRead | MTL::ResourceUsageWrite,
            MTL::RenderStageFragment);
        renderEncoder->setFragmentTexture(texture, binding);
    }
    return true;
}

bool GfxMetalPicaArgumentBuffer::Bind(
    MTL::RenderCommandEncoder* renderEncoder) const {
    if (!mInitialized || renderEncoder == nullptr) {
        return false;
    }
    const MTL::RenderStages stages =
        mStage == Renderer3ds::PicaMslShaderStage::Vertex
            ? MTL::RenderStageVertex
            : MTL::RenderStageFragment;
    for (MTL::Resource* resource : mReferencedResources) {
        renderEncoder->useResource(resource, MTL::ResourceUsageRead, stages);
    }
    if (mArgumentBuffer == nullptr) {
        return true;
    }
    if (mStage == Renderer3ds::PicaMslShaderStage::Vertex) {
        renderEncoder->setVertexBuffer(mArgumentBuffer, 0, 0);
    } else {
        renderEncoder->setFragmentBuffer(mArgumentBuffer, 0, 0);
    }
    return true;
}

bool GfxMetalPicaArgumentBuffer::IsInitialized() const {
    return mInitialized;
}

MTL::Buffer* GfxMetalPicaArgumentBuffer::Buffer() const {
    return mArgumentBuffer;
}

} // namespace Fast::Backends
