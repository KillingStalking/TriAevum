#include "fast/backends/gfx_metal_pica_device.h"

#include <Metal/Metal.hpp>
#include <QuartzCore/QuartzCore.hpp>
#include <SDL_render.h>

namespace Fast::Backends {

GfxMetalPicaDevice::~GfxMetalPicaDevice() {
    Shutdown();
}

bool GfxMetalPicaDevice::Initialize(SDL_Renderer* renderer, std::string* error) {
    if (renderer == nullptr) {
        if (error != nullptr) {
            *error = "Metal PICA initialization requires an SDL renderer";
        }
        return false;
    }
    auto* layer = static_cast<CA::MetalLayer*>(SDL_RenderGetMetalLayer(renderer));
    return Initialize(layer, error);
}

bool GfxMetalPicaDevice::Initialize(CA::MetalLayer* layer, std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (layer == nullptr) {
        if (error != nullptr) {
            *error = "Metal PICA initialization requires an SDL-owned CAMetalLayer";
        }
        return false;
    }
    if (IsReady()) {
        if (mLayer == layer) {
            return true;
        }
        if (error != nullptr) {
            *error = "Metal PICA device is already attached to another layer";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::Device* device = layer->device();
    if (device == nullptr) {
        pool->release();
        if (error != nullptr) {
            *error = "SDL's CAMetalLayer has no Metal device";
        }
        return false;
    }

    MTL::CommandQueue* queue = device->newCommandQueue();
    if (queue == nullptr) {
        pool->release();
        if (error != nullptr) {
            *error = "Metal device could not create a command queue";
        }
        return false;
    }

    layer->setPixelFormat(MTL::PixelFormatBGRA8Unorm);
    layer->setFramebufferOnly(false);

    // The layer owns its device. Keep a non-owning device pointer and own only
    // the queue returned by newCommandQueue().
    mDevice = device;
    mCommandQueue = queue;
    mLayer = layer;
    pool->release();
    return true;
}

void GfxMetalPicaDevice::Shutdown() {
    if (mCommandQueue != nullptr) {
        mCommandQueue->release();
        mCommandQueue = nullptr;
    }
    // The SDL-owned CAMetalLayer retains the MTL::Device.
    mDevice = nullptr;
    mLayer = nullptr;
}

bool GfxMetalPicaDevice::IsReady() const {
    return mDevice != nullptr && mCommandQueue != nullptr && mLayer != nullptr;
}

MTL::Device* GfxMetalPicaDevice::Device() const {
    return mDevice;
}

MTL::CommandQueue* GfxMetalPicaDevice::CommandQueue() const {
    return mCommandQueue;
}

CA::MetalLayer* GfxMetalPicaDevice::Layer() const {
    return mLayer;
}

bool GfxMetalPicaDevice::WaitIdle(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!IsReady()) {
        if (error != nullptr) {
            *error = "Metal PICA device is not initialized";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::CommandBuffer* commandBuffer = mCommandQueue->commandBuffer();
    if (commandBuffer == nullptr) {
        pool->release();
        if (error != nullptr) {
            *error = "Metal command queue did not create an idle fence";
        }
        return false;
    }
    commandBuffer->commit();
    commandBuffer->waitUntilCompleted();
    const bool completed =
        commandBuffer->status() == MTL::CommandBufferStatusCompleted;
    pool->release();
    if (!completed && error != nullptr) {
        *error = "Metal queue idle fence completed with an error";
    }
    return completed;
}

} // namespace Fast::Backends
