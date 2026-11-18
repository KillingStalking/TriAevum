#include "fast/backends/gfx_metal_pica_shader.h"

#include <Metal/Metal.hpp>

namespace Fast::Backends {

GfxMetalPicaShader::~GfxMetalPicaShader() {
    Reset();
}

bool GfxMetalPicaShader::Compile(
    MTL::Device* device,
    const Renderer3ds::PicaMslShaderArtifact& artifact,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr || artifact.Source.empty() ||
        artifact.EntryPoint.empty()) {
        if (error != nullptr) {
            *error = "PICA Metal shader compilation requires a device, MSL source and entry point";
        }
        return false;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    NS::String* source = NS::String::string(
        artifact.Source.c_str(), NS::UTF8StringEncoding);
    MTL::CompileOptions* options = MTL::CompileOptions::alloc()->init();
    if (source == nullptr || options == nullptr) {
        if (options != nullptr) {
            options->release();
        }
        pool->release();
        if (error != nullptr) {
            *error = "Metal could not allocate shader compilation inputs";
        }
        return false;
    }
    options->setLanguageVersion(MTL::LanguageVersion2_3);

    NS::Error* compileError = nullptr;
    mLibrary = device->newLibrary(source, options, &compileError);
    options->release();
    if (mLibrary == nullptr) {
        if (error != nullptr) {
            const char* description =
                compileError != nullptr &&
                        compileError->localizedDescription() != nullptr
                    ? compileError->localizedDescription()->utf8String()
                    : nullptr;
            *error = description != nullptr
                ? description
                : "Metal failed to compile the PICA MSL source";
        }
        pool->release();
        return false;
    }

    NS::String* entryPoint = NS::String::string(
        artifact.EntryPoint.c_str(), NS::UTF8StringEncoding);
    if (entryPoint != nullptr) {
        mFunction = mLibrary->newFunction(entryPoint);
    }
    pool->release();

    if (mFunction == nullptr) {
        Reset();
        if (error != nullptr) {
            *error = "Compiled MSL library does not contain the requested entry point";
        }
        return false;
    }
    return true;
}

void GfxMetalPicaShader::Reset() {
    if (mFunction != nullptr) {
        mFunction->release();
        mFunction = nullptr;
    }
    if (mLibrary != nullptr) {
        mLibrary->release();
        mLibrary = nullptr;
    }
}

bool GfxMetalPicaShader::IsValid() const {
    return mLibrary != nullptr && mFunction != nullptr;
}

MTL::Function* GfxMetalPicaShader::Function() const {
    return mFunction;
}

} // namespace Fast::Backends
