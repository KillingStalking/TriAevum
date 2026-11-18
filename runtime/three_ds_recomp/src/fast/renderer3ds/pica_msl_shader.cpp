#include "fast/renderer3ds/pica_msl_shader.h"

#include <spirv_msl.hpp>
#include <shaderc/shaderc.hpp>

#include <algorithm>
#include <exception>
#include <utility>
#include <vector>

namespace Fast::Renderer3ds {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

bool TranslateSpirvToMslArtifact(
    std::span<const uint32_t> spirv,
    PicaMslShaderStage expectedStage,
    PicaMslShaderArtifact& artifact,
    std::string* error) {
    artifact = {};
    artifact.Stage = expectedStage;
    if (spirv.empty() || spirv.front() != 0x07230203U) {
        SetError(error, "PICA shader input is not a valid SPIR-V module");
        return false;
    }

    try {
        std::vector<uint32_t> ownedSpirv(spirv.begin(), spirv.end());
        spirv_cross::CompilerMSL compiler(std::move(ownedSpirv));
        const auto entryPoint = compiler.get_entry_point();
        const auto expectedModel =
            expectedStage == PicaMslShaderStage::Vertex
                ? spv::ExecutionModelVertex
                : spv::ExecutionModelFragment;
        if (entryPoint.execution_model != expectedModel) {
            SetError(error, "PICA SPIR-V entry point does not match the requested shader stage");
            return false;
        }

        const auto resources = compiler.get_shader_resources();
        const auto appendResource = [&](const spirv_cross::Resource& resource,
                                        PicaNriDescriptorKind kind) {
            if (!compiler.has_decoration(resource.id, spv::DecorationBinding)) {
                throw std::runtime_error("PICA shader resource has no descriptor binding");
            }
            const uint32_t descriptorSet =
                compiler.has_decoration(resource.id, spv::DecorationDescriptorSet)
                    ? compiler.get_decoration(resource.id, spv::DecorationDescriptorSet)
                    : 0U;
            const uint32_t bindingIndex =
                compiler.get_decoration(resource.id, spv::DecorationBinding);
            if (descriptorSet != 0U) {
                throw std::runtime_error("PICA Metal shaders currently support descriptor set zero only");
            }

            const auto expected = std::find_if(
                kPicaNriDescriptorBindings.begin(),
                kPicaNriDescriptorBindings.end(),
                [bindingIndex](const PicaNriDescriptorBinding& candidate) {
                    return candidate.Binding == bindingIndex;
                });
            const auto nriStage =
                expectedStage == PicaMslShaderStage::Vertex
                    ? PicaNriShaderStage::Vertex
                    : PicaNriShaderStage::Fragment;
            if (expected == kPicaNriDescriptorBindings.end() ||
                expected->Kind != kind || expected->Stage != nriStage) {
                throw std::runtime_error(
                    "PICA Metal shader descriptor does not match the canonical PICA binding ABI");
            }

            spirv_cross::MSLResourceBinding metalBinding;
            metalBinding.stage = entryPoint.execution_model;
            metalBinding.basetype = compiler.get_type(resource.type_id).basetype;
            metalBinding.desc_set = descriptorSet;
            metalBinding.binding = bindingIndex;
            switch (kind) {
                case PicaNriDescriptorKind::ConstantBuffer:
                case PicaNriDescriptorKind::StructuredBuffer:
                    metalBinding.msl_buffer = bindingIndex;
                    break;
                case PicaNriDescriptorKind::Texture:
                case PicaNriDescriptorKind::StorageTexture:
                    metalBinding.msl_texture = bindingIndex;
                    break;
                case PicaNriDescriptorKind::Sampler:
                    metalBinding.msl_sampler = bindingIndex;
                    break;
            }
            compiler.add_msl_resource_binding(metalBinding);
            artifact.Resources.push_back(*expected);
        };

        for (const auto& resource : resources.uniform_buffers) {
            appendResource(resource, PicaNriDescriptorKind::ConstantBuffer);
        }
        for (const auto& resource : resources.storage_buffers) {
            appendResource(resource, PicaNriDescriptorKind::StructuredBuffer);
        }
        for (const auto& resource : resources.storage_images) {
            appendResource(resource, PicaNriDescriptorKind::StorageTexture);
        }
        for (const auto& resource : resources.separate_images) {
            appendResource(resource, PicaNriDescriptorKind::Texture);
        }
        for (const auto& resource : resources.separate_samplers) {
            appendResource(resource, PicaNriDescriptorKind::Sampler);
        }
        if (!resources.sampled_images.empty() ||
            !resources.push_constant_buffers.empty() ||
            !resources.subpass_inputs.empty() ||
            !resources.atomic_counters.empty() ||
            !resources.acceleration_structures.empty() ||
            !resources.gl_plain_uniforms.empty() ||
            !resources.tensors.empty() ||
            !resources.shader_record_buffers.empty()) {
            throw std::runtime_error(
                "PICA Metal shader contains a resource class outside the canonical descriptor ABI");
        }

        auto options = compiler.get_msl_options();
        options.platform = spirv_cross::CompilerMSL::Options::iOS;
        options.set_msl_version(2, 3);
        options.argument_buffers = true;
        options.argument_buffers_tier =
            spirv_cross::CompilerMSL::Options::ArgumentBuffersTier::Tier2;
        options.force_active_argument_buffer_resources = true;
        compiler.set_msl_options(options);

        artifact.Source = compiler.compile();
        artifact.EntryPoint = compiler.get_cleansed_entry_point_name(
            entryPoint.name, entryPoint.execution_model);
        std::sort(
            artifact.Resources.begin(), artifact.Resources.end(),
            [](const PicaNriDescriptorBinding& left,
               const PicaNriDescriptorBinding& right) {
                return left.Binding < right.Binding;
            });
        if (artifact.Source.empty() || artifact.EntryPoint.empty()) {
            throw std::runtime_error("SPIRV-Cross returned an incomplete MSL artifact");
        }
        return true;
    } catch (const std::exception& exception) {
        artifact = {};
        SetError(error, exception.what());
        return false;
    }
}

} // namespace

bool TranslatePicaGlslToMsl(
    std::string_view glslSource,
    PicaMslShaderStage stage,
    PicaMslShaderArtifact& artifact,
    std::string* error) {
    artifact = {};
    if (error != nullptr) {
        error->clear();
    }
    if (glslSource.empty()) {
        SetError(error, "PICA GLSL source is empty");
        return false;
    }

    try {
        std::string translatedSource(glslSource);
        if (stage == PicaMslShaderStage::Fragment &&
            translatedSource.find("pica_texture0") != std::string::npos) {
            const auto variant =
                BuildPicaNriFragmentShaderVariant(translatedSource);
            if (!variant.Applied) {
                SetError(error, "PICA Metal sampler ABI translation failed: " + variant.Error);
                return false;
            }
            translatedSource = variant.Source;
        }

        shaderc::Compiler compiler;
        shaderc::CompileOptions options;
        options.SetTargetEnvironment(
            shaderc_target_env_vulkan,
            shaderc_env_version_vulkan_1_1);
        options.SetOptimizationLevel(shaderc_optimization_level_performance);
        const shaderc_shader_kind kind =
            stage == PicaMslShaderStage::Vertex
                ? shaderc_vertex_shader
                : shaderc_fragment_shader;
        const char* name =
            stage == PicaMslShaderStage::Vertex
                ? "native_pica.vert"
                : "native_pica.frag";
        const auto result = compiler.CompileGlslToSpv(
            translatedSource.data(), translatedSource.size(), kind, name, options);
        if (result.GetCompilationStatus() != shaderc_compilation_status_success) {
            SetError(error, result.GetErrorMessage());
            return false;
        }
        const std::vector<uint32_t> spirv(result.cbegin(), result.cend());
        return TranslateSpirvToMslArtifact(spirv, stage, artifact, error);
    } catch (const std::exception& exception) {
        artifact = {};
        SetError(error, exception.what());
        return false;
    }
}

bool TranslatePicaGlslToMsl(
    std::string_view glslSource,
    PicaMslShaderStage stage,
    std::string& mslSource,
    std::string* error) {
    PicaMslShaderArtifact artifact;
    if (!TranslatePicaGlslToMsl(glslSource, stage, artifact, error)) {
        mslSource.clear();
        return false;
    }
    mslSource = std::move(artifact.Source);
    return true;
}

bool TranslatePicaSpirvToMsl(
    std::span<const uint32_t> spirv,
    std::string& mslSource,
    std::string* error) {
    // The SPIR-V overload is useful for precompiled inputs; infer the stage
    // from the module's execution model before applying the same ABI checks.
    mslSource.clear();
    if (error != nullptr) {
        error->clear();
    }
    if (spirv.empty() || spirv.front() != 0x07230203U) {
        SetError(error, "PICA shader input is not a valid SPIR-V module");
        return false;
    }
    try {
        std::vector<uint32_t> ownedSpirv(spirv.begin(), spirv.end());
        spirv_cross::CompilerMSL probe(std::move(ownedSpirv));
        const auto model = probe.get_entry_point().execution_model;
        const auto stage = model == spv::ExecutionModelVertex
            ? PicaMslShaderStage::Vertex
            : PicaMslShaderStage::Fragment;
        PicaMslShaderArtifact artifact;
        if (!TranslateSpirvToMslArtifact(spirv, stage, artifact, error)) {
            return false;
        }
        mslSource = std::move(artifact.Source);
        return true;
    } catch (const std::exception& exception) {
        SetError(error, exception.what());
        return false;
    }
}

} // namespace Fast::Renderer3ds
