#pragma once

#include <string>

#include "fast/renderer3ds/pica_msl_shader.h"

namespace MTL {
class Device;
class Function;
class Library;
}

namespace Fast::Backends {

// Compiles translated MSL source through the on-device Metal compiler and
// retains the resulting library/function for pipeline creation.
class GfxMetalPicaShader {
  public:
    GfxMetalPicaShader() = default;
    ~GfxMetalPicaShader();

    GfxMetalPicaShader(const GfxMetalPicaShader&) = delete;
    GfxMetalPicaShader& operator=(const GfxMetalPicaShader&) = delete;

    [[nodiscard]] bool Compile(
        MTL::Device* device,
        const Renderer3ds::PicaMslShaderArtifact& artifact,
        std::string* error = nullptr);
    void Reset();

    [[nodiscard]] bool IsValid() const;
    [[nodiscard]] MTL::Function* Function() const;

  private:
    MTL::Library* mLibrary = nullptr;
    MTL::Function* mFunction = nullptr;
};

} // namespace Fast::Backends
