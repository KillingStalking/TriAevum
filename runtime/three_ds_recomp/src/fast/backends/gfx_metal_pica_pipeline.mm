#include "fast/backends/gfx_metal_pica_pipeline.h"

#include "fast/backends/gfx_metal_pica_depth_stencil.h"
#include "fast/backends/gfx_metal_pica_raster_state.h"

#include <Metal/Metal.hpp>

#include <utility>

namespace Fast::Backends {

GfxMetalPicaPipeline::~GfxMetalPicaPipeline() {
    Reset();
}

bool GfxMetalPicaPipeline::Create(
    MTL::Device* device,
    MTL::Function* vertexFunction,
    MTL::Function* fragmentFunction,
    MTL::VertexDescriptor* vertexDescriptor,
    uint32_t colorPixelFormat,
    uint32_t depthPixelFormat,
    uint32_t sampleCount,
    const Renderer3ds::PicaDrawView* draw,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr || vertexFunction == nullptr ||
        fragmentFunction == nullptr || sampleCount == 0) {
        if (error != nullptr) {
            *error = "Metal PICA pipeline requires a device, vertex/fragment functions and a nonzero sample count";
        }
        return false;
    }

    const Renderer3ds::NativeBlendState defaultBlend{};
    const auto& blend = draw != nullptr ? draw->Blend : defaultBlend;
    const auto logicOperation = draw != nullptr
        ? draw->LogicOperation
        : Renderer3ds::PicaLogicOperation::Copy;
    const uint8_t colorWriteMask =
        draw != nullptr ? draw->ColorWriteMask : 0x0fU;
    if (draw != nullptr &&
        (draw->DepthTestEnabled || draw->DepthWriteEnabled ||
         draw->Stencil.Enabled) && depthPixelFormat == 0U) {
        if (error != nullptr) {
            *error = "PICA depth/stencil state requires a compatible Metal depth attachment format";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::RenderPipelineDescriptor* descriptor =
        MTL::RenderPipelineDescriptor::alloc()->init();
    if (descriptor == nullptr) {
        pool->release();
        if (error != nullptr) {
            *error = "Metal could not allocate a render-pipeline descriptor";
        }
        return false;
    }

    descriptor->setVertexFunction(vertexFunction);
    descriptor->setFragmentFunction(fragmentFunction);
    descriptor->setVertexDescriptor(vertexDescriptor);
    descriptor->setSampleCount(sampleCount);
    auto* colorAttachment = descriptor->colorAttachments()->object(0);
    colorAttachment->setPixelFormat(
        static_cast<MTL::PixelFormat>(colorPixelFormat));
    std::string blendError;
    if (!ConfigurePicaMetalColorAttachment(
            colorAttachment, blend, logicOperation, colorWriteMask,
            &blendError)) {
        descriptor->release();
        pool->release();
        if (error != nullptr) {
            *error = std::move(blendError);
        }
        return false;
    }
    descriptor->setDepthAttachmentPixelFormat(
        static_cast<MTL::PixelFormat>(depthPixelFormat));
    if (depthPixelFormat ==
        static_cast<uint32_t>(MTL::PixelFormatDepth32Float_Stencil8)) {
        descriptor->setStencilAttachmentPixelFormat(
            MTL::PixelFormatDepth32Float_Stencil8);
    }

    NS::Error* pipelineError = nullptr;
    mState = device->newRenderPipelineState(descriptor, &pipelineError);
    descriptor->release();
    if (mState == nullptr) {
        if (error != nullptr) {
            const char* description =
                pipelineError != nullptr &&
                        pipelineError->localizedDescription() != nullptr
                    ? pipelineError->localizedDescription()->utf8String()
                    : nullptr;
            *error = description != nullptr
                ? description
                : "Metal failed to create the PICA render pipeline";
        }
        pool->release();
        return false;
    }

    if (draw != nullptr) {
        GfxMetalPicaDepthStencilState depthStencil;
        if (!depthStencil.Create(
                device, draw->DepthTestEnabled, draw->DepthWriteEnabled,
                draw->DepthCompare, draw->Stencil, error)) {
            Reset();
            pool->release();
            return false;
        }
        mDepthStencilState = depthStencil.State();
        mDepthStencilState->retain();
    }

    mColorPixelFormat = colorPixelFormat;
    mDepthPixelFormat = depthPixelFormat;
    mStencilPixelFormat =
        depthPixelFormat ==
                static_cast<uint32_t>(MTL::PixelFormatDepth32Float_Stencil8)
            ? depthPixelFormat
            : 0U;
    mSampleCount = sampleCount;
    pool->release();
    return true;
}

void GfxMetalPicaPipeline::Reset() {
    if (mDepthStencilState != nullptr) {
        mDepthStencilState->release();
        mDepthStencilState = nullptr;
    }
    if (mState != nullptr) {
        mState->release();
        mState = nullptr;
    }
    mColorPixelFormat = 0;
    mDepthPixelFormat = 0;
    mStencilPixelFormat = 0;
    mSampleCount = 0;
}

bool GfxMetalPicaPipeline::Bind(
    MTL::RenderCommandEncoder* encoder,
    const Renderer3ds::PicaDrawView* draw) const {
    if (encoder == nullptr || mState == nullptr) {
        return false;
    }
    encoder->setRenderPipelineState(mState);
    if (mDepthStencilState != nullptr) {
        encoder->setDepthStencilState(mDepthStencilState);
        encoder->setStencilReferenceValue(
            draw != nullptr ? draw->Stencil.Reference : 0U);
    }
    if (draw != nullptr) {
        return BindPicaMetalRasterState(
            encoder, draw->CullMode, draw->FramebufferFlipped,
            draw->Blend, nullptr);
    }
    return true;
}

bool GfxMetalPicaPipeline::IsValid() const {
    return mState != nullptr;
}

MTL::RenderPipelineState* GfxMetalPicaPipeline::State() const {
    return mState;
}

uint32_t GfxMetalPicaPipeline::ColorPixelFormat() const {
    return mColorPixelFormat;
}

uint32_t GfxMetalPicaPipeline::DepthPixelFormat() const {
    return mDepthPixelFormat;
}

uint32_t GfxMetalPicaPipeline::StencilPixelFormat() const {
    return mStencilPixelFormat;
}

uint32_t GfxMetalPicaPipeline::SampleCount() const {
    return mSampleCount;
}

} // namespace Fast::Backends
