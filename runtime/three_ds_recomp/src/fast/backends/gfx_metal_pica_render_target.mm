#include "fast/backends/gfx_metal_pica_render_target.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, const char* message) {
    if (error != nullptr) {
        *error = message;
    }
}

} // namespace

GfxMetalPicaRenderTarget::~GfxMetalPicaRenderTarget() {
    Reset();
}

bool GfxMetalPicaRenderTarget::Create(
    MTL::Device* device,
    uint32_t width,
    uint32_t height,
    uint32_t colorPixelFormat,
    uint32_t depthPixelFormat,
    uint32_t stencilPixelFormat,
    uint32_t sampleCount,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr || width == 0U || height == 0U ||
        colorPixelFormat == 0U || sampleCount != 1U) {
        SetError(error, "PICA Metal render target requires a device, nonzero extent/color format and single-sample storage");
        return false;
    }
    if (stencilPixelFormat != 0U && depthPixelFormat == 0U) {
        SetError(error, "PICA Metal stencil attachment requires a depth texture");
        return false;
    }
    if (stencilPixelFormat != 0U &&
        stencilPixelFormat != depthPixelFormat) {
        SetError(error, "PICA Metal depth/stencil must use one combined attachment format");
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::TextureDescriptor* colorDescriptor =
        MTL::TextureDescriptor::texture2DDescriptor(
            static_cast<MTL::PixelFormat>(colorPixelFormat),
            width, height, false);
    if (colorDescriptor == nullptr) {
        pool->release();
        SetError(error, "Metal could not allocate a PICA color texture descriptor");
        return false;
    }
    colorDescriptor->setStorageMode(MTL::StorageModePrivate);
    colorDescriptor->setUsage(
        MTL::TextureUsageRenderTarget | MTL::TextureUsageShaderRead);
    mColorTexture = device->newTexture(colorDescriptor);
    if (mColorTexture == nullptr) {
        pool->release();
        Reset();
        SetError(error, "Metal could not allocate the PICA color render target");
        return false;
    }

    if (depthPixelFormat != 0U) {
        MTL::TextureDescriptor* depthDescriptor =
            MTL::TextureDescriptor::texture2DDescriptor(
                static_cast<MTL::PixelFormat>(depthPixelFormat),
                width, height, false);
        if (depthDescriptor == nullptr) {
            pool->release();
            Reset();
            SetError(error, "Metal could not allocate a PICA depth texture descriptor");
            return false;
        }
        depthDescriptor->setStorageMode(MTL::StorageModePrivate);
        depthDescriptor->setUsage(MTL::TextureUsageRenderTarget);
        mDepthTexture = device->newTexture(depthDescriptor);
        if (mDepthTexture == nullptr) {
            pool->release();
            Reset();
            SetError(error, "Metal could not allocate the PICA depth render target");
            return false;
        }
    }

    pool->release();
    mWidth = width;
    mHeight = height;
    mColorPixelFormat = colorPixelFormat;
    mDepthPixelFormat = depthPixelFormat;
    mStencilPixelFormat = stencilPixelFormat;
    mSampleCount = sampleCount;
    return true;
}

void GfxMetalPicaRenderTarget::Reset() {
    End();
    if (mDepthTexture != nullptr) {
        mDepthTexture->release();
        mDepthTexture = nullptr;
    }
    if (mColorTexture != nullptr) {
        mColorTexture->release();
        mColorTexture = nullptr;
    }
    mWidth = 0;
    mHeight = 0;
    mColorPixelFormat = 0;
    mDepthPixelFormat = 0;
    mStencilPixelFormat = 0;
    mSampleCount = 0;
    mHasBeenInitialized = false;
}

bool GfxMetalPicaRenderTarget::Begin(
    MTL::CommandBuffer* commandBuffer,
    bool clearColor,
    bool clearDepth,
    bool clearStencil,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (IsActive()) {
        SetError(error, "PICA Metal render target is already active");
        return false;
    }
    if (!IsValid() || commandBuffer == nullptr) {
        SetError(error, "PICA Metal render target requires valid textures and a command buffer");
        return false;
    }
    const bool effectiveClearColor = clearColor || !mHasBeenInitialized;
    const bool effectiveClearDepth =
        clearDepth || (!mHasBeenInitialized && mDepthTexture != nullptr);
    const bool effectiveClearStencil =
        clearStencil || (!mHasBeenInitialized && mStencilPixelFormat != 0U);
    if (effectiveClearDepth && mDepthTexture == nullptr) {
        SetError(error, "PICA Metal render target has no depth attachment to clear");
        return false;
    }
    if (effectiveClearStencil && mStencilPixelFormat == 0U) {
        SetError(error, "PICA Metal render target has no stencil attachment to clear");
        return false;
    }

    mAutoreleasePool = NS::AutoreleasePool::alloc()->init();
    MTL::RenderPassDescriptor* pass =
        MTL::RenderPassDescriptor::renderPassDescriptor();
    if (pass == nullptr) {
        End();
        SetError(error, "Metal could not allocate a PICA render-pass descriptor");
        return false;
    }

    auto* color = pass->colorAttachments()->object(0);
    color->setTexture(mColorTexture);
    color->setLoadAction(
        effectiveClearColor ? MTL::LoadActionClear : MTL::LoadActionLoad);
    color->setStoreAction(MTL::StoreActionStore);
    color->setClearColor(MTL::ClearColor::Make(0.0, 0.0, 0.0, 0.0));

    if (mDepthTexture != nullptr) {
        auto* depth = pass->depthAttachment();
        depth->setTexture(mDepthTexture);
        depth->setLoadAction(
            effectiveClearDepth ? MTL::LoadActionClear : MTL::LoadActionLoad);
        depth->setStoreAction(MTL::StoreActionStore);
        depth->setClearDepth(1.0);
    }
    if (mStencilPixelFormat != 0U) {
        auto* stencil = pass->stencilAttachment();
        stencil->setTexture(mDepthTexture);
        stencil->setLoadAction(
            effectiveClearStencil ? MTL::LoadActionClear : MTL::LoadActionLoad);
        stencil->setStoreAction(MTL::StoreActionStore);
        stencil->setClearStencil(0U);
    }

    mEncoder = commandBuffer->renderCommandEncoder(pass);
    if (mEncoder == nullptr) {
        End();
        SetError(error, "Metal could not create a PICA offscreen render encoder");
        return false;
    }
    return true;
}

MTL::RenderCommandEncoder* GfxMetalPicaRenderTarget::Encoder() const {
    return mEncoder;
}

void GfxMetalPicaRenderTarget::End() {
    if (mEncoder != nullptr) {
        mEncoder->endEncoding();
        mEncoder = nullptr;
        mHasBeenInitialized = true;
    }
    if (mAutoreleasePool != nullptr) {
        mAutoreleasePool->release();
        mAutoreleasePool = nullptr;
    }
}

bool GfxMetalPicaRenderTarget::IsValid() const {
    return mColorTexture != nullptr &&
           (mDepthPixelFormat == 0U || mDepthTexture != nullptr);
}

bool GfxMetalPicaRenderTarget::IsActive() const {
    return mEncoder != nullptr && mAutoreleasePool != nullptr;
}

MTL::Texture* GfxMetalPicaRenderTarget::ColorTexture() const {
    return mColorTexture;
}

MTL::Texture* GfxMetalPicaRenderTarget::DepthTexture() const {
    return mDepthTexture;
}

uint32_t GfxMetalPicaRenderTarget::Width() const {
    return mWidth;
}

uint32_t GfxMetalPicaRenderTarget::Height() const {
    return mHeight;
}

uint32_t GfxMetalPicaRenderTarget::ColorPixelFormat() const {
    return mColorPixelFormat;
}

uint32_t GfxMetalPicaRenderTarget::DepthPixelFormat() const {
    return mDepthPixelFormat;
}

uint32_t GfxMetalPicaRenderTarget::StencilPixelFormat() const {
    return mStencilPixelFormat;
}

uint32_t GfxMetalPicaRenderTarget::SampleCount() const {
    return mSampleCount;
}

} // namespace Fast::Backends
