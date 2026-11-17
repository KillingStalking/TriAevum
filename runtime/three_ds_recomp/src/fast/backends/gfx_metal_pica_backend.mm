#include "fast/backends/gfx_metal_pica_backend.h"

#include <SDL_render.h>

#include <Metal/Metal.hpp>

#include <cassert>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, const char* message) {
    if (error != nullptr) {
        *error = message;
    }
}

} // namespace

GfxMetalPicaBackend::~GfxMetalPicaBackend() {
    assert(!HasActiveFrame());
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
    if (!mDevice.IsReady()) {
        mDrawExecutor.ClearCaches();
        mTextureCache.Clear();
        mRenderTargetCache.Clear();
    }
    return mDevice.Initialize(renderer, error);
}

bool GfxMetalPicaBackend::BeginFrame(
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (!mDevice.IsReady() || commandBuffer == nullptr || HasActiveFrame() ||
        commandBuffer->commandQueue() != mDevice.CommandQueue()) {
        SetError(error, "Metal PICA frame requires a command buffer from the backend device queue and no active frame");
        return false;
    }
    ++mFrameIndex;
    mTextureCache.BeginFrame(mFrameIndex);
    mRenderTargetCache.BeginFrame(mFrameIndex);
    mCommandBuffer = commandBuffer;
    return true;
}

void GfxMetalPicaBackend::EndFrame() {
    // The host owns and commits/presents this command buffer after all PICA
    // work has been appended to it.
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
        mDrawExecutor.ClearCaches();
        mTextureCache.Clear();
        mRenderTargetCache.Clear();
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
    if (!draw.FragmentShaderSource.empty()) {
        return mDrawExecutor.Encode(
            mDevice, mTextureCache, mRenderTargetCache,
            mCommandBuffer, draw, error);
    }
    if (draw.UberFragmentShaderSource.empty()) {
        SetError(error, "native PICA Metal draw has neither a specialized nor an uber fragment shader");
        return false;
    }

    // The frontend may submit the always-available uber program while the
    // specialized fragment variant is still being prepared.
    Renderer3ds::PicaDrawView fallback = draw;
    fallback.FragmentShaderSource = draw.UberFragmentShaderSource;
    fallback.FragmentShaderKey = draw.UberFragmentShaderKey;
    fallback.FragmentShaderSourceIdentity = draw.UberFragmentShaderSourceIdentity;
    fallback.FragmentShaderHooks = draw.UberFragmentShaderHooks;
    // The fallback program has no canonical pipeline identity shared with the
    // specialized program; use a transient pipeline to avoid a false cache hit.
    fallback.CanonicalPipelineId = 0U;
    fallback.CanonicalFragmentProgramId = 0U;
    return mDrawExecutor.Encode(
        mDevice, mTextureCache, mRenderTargetCache,
        mCommandBuffer, fallback, error);
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
