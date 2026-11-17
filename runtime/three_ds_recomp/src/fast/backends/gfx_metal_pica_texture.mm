#include "fast/backends/gfx_metal_pica_texture.h"

#include <Metal/Metal.hpp>

#include "fast/extension/pica_texture_decode.h"

#include <algorithm>
#include <array>
#include <limits>
#include <optional>
#include <utility>
#include <vector>

namespace Fast::Backends {
namespace {

void SetError(std::string* error, std::string message) {
    if (error != nullptr) {
        *error = std::move(message);
    }
}

uint32_t NativeMipLevelCount(const Renderer3ds::PicaTextureView& texture) {
    uint32_t width = texture.Width;
    uint32_t height = texture.Height;
    uint32_t levels = 1U;
    while (width > 8U && height > 8U) {
        ++levels;
        width >>= 1U;
        height >>= 1U;
    }
    return std::min(levels, static_cast<uint32_t>(texture.MaxMipLevel) + 1U);
}

std::optional<size_t> NativeEncodedMipSize(
    uint8_t format, uint32_t width, uint32_t height) {
    static constexpr std::array<uint8_t, 14> kNibblesPerPixel{
        8U, 6U, 4U, 4U, 4U, 4U, 4U,
        2U, 2U, 2U, 1U, 1U, 1U, 2U};
    if (format >= kNibblesPerPixel.size() || width == 0U || height == 0U) {
        return std::nullopt;
    }
    const uint64_t tiledWidth =
        (static_cast<uint64_t>(std::max(8U, width)) + 7U) & ~7ULL;
    const uint64_t tiledHeight =
        (static_cast<uint64_t>(std::max(8U, height)) + 7U) & ~7ULL;
    const uint64_t nibbles =
        tiledWidth * tiledHeight * kNibblesPerPixel[format];
    const uint64_t bytes = (nibbles + 1U) / 2U;
    if (bytes > std::numeric_limits<size_t>::max()) {
        return std::nullopt;
    }
    return static_cast<size_t>(bytes);
}

bool DecodeWrap(
    uint8_t nativeWrap,
    MTL::SamplerAddressMode& addressMode) {
    switch (nativeWrap) {
        case 0:
            addressMode = MTL::SamplerAddressModeClampToEdge;
            return true;
        case 2:
        case 6:
        case 7:
            addressMode = MTL::SamplerAddressModeRepeat;
            return true;
        case 3:
            addressMode = MTL::SamplerAddressModeMirrorRepeat;
            return true;
        case 1:
            return false; // Clamp-to-border requires the PICA border colour.
        case 4:
        case 5:
        default:
            return false; // Asymmetric/unknown modes are not silently remapped.
    }
}

} // namespace

GfxMetalPicaTextureResource::~GfxMetalPicaTextureResource() {
    Reset();
}

bool GfxMetalPicaTextureResource::Create(
    MTL::Device* device,
    const Renderer3ds::PicaTextureView& texture,
    std::string* error) {
    if (error != nullptr) {
        error->clear();
    }
    Reset();
    if (device == nullptr || texture.Width == 0 || texture.Height == 0 ||
        texture.NativeBytes.empty()) {
        SetError(error, "PICA Metal texture upload requires a device and nonempty texture data");
        return false;
    }
    if (!texture.CopyReferences.empty()) {
        SetError(error, "PICA Metal texture is owned by an ordered GPU TextureCopy producer");
        return false;
    }
    if (texture.NativeType == 2U) {
        SetError(error, "PICA Metal Shadow2D integer textures require the dedicated shadow resource path");
        return false;
    }
    MTL::SamplerAddressMode addressS = MTL::SamplerAddressModeRepeat;
    MTL::SamplerAddressMode addressT = MTL::SamplerAddressModeRepeat;
    if (!DecodeWrap(texture.NativeWrapS, addressS) ||
        !DecodeWrap(texture.NativeWrapT, addressT)) {
        SetError(error, "PICA Metal texture uses a border or asymmetric wrap mode not yet represented by the draw state");
        return false;
    }
    const uint32_t mipLevels = NativeMipLevelCount(texture);
    if (mipLevels == 0U) {
        SetError(error, "PICA Metal texture has no valid mip levels");
        return false;
    }

    std::vector<std::vector<uint8_t>> decodedMips;
    std::vector<uint32_t> mipWidths;
    std::vector<uint32_t> mipHeights;
    decodedMips.reserve(mipLevels);
    mipWidths.reserve(mipLevels);
    mipHeights.reserve(mipLevels);
    size_t nativeOffset = 0U;
    std::string decodeError;
    for (uint32_t level = 0; level < mipLevels; ++level) {
        const uint32_t mipWidth =
            std::max(1U, static_cast<uint32_t>(texture.Width) >> level);
        const uint32_t mipHeight =
            std::max(1U, static_cast<uint32_t>(texture.Height) >> level);
        const auto encodedBytes =
            NativeEncodedMipSize(texture.NativeFormat, mipWidth, mipHeight);
        if (!encodedBytes || nativeOffset > texture.NativeBytes.size() ||
            *encodedBytes > texture.NativeBytes.size() - nativeOffset) {
            SetError(error, "PICA Metal native mip chain is truncated");
            return false;
        }
        std::vector<uint8_t> decoded;
        if (!Extension::DecodePicaTextureRgba8(
                texture.NativeFormat,
                static_cast<uint16_t>(mipWidth),
                static_cast<uint16_t>(mipHeight),
                texture.NativeBytes.subspan(nativeOffset, *encodedBytes),
                decoded, &decodeError)) {
            SetError(error, "PICA Metal texture mip decode failed: " + decodeError);
            return false;
        }
        const uint64_t expectedBytes =
            static_cast<uint64_t>(mipWidth) * mipHeight * 4U;
        if (expectedBytes > std::numeric_limits<size_t>::max() ||
            decoded.size() != static_cast<size_t>(expectedBytes)) {
            SetError(error, "PICA Metal texture mip decoded to an unexpected RGBA8 size");
            return false;
        }
        decodedMips.push_back(std::move(decoded));
        mipWidths.push_back(mipWidth);
        mipHeights.push_back(mipHeight);
        nativeOffset += *encodedBytes;
    }

    NS::AutoreleasePool* pool = NS::AutoreleasePool::alloc()->init();
    MTL::TextureDescriptor* textureDescriptor =
        MTL::TextureDescriptor::texture2DDescriptor(
            MTL::PixelFormatRGBA8Unorm, texture.Width, texture.Height,
            mipLevels > 1U);
    if (textureDescriptor == nullptr) {
        pool->release();
        SetError(error, "Metal could not allocate a PICA texture descriptor");
        return false;
    }
    textureDescriptor->setMipmapLevelCount(mipLevels);
    textureDescriptor->setStorageMode(MTL::StorageModeShared);
    textureDescriptor->setUsage(MTL::TextureUsageShaderRead);
    mTexture = device->newTexture(textureDescriptor);
    if (mTexture == nullptr) {
        pool->release();
        SetError(error, "Metal could not allocate a PICA RGBA8 texture");
        return false;
    }
    for (uint32_t level = 0; level < mipLevels; ++level) {
        mTexture->replaceRegion(
            MTL::Region::Make2D(
                0, 0, mipWidths[level], mipHeights[level]),
            level, decodedMips[level].data(),
            static_cast<NS::UInteger>(mipWidths[level]) * 4U);
    }

    MTL::SamplerDescriptor* samplerDescriptor =
        MTL::SamplerDescriptor::alloc()->init();
    if (samplerDescriptor == nullptr) {
        pool->release();
        Reset();
        SetError(error, "Metal could not allocate a PICA sampler descriptor");
        return false;
    }
    samplerDescriptor->setMinFilter(
        texture.MinLinear ? MTL::SamplerMinMagFilterLinear
                          : MTL::SamplerMinMagFilterNearest);
    samplerDescriptor->setMagFilter(
        texture.MagLinear ? MTL::SamplerMinMagFilterLinear
                          : MTL::SamplerMinMagFilterNearest);
    samplerDescriptor->setMipFilter(
        mipLevels > 1U
            ? (texture.MipLinear ? MTL::SamplerMipFilterLinear
                                 : MTL::SamplerMipFilterNearest)
            : MTL::SamplerMipFilterNotMipmapped);
    const uint32_t maxMip = mipLevels - 1U;
    const uint32_t minLod = std::min<uint32_t>(texture.MinMipLevel, maxMip);
    const uint32_t maxLod = std::max(
        minLod, std::min<uint32_t>(texture.MaxMipLevel, maxMip));
    samplerDescriptor->setLodMinClamp(static_cast<float>(minLod));
    samplerDescriptor->setLodMaxClamp(static_cast<float>(maxLod));
    samplerDescriptor->setSAddressMode(addressS);
    samplerDescriptor->setTAddressMode(addressT);
    samplerDescriptor->setSupportArgumentBuffers(true);
    mSampler = device->newSamplerState(samplerDescriptor);
    samplerDescriptor->release();
    pool->release();

    if (mSampler == nullptr) {
        Reset();
        SetError(error, "Metal could not create a PICA sampler state");
        return false;
    }
    mWidth = texture.Width;
    mHeight = texture.Height;
    return true;
}

void GfxMetalPicaTextureResource::Reset() {
    if (mSampler != nullptr) {
        mSampler->release();
        mSampler = nullptr;
    }
    if (mTexture != nullptr) {
        mTexture->release();
        mTexture = nullptr;
    }
    mWidth = 0;
    mHeight = 0;
}

bool GfxMetalPicaTextureResource::IsValid() const {
    return mTexture != nullptr && mSampler != nullptr;
}

MTL::Texture* GfxMetalPicaTextureResource::Texture() const {
    return mTexture;
}

MTL::SamplerState* GfxMetalPicaTextureResource::Sampler() const {
    return mSampler;
}

uint32_t GfxMetalPicaTextureResource::Width() const {
    return mWidth;
}

uint32_t GfxMetalPicaTextureResource::Height() const {
    return mHeight;
}

} // namespace Fast::Backends
