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

MTL::CommandBuffer* GfxMetalPicaFrame::CommandBuffer() const {
    return mCommandBuffer;
}

bool GfxMetalPicaFrame::EndEncoding(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!IsActive() || mEncoder == nullptr) {
        if (error != nullptr) {
            *error = "Metal PICA frame has no active render encoder to end";
        }
        return false;
    }
    mEncoder->endEncoding();
    mEncoder = nullptr;
    return true;
}

bool GfxMetalPicaFrame::BeginDrawablePass(
    GfxMetalPicaClearColor clearColor,
    bool clear,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!IsActive() || mEncoder != nullptr) {
        if (error != nullptr) {
            *error = "Metal PICA drawable pass requires an active frame with no open encoder";
        }
        return false;
    }

    MTL::RenderPassDescriptor* renderPass =
        MTL::RenderPassDescriptor::renderPassDescriptor();
    if (renderPass == nullptr) {
        if (error != nullptr) {
            *error = "Metal could not allocate the drawable presentation pass";
        }
        return false;
    }
    MTL::RenderPassColorAttachmentDescriptor* colorAttachment =
        renderPass->colorAttachments()->object(0);
    colorAttachment->setTexture(mDrawable->texture());
    colorAttachment->setLoadAction(
        clear ? MTL::LoadActionClear : MTL::LoadActionLoad);
    colorAttachment->setStoreAction(MTL::StoreActionStore);
    if (clear) {
        colorAttachment->setClearColor(MTL::ClearColor::Make(
            clearColor.Red, clearColor.Green, clearColor.Blue, clearColor.Alpha));
    }

    mEncoder = mCommandBuffer->renderCommandEncoder(renderPass);
    if (mEncoder == nullptr) {
        if (error != nullptr) {
            *error = "Metal could not create the drawable presentation encoder";
        }
        return false;
    }
    return true;
}

bool GfxMetalPicaFrame::EndAndPresent(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!IsActive() || mEncoder == nullptr) {
        if (error != nullptr) {
            *error = "Metal PICA frame has no active drawable encoder to present";
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
           mCommandBuffer != nullptr;
}

bool GfxMetalPicaFrame::HasActiveEncoder() const {
    return mEncoder != nullptr;
}

} // namespace Fast::Backends
