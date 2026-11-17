#include "fast/backends/gfx_metal_pica_raster_state.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {
namespace {

bool ToMetalBlendFactor(
    Renderer3ds::NativeBlendFactor factor,
    MTL::BlendFactor& result) {
    using Renderer3ds::NativeBlendFactor;
    switch (factor) {
        case NativeBlendFactor::Zero:
            result = MTL::BlendFactorZero;
            return true;
        case NativeBlendFactor::One:
            result = MTL::BlendFactorOne;
            return true;
        case NativeBlendFactor::SourceColor:
            result = MTL::BlendFactorSourceColor;
            return true;
        case NativeBlendFactor::OneMinusSourceColor:
            result = MTL::BlendFactorOneMinusSourceColor;
            return true;
        case NativeBlendFactor::DestColor:
            result = MTL::BlendFactorDestinationColor;
            return true;
        case NativeBlendFactor::OneMinusDestColor:
            result = MTL::BlendFactorOneMinusDestinationColor;
            return true;
        case NativeBlendFactor::SourceAlpha:
            result = MTL::BlendFactorSourceAlpha;
            return true;
        case NativeBlendFactor::OneMinusSourceAlpha:
            result = MTL::BlendFactorOneMinusSourceAlpha;
            return true;
        case NativeBlendFactor::DestAlpha:
            result = MTL::BlendFactorDestinationAlpha;
            return true;
        case NativeBlendFactor::OneMinusDestAlpha:
            result = MTL::BlendFactorOneMinusDestinationAlpha;
            return true;
        case NativeBlendFactor::ConstantColor:
            result = MTL::BlendFactorBlendColor;
            return true;
        case NativeBlendFactor::OneMinusConstantColor:
            result = MTL::BlendFactorOneMinusBlendColor;
            return true;
        case NativeBlendFactor::ConstantAlpha:
            result = MTL::BlendFactorBlendAlpha;
            return true;
        case NativeBlendFactor::OneMinusConstantAlpha:
            result = MTL::BlendFactorOneMinusBlendAlpha;
            return true;
        case NativeBlendFactor::SourceAlphaSaturate:
            result = MTL::BlendFactorSourceAlphaSaturated;
            return true;
    }
    return false;
}

bool ToMetalBlendOperation(
    Renderer3ds::NativeBlendEquation equation,
    MTL::BlendOperation& result) {
    switch (equation) {
        case Renderer3ds::NativeBlendEquation::Add:
            result = MTL::BlendOperationAdd;
            return true;
        case Renderer3ds::NativeBlendEquation::Subtract:
            result = MTL::BlendOperationSubtract;
            return true;
        case Renderer3ds::NativeBlendEquation::ReverseSubtract:
            result = MTL::BlendOperationReverseSubtract;
            return true;
        case Renderer3ds::NativeBlendEquation::Min:
            result = MTL::BlendOperationMin;
            return true;
        case Renderer3ds::NativeBlendEquation::Max:
            result = MTL::BlendOperationMax;
            return true;
    }
    return false;
}

MTL::ColorWriteMask ToMetalColorWriteMask(uint8_t mask) {
    MTL::ColorWriteMask result = MTL::ColorWriteMaskNone;
    if ((mask & 0x1U) != 0U) result |= MTL::ColorWriteMaskRed;
    if ((mask & 0x2U) != 0U) result |= MTL::ColorWriteMaskGreen;
    if ((mask & 0x4U) != 0U) result |= MTL::ColorWriteMaskBlue;
    if ((mask & 0x8U) != 0U) result |= MTL::ColorWriteMaskAlpha;
    return result;
}

} // namespace

bool ConfigurePicaMetalColorAttachment(
    MTL::RenderPipelineColorAttachmentDescriptor* attachment,
    const Renderer3ds::NativeBlendState& blend,
    Renderer3ds::PicaLogicOperation logicOperation,
    uint8_t colorWriteMask,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (attachment == nullptr) {
        if (error != nullptr) {
            *error = "PICA Metal blend configuration requires a color attachment";
        }
        return false;
    }
    if (logicOperation != Renderer3ds::PicaLogicOperation::Copy) {
        if (error != nullptr) {
            *error = "PICA bitwise logic operations are not supported by the Metal blend unit";
        }
        return false;
    }

    MTL::BlendOperation rgbOperation;
    MTL::BlendOperation alphaOperation;
    MTL::BlendFactor sourceRgb;
    MTL::BlendFactor destinationRgb;
    MTL::BlendFactor sourceAlpha;
    MTL::BlendFactor destinationAlpha;
    if (!ToMetalBlendOperation(blend.EquationRgb, rgbOperation) ||
        !ToMetalBlendOperation(blend.EquationAlpha, alphaOperation) ||
        !ToMetalBlendFactor(blend.SourceRgb, sourceRgb) ||
        !ToMetalBlendFactor(blend.DestRgb, destinationRgb) ||
        !ToMetalBlendFactor(blend.SourceAlpha, sourceAlpha) ||
        !ToMetalBlendFactor(blend.DestAlpha, destinationAlpha)) {
        if (error != nullptr) {
            *error = "PICA blend state contains an invalid operation or factor";
        }
        return false;
    }
    attachment->setBlendingEnabled(blend.Enabled);
    attachment->setRgbBlendOperation(rgbOperation);
    attachment->setAlphaBlendOperation(alphaOperation);
    attachment->setSourceRGBBlendFactor(sourceRgb);
    attachment->setDestinationRGBBlendFactor(destinationRgb);
    attachment->setSourceAlphaBlendFactor(sourceAlpha);
    attachment->setDestinationAlphaBlendFactor(destinationAlpha);
    attachment->setWriteMask(ToMetalColorWriteMask(colorWriteMask));
    return true;
}

bool BindPicaMetalRasterState(
    MTL::RenderCommandEncoder* encoder,
    Renderer3ds::NativeCullMode cullMode,
    bool framebufferFlipped,
    const Renderer3ds::NativeBlendState& blend,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    if (encoder == nullptr) {
        if (error != nullptr) {
            *error = "PICA Metal raster state requires a render encoder";
        }
        return false;
    }

    encoder->setCullMode(
        cullMode == Renderer3ds::NativeCullMode::KeepAll
            ? MTL::CullModeNone
            : (framebufferFlipped ? MTL::CullModeFront : MTL::CullModeBack));
    encoder->setFrontFacingWinding(
        cullMode == Renderer3ds::NativeCullMode::KeepCounterClockwise
            ? MTL::WindingClockwise
            : MTL::WindingCounterClockwise);
    encoder->setBlendColor(
        blend.ConstantColor[0], blend.ConstantColor[1],
        blend.ConstantColor[2], blend.ConstantColor[3]);
    return true;
}

} // namespace Fast::Backends
