#include "fast/backends/gfx_metal_pica_depth_stencil.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {
namespace {

bool ToMetalCompare(
    Renderer3ds::PicaCompareFunction compare,
    MTL::CompareFunction& result) {
    switch (compare) {
        case Renderer3ds::PicaCompareFunction::Never:
            result = MTL::CompareFunctionNever;
            return true;
        case Renderer3ds::PicaCompareFunction::Always:
            result = MTL::CompareFunctionAlways;
            return true;
        case Renderer3ds::PicaCompareFunction::Equal:
            result = MTL::CompareFunctionEqual;
            return true;
        case Renderer3ds::PicaCompareFunction::NotEqual:
            result = MTL::CompareFunctionNotEqual;
            return true;
        case Renderer3ds::PicaCompareFunction::Less:
            result = MTL::CompareFunctionLess;
            return true;
        case Renderer3ds::PicaCompareFunction::LessOrEqual:
            result = MTL::CompareFunctionLessEqual;
            return true;
        case Renderer3ds::PicaCompareFunction::Greater:
            result = MTL::CompareFunctionGreater;
            return true;
        case Renderer3ds::PicaCompareFunction::GreaterOrEqual:
            result = MTL::CompareFunctionGreaterEqual;
            return true;
    }
    return false;
}

bool ToMetalStencilOperation(
    Renderer3ds::PicaStencilAction action,
    MTL::StencilOperation& result) {
    switch (action) {
        case Renderer3ds::PicaStencilAction::Keep:
            result = MTL::StencilOperationKeep;
            return true;
        case Renderer3ds::PicaStencilAction::Zero:
            result = MTL::StencilOperationZero;
            return true;
        case Renderer3ds::PicaStencilAction::Replace:
            result = MTL::StencilOperationReplace;
            return true;
        case Renderer3ds::PicaStencilAction::Increment:
            result = MTL::StencilOperationIncrementClamp;
            return true;
        case Renderer3ds::PicaStencilAction::Decrement:
            result = MTL::StencilOperationDecrementClamp;
            return true;
        case Renderer3ds::PicaStencilAction::Invert:
            result = MTL::StencilOperationInvert;
            return true;
        case Renderer3ds::PicaStencilAction::IncrementWrap:
            result = MTL::StencilOperationIncrementWrap;
            return true;
        case Renderer3ds::PicaStencilAction::DecrementWrap:
            result = MTL::StencilOperationDecrementWrap;
            return true;
    }
    return false;
}

} // namespace

GfxMetalPicaDepthStencilState::~GfxMetalPicaDepthStencilState() {
    Reset();
}

bool GfxMetalPicaDepthStencilState::Create(
    MTL::Device* device,
    bool depthTestEnabled,
    bool depthWriteEnabled,
    Renderer3ds::PicaCompareFunction depthCompare,
    const Renderer3ds::PicaStencilState& stencil,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr) {
        if (error != nullptr) {
            *error = "PICA Metal depth/stencil state requires a Metal device";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::DepthStencilDescriptor* descriptor =
        MTL::DepthStencilDescriptor::alloc()->init();
    if (descriptor == nullptr) {
        pool->release();
        if (error != nullptr) {
            *error = "Metal could not allocate a depth/stencil descriptor";
        }
        return false;
    }
    MTL::CompareFunction metalDepthCompare = MTL::CompareFunctionAlways;
    if (depthTestEnabled && !ToMetalCompare(depthCompare, metalDepthCompare)) {
        descriptor->release();
        pool->release();
        if (error != nullptr) {
            *error = "PICA depth compare function is invalid";
        }
        return false;
    }
    descriptor->setDepthCompareFunction(metalDepthCompare);
    descriptor->setDepthWriteEnabled(depthWriteEnabled);

    if (stencil.Enabled) {
        MTL::StencilDescriptor* face =
            MTL::StencilDescriptor::alloc()->init();
        if (face == nullptr) {
            descriptor->release();
            pool->release();
            if (error != nullptr) {
                *error = "Metal could not allocate a stencil face descriptor";
            }
            return false;
        }
        MTL::CompareFunction stencilCompare;
        MTL::StencilOperation stencilFail;
        MTL::StencilOperation stencilDepthFail;
        MTL::StencilOperation stencilPass;
        if (!ToMetalCompare(stencil.Compare, stencilCompare) ||
            !ToMetalStencilOperation(stencil.Fail, stencilFail) ||
            !ToMetalStencilOperation(stencil.DepthFail, stencilDepthFail) ||
            !ToMetalStencilOperation(stencil.Pass, stencilPass)) {
            face->release();
            descriptor->release();
            pool->release();
            if (error != nullptr) {
                *error = "PICA stencil state contains an invalid compare or operation";
            }
            return false;
        }
        face->setStencilCompareFunction(stencilCompare);
        face->setStencilFailureOperation(stencilFail);
        face->setDepthFailureOperation(stencilDepthFail);
        face->setDepthStencilPassOperation(stencilPass);
        face->setReadMask(stencil.CompareMask);
        face->setWriteMask(stencil.WriteMask);
        descriptor->setFrontFaceStencil(face);
        descriptor->setBackFaceStencil(face);
        face->release();
    }

    mState = device->newDepthStencilState(descriptor);
    descriptor->release();
    pool->release();
    if (mState == nullptr) {
        if (error != nullptr) {
            *error = "Metal could not create the PICA depth/stencil state";
        }
        return false;
    }
    return true;
}

void GfxMetalPicaDepthStencilState::Reset() {
    if (mState != nullptr) {
        mState->release();
        mState = nullptr;
    }
}

bool GfxMetalPicaDepthStencilState::Bind(
    MTL::RenderCommandEncoder* encoder,
    uint8_t stencilReference) const {
    if (encoder == nullptr || mState == nullptr) {
        return false;
    }
    encoder->setDepthStencilState(mState);
    encoder->setStencilReferenceValue(stencilReference);
    return true;
}

bool GfxMetalPicaDepthStencilState::IsValid() const {
    return mState != nullptr;
}

MTL::DepthStencilState* GfxMetalPicaDepthStencilState::State() const {
    return mState;
}

} // namespace Fast::Backends
