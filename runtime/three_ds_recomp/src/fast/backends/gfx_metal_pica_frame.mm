#include "fast/backends/gfx_metal_pica_frame.h"

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>

namespace Fast::Backends {

GfxMetalPicaFrame::~GfxMetalPicaFrame() {
    Cancel();
}

bool GfxMetalPicaFrame::Begin(
    GfxMetalPicaDevice& device,
    GfxMetalPicaClearColor clearColor,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (IsActive()) {
        if (error != nullptr) {
            *error = "Metal PICA frame is already active";
        }
        return false;
    }
    if (!device.IsReady()) {
        if (error != nullptr) {
            *error = "Metal PICA frame requires an initialized device";
        }
        return false;
    }

    mAutoreleasePool = NS::AutoreleasePool::alloc()->init();
    mDrawable = device.Layer()->nextDrawable();
    if (mDrawable == nullptr) {
        Cancel();
        if (error != nullptr) {
            *error = "CAMetalLayer did not provide a drawable";
        }
        return false;
    }

    mCommandBuffer = device.CommandQueue()->commandBuffer();
    if (mCommandBuffer == nullptr) {
        Cancel();
        if (error != nullptr) {
            *error = "Metal command queue did not create a command buffer";
        }
        return false;
    }

    MTL::RenderPassDescriptor* renderPass =
        MTL::RenderPassDescriptor::renderPassDescriptor();
    if (renderPass == nullptr) {
        Cancel();
        if (error != nullptr) {
            *error = "Metal could not allocate a render pass descriptor";
        }
        return false;
    }

    MTL::RenderPassColorAttachmentDescriptor* colorAttachment =
        renderPass->colorAttachments()->object(0);
    colorAttachment->setTexture(mDrawable->texture());
    colorAttachment->setLoadAction(MTL::LoadActionClear);
    colorAttachment->setStoreAction(MTL::StoreActionStore);
    colorAttachment->setClearColor(MTL::ClearColor::Make(
        clearColor.Red, clearColor.Green, clearColor.Blue, clearColor.Alpha));

    mEncoder = mCommandBuffer->renderCommandEncoder(renderPass);
    if (mEncoder == nullptr) {
        Cancel();
        if (error != nullptr) {
            *error = "Metal could not create a render command encoder";
        }
        return false;
    }
    return true;
}

MTL::RenderCommandEncoder* GfxMetalPicaFrame::Encoder() const {
    return mEncoder;
}

bool GfxMetalPicaFrame::EndAndPresent(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!IsActive()) {
        if (error != nullptr) {
            *error = "Metal PICA frame is not active";
        }
        return false;
    }

    mEncoder->endEncoding();
    mCommandBuffer->presentDrawable(mDrawable);
    mCommandBuffer->commit();
    mEncoder = nullptr;
    mCommandBuffer = nullptr;
    mDrawable = nullptr;
    mAutoreleasePool->release();
    mAutoreleasePool = nullptr;
    return true;
}

void GfxMetalPicaFrame::Cancel() {
    if (mEncoder != nullptr) {
        mEncoder->endEncoding();
        mEncoder = nullptr;
    }
    mCommandBuffer = nullptr;
    mDrawable = nullptr;
    if (mAutoreleasePool != nullptr) {
        mAutoreleasePool->release();
        mAutoreleasePool = nullptr;
    }
}

bool GfxMetalPicaFrame::IsActive() const {
    return mAutoreleasePool != nullptr &&
           mDrawable != nullptr &&
           mCommandBuffer != nullptr &&
           mEncoder != nullptr;
}

} // namespace Fast::Backends
