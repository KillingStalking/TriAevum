#include "fast/backends/gfx_metal_pica_backend.h"

#include <SDL_render.h>

#include <Metal/Metal.hpp>

#include "fast/extension/pica_display_transfer.h"

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
        mDisplayTransferCache.Clear();
    }
    return mDevice.Initialize(renderer, error);
}

bool GfxMetalPicaBackend::BeginFrame(
    MTL::CommandBuffer* commandBuffer,
    std::string* error) {
    return BeginFrame(commandBuffer, nullptr, error);
}

bool GfxMetalPicaBackend::BeginFrame(
    MTL::CommandBuffer* commandBuffer,
    MTL::Texture* drawableTexture,
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
    mDrawableTexture = drawableTexture;
    return true;
}

void GfxMetalPicaBackend::EndFrame() {
    // The host owns and commits/presents this command buffer after all PICA
    // work has been appended to it.
    mCommandBuffer = nullptr;
    mDrawableTexture = nullptr;
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
        mDisplayTransferCache.Clear();
        return true;
    }
    if (!mDevice.WaitIdle(error)) {
        return false;
    }
    mDrawExecutor.ClearCaches();
    mTextureCache.Clear();
    mRenderTargetCache.Clear();
    mDisplayTransferCache.Clear();
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
    if (!HasActiveFrame()) {
        SetError(error, "native PICA Metal display transfer submitted outside an active frame");
        return false;
    }
    if (transfer.RenderTargetCapture) {
        if (transfer.CompletionId == 0U || transfer.InputPhysicalAddress == 0U ||
            transfer.InputWidth == 0U || transfer.InputHeight == 0U ||
            transfer.Present || transfer.MaterializeGuest || transfer.TextureCopyBytes != 0U) {
            SetError(error, "native PICA Metal render-target capture has an invalid producer identity or unsupported side effect");
            return false;
        }
        GfxMetalPicaRenderTarget* captureSource = mRenderTargetCache.FindColorTarget(
            transfer.RenderTargetNamespace, transfer.InputPhysicalAddress);
        if (captureSource == nullptr || transfer.InputWidth > captureSource->Width() ||
            transfer.InputHeight > captureSource->Height()) {
            SetError(error, "native PICA Metal render-target capture source is missing or too small");
            return false;
        }
        if (transfer.InputWidth != captureSource->Width() ||
            transfer.InputHeight != captureSource->Height()) {
            SetError(error, "native PICA Metal render-target capture currently requires an exact full-target extent");
            return false;
        }
        return mDisplayTransferCache.CaptureRenderTarget(
            mDevice, mCommandBuffer, captureSource->ColorTexture(),
            transfer.RenderTargetNamespace, transfer.CompletionId,
            transfer.AfterDrawSubmissionId, transfer.InputPhysicalAddress, error);
    }
    if (transfer.TextureCopyBytes != 0U) {
        SetError(error, "native PICA Metal raw TextureCopy still requires native-byte encoding and tiled partial-range derivation");
        return false;
    }
    if (transfer.Present && mDrawableTexture == nullptr) {
        SetError(error, "native PICA Metal display transfer requires the active CAMetalDrawable texture");
        return false;
    }
    if (transfer.MaterializeGuest) {
        SetError(error, "native PICA Metal display transfer cannot complete a guest-visible write until asynchronous readback and physical-memory commit are connected");
        return false;
    }
    if (transfer.CompletionId == 0U ||
        transfer.InputPhysicalAddress == 0U ||
        transfer.OutputPhysicalAddress == 0U ||
        transfer.InputWidth == 0U || transfer.InputHeight == 0U ||
        transfer.OutputWidth == 0U || transfer.OutputHeight == 0U) {
        SetError(error, "native PICA Metal display transfer has an incomplete guest identity or extent");
        return false;
    }

    GfxMetalPicaRenderTarget* source = mRenderTargetCache.FindColorTarget(
        transfer.RenderTargetNamespace, transfer.InputPhysicalAddress);
    if (source == nullptr) {
        SetError(error, "native PICA Metal display transfer source framebuffer has not been rendered");
        return false;
    }
    if (transfer.InputWidth > source->Width() ||
        transfer.InputHeight > source->Height()) {
        SetError(error, "native PICA Metal display transfer exceeds its source framebuffer");
        return false;
    }

    std::string planError;
    const auto plan = Extension::BuildPicaDisplayTransferPlan({
        transfer.InputWidth,
        transfer.InputHeight,
        transfer.OutputWidth,
        transfer.OutputHeight,
        source->Width(),
        source->Height(),
        transfer.Flags,
        false,
    }, &planError);
    if (!plan.has_value()) {
        if (error != nullptr) {
            *error = "native PICA Metal display-transfer plan failed: " + planError;
        }
        return false;
    }
    if (!mDisplayTransferCache.Submit(
        mDevice, mCommandBuffer, source->ColorTexture(),
        transfer, *plan, error)) {
        return false;
    }
    if (transfer.Present) {
        MTL::Texture* display = mDisplayTransferCache.Find(
            transfer.RenderTargetNamespace, transfer.OutputPhysicalAddress);
        return mDisplayTransferCache.Present(
            mDevice, mCommandBuffer, display, mDrawableTexture,
            transfer.PresentationMode, error);
    }
    return true;
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

bool GfxMetalPicaBackend::SetPinnedPicaTextureCopies(
    std::span<const Renderer3ds::PicaTextureCopyReference> copies,
    std::string* error) {
    if (error != nullptr) error->clear();
    if (HasActiveFrame()) {
        SetError(error, "native PICA Metal producer pins cannot change during an active frame");
        return false;
    }
    return mDisplayTransferCache.SetPinnedCaptures(
        mCanonicalRenderTargetNamespace, copies, error);
}

void GfxMetalPicaBackend::SetCanonicalPicaRenderTargetNamespace(
    uint64_t renderTargetNamespace) {
    mCanonicalRenderTargetNamespace = renderTargetNamespace;
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
    mDisplayTransferCache.Clear();
    mCanonicalRenderTargetNamespace = 0U;
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

MTL::Texture* GfxMetalPicaBackend::FindDisplayTexture(
    uint64_t renderTargetNamespace,
    uint32_t outputPhysicalAddress) const {
    return mDisplayTransferCache.Find(
        renderTargetNamespace, outputPhysicalAddress);
}

} // namespace Fast::Backends
