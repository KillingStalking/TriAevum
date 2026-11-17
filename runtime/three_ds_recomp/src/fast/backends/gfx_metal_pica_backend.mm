#include "fast/backends/gfx_metal_pica_backend.h"

#include <SDL_render.h>

#include <utility>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, const char* message) {
    if (error != nullptr) {
        *error = message;
    }
}

} // namespace

GfxMetalPicaBackend::~GfxMetalPicaBackend() {
    std::string ignored;
    (void)Shutdown(&ignored);
}

bool GfxMetalPicaBackend::Initialize(
    SDL_Renderer* renderer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (HasActiveFrame()) {
        SetError(error, "Metal PICA backend cannot initialize during an active frame");
        return false;
    }
    return mDevice.Initialize(renderer, error);
}

bool GfxMetalPicaBackend::BeginFrame(
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!mDevice.IsReady() || commandBuffer == nullptr || HasActiveFrame()) {
        SetError(error, "Metal PICA frame requires a ready device, command buffer and no active frame");
        return false;
    }
    ++mFrameIndex;
    mTextureCache.BeginFrame(mFrameIndex);
    mRenderTargetCache.BeginFrame(mFrameIndex);
    mCommandBuffer = commandBuffer;
    return true;
}

void GfxMetalPicaBackend::EndFrame() {
    mCommandBuffer = nullptr;
}

bool GfxMetalPicaBackend::Shutdown(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (HasActiveFrame()) {
        SetError(error, "Metal PICA backend cannot shut down during an active frame");
        return false;
    }
    if (!mDevice.IsReady()) {
        return true;
    }
    if (!mDevice.WaitIdle(error)) {
        return false;
    }
    mDrawExecutor.ClearCaches();
    mTextureCache.Clear();
    mRenderTargetCache.Clear();
    mDevice.Shutdown();
    return true;
}

bool GfxMetalPicaBackend::SubmitPicaDraw(
    const Renderer3ds::PicaDrawView& draw,
    std::string* error) {
    if (!HasActiveFrame()) {
        SetError(error, "native PICA Metal draw submitted outside an active frame");
        return false;
    }
    return mDrawExecutor.Encode(
        mDevice, mTextureCache, mRenderTargetCache,
        mCommandBuffer, draw, error);
}

bool GfxMetalPicaBackend::SubmitPicaDisplayTransfer(
    const Renderer3ds::PicaDisplayTransferView& transfer,
    std::string* error) {
    (void)transfer;
    SetError(error, "native PICA Metal display transfers are not implemented yet");
    return false;
}

bool GfxMetalPicaBackend::ClearPicaRenderTarget(
    uint64_t renderTargetNamespace,
    uint32_t colorPhysicalAddress,
    std::string* error) {
    if (!HasActiveFrame()) {
        SetError(error, "native PICA Metal target clear submitted outside an active frame");
        return false;
    }
    return mRenderTargetCache.Clear(
        renderTargetNamespace, colorPhysicalAddress,
        mCommandBuffer, error);
}

bool GfxMetalPicaBackend::SubmitPicaMemoryFill(
    const Renderer3ds::PicaMemoryFillView& fill,
    std::string* error) {
    if (!HasActiveFrame()) {
        SetError(error, "native PICA Metal memory fill submitted outside an active frame");
        return false;
    }
    return mRenderTargetCache.SubmitMemoryFill(
        fill, mCommandBuffer, error);
}

bool GfxMetalPicaBackend::ResetPicaState(std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (HasActiveFrame()) {
        SetError(error, "native PICA Metal state cannot reset during an active frame");
        return false;
    }
    if (mDevice.IsReady() && !mDevice.WaitIdle(error)) {
        return false;
    }
    mDrawExecutor.ClearCaches();
    mTextureCache.Clear();
    mRenderTargetCache.Clear();
    return true;
}

bool GfxMetalPicaBackend::IsReady() const {
    return mDevice.IsReady();
}

bool GfxMetalPicaBackend::HasActiveFrame() const {
    return mCommandBuffer != nullptr;
}

GfxMetalPicaDevice& GfxMetalPicaBackend::Device() {
    return mDevice;
}

} // namespace Fast::Backends
