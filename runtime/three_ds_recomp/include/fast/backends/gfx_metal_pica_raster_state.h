#pragma once

#include <string>

#include "fast/renderer3ds/pica_native_state.h"

namespace MTL {
class RenderCommandEncoder;
class RenderPipelineColorAttachmentDescriptor;
}

namespace Fast::Backends {

// Configures one Metal color attachment from the shared PICA blend contract.
// Non-COPY PICA logic operations are rejected because Metal's ordinary blend
// unit cannot reproduce bitwise framebuffer logic operations.
[[nodiscard]] bool ConfigurePicaMetalColorAttachment(
    MTL::RenderPipelineColorAttachmentDescriptor* attachment,
    const Renderer3ds::NativeBlendState& blend,
    Renderer3ds::PicaLogicOperation logicOperation,
    uint8_t colorWriteMask,
    std::string* error = nullptr);

// Applies the dynamic cull/winding and constant blend colour for a PICA draw.
[[nodiscard]] bool BindPicaMetalRasterState(
    MTL::RenderCommandEncoder* encoder,
    Renderer3ds::NativeCullMode cullMode,
    bool framebufferFlipped,
    const Renderer3ds::NativeBlendState& blend,
    std::string* error = nullptr);

} // namespace Fast::Backends
