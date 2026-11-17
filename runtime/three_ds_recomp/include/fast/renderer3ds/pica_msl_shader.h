#pragma once

#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

#include "fast/renderer3ds/pica_nri_shader_contract.h"

namespace Fast::Renderer3ds {

enum class PicaMslShaderStage : uint8_t {
    Vertex,
    Fragment,
};

struct PicaMslShaderArtifact {
    std::string Source;
    std::string EntryPoint;
    PicaMslShaderStage Stage = PicaMslShaderStage::Vertex;
    std::vector<PicaNriDescriptorBinding> Resources;
};

// Compiles canonical PICA GLSL with shaderc, validates its descriptor ABI,
// then lowers its SPIR-V to iOS MSL. This is not yet a complete GPU backend.
[[nodiscard]] bool TranslatePicaGlslToMsl(
    std::string_view glslSource,
    PicaMslShaderStage stage,
    PicaMslShaderArtifact& artifact,
    std::string* error = nullptr);

// Convenience overload for callers that only need generated MSL source.
[[nodiscard]] bool TranslatePicaGlslToMsl(
    std::string_view glslSource,
    PicaMslShaderStage stage,
    std::string& mslSource,
    std::string* error = nullptr);

// Translates a PICA SPIR-V module that already uses the split texture/sampler
// descriptor ABI into iOS MSL. Descriptor metadata is validated by the
// artifact overload; the runtime backend binds the emitted argument buffers.
[[nodiscard]] bool TranslatePicaSpirvToMsl(
    std::span<const uint32_t> spirv,
    std::string& mslSource,
    std::string* error = nullptr);

} // namespace Fast::Renderer3ds
