#pragma once

#include "fast/renderer3ds/pica_render_backend.h"

#include <array>
#include <cstdint>

namespace Fast::Renderer3ds {

struct PicaMemoryFillColor {
    std::array<float, 4> Value{};
};

struct PicaMemoryFillDepthStencil {
    float Depth = 1.0F;
    uint8_t Stencil = 0U;
};

[[nodiscard]] constexpr uint32_t PicaColorBytesPerPixel(uint8_t nativeFormat) noexcept {
    return nativeFormat == 0U ? 4U : (nativeFormat == 1U ? 3U : 2U);
}

[[nodiscard]] constexpr uint32_t PicaDepthBytesPerPixel(uint8_t nativeFormat) noexcept {
    return nativeFormat == 0U ? 2U : (nativeFormat == 2U ? 3U : 4U);
}

[[nodiscard]] constexpr uint32_t PicaMemoryFillElementSize(uint16_t control) noexcept {
    return (control & (1U << 9U)) != 0U ? 4U : ((control & (1U << 8U)) != 0U ? 3U : 2U);
}

[[nodiscard]] inline uint8_t PicaMemoryFillByte(const PicaMemoryFillView& fill, uint32_t index) noexcept {
    const uint32_t shift =
        (index % PicaMemoryFillElementSize(fill.Control)) * 8U;
    return static_cast<uint8_t>(fill.Value >> shift);
}

[[nodiscard]] inline PicaMemoryFillColor DecodePicaMemoryFillColor(
    const PicaMemoryFillView& fill, uint8_t nativeFormat) noexcept {
    const uint8_t b0 = PicaMemoryFillByte(fill, 0U);
    const uint8_t b1 = PicaMemoryFillByte(fill, 1U);
    const uint8_t b2 = PicaMemoryFillByte(fill, 2U);
    const uint8_t b3 = PicaMemoryFillByte(fill, 3U);
    const auto unorm = [](uint32_t value, uint32_t maximum) {
        return static_cast<float>(value) / static_cast<float>(maximum);
    };

    PicaMemoryFillColor result;
    if (nativeFormat == 0U) {
        result.Value = {
            unorm(b3, 0xFFU), unorm(b2, 0xFFU),
            unorm(b1, 0xFFU), unorm(b0, 0xFFU)};
    } else if (nativeFormat == 1U) {
        result.Value = {
            unorm(b2, 0xFFU), unorm(b1, 0xFFU),
            unorm(b0, 0xFFU), 1.0F};
    } else {
        const uint32_t packed =
            static_cast<uint32_t>(b0) | (static_cast<uint32_t>(b1) << 8U);
        if (nativeFormat == 2U) {
            result.Value = {
                unorm((packed >> 11U) & 0x1FU, 0x1FU),
                unorm((packed >> 5U) & 0x3FU, 0x3FU),
                unorm(packed & 0x1FU, 0x1FU), 1.0F};
        } else if (nativeFormat == 3U) {
            result.Value = {
                unorm((packed >> 11U) & 0x1FU, 0x1FU),
                unorm((packed >> 6U) & 0x1FU, 0x1FU),
                unorm((packed >> 1U) & 0x1FU, 0x1FU),
                static_cast<float>(packed & 1U)};
        } else {
            result.Value = {
                unorm((packed >> 12U) & 0xFU, 0xFU),
                unorm((packed >> 8U) & 0xFU, 0xFU),
                unorm((packed >> 4U) & 0xFU, 0xFU),
                unorm(packed & 0xFU, 0xFU)};
        }
    }
    return result;
}

[[nodiscard]] inline PicaMemoryFillDepthStencil DecodePicaMemoryFillDepthStencil(
    const PicaMemoryFillView& fill, uint8_t nativeFormat) noexcept {
    const uint32_t b0 = PicaMemoryFillByte(fill, 0U);
    const uint32_t b1 = PicaMemoryFillByte(fill, 1U);
    const uint32_t b2 = PicaMemoryFillByte(fill, 2U);
    const uint32_t depth = nativeFormat == 0U ? b0 | (b1 << 8U) : b0 | (b1 << 8U) | (b2 << 16U);
    const uint32_t maximum = nativeFormat == 0U ? 0xFFFFU : 0xFFFFFFU;
    return {static_cast<float>(depth) / static_cast<float>(maximum),
            static_cast<uint8_t>(nativeFormat == 3U ? PicaMemoryFillByte(fill, 3U) : 0U)};
}

} // namespace Fast::Renderer3ds
