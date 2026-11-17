#pragma once

#include <string>

struct SDL_Renderer;

namespace MTL {
class Device;
class CommandQueue;
}

namespace CA {
class MetalLayer;
}

namespace Fast::Backends {

// Owns the Metal device and command queue used by the modern PICA backend.
// The CAMetalLayer is SDL-owned and is never retained or released here.
class GfxMetalPicaDevice {
  public:
    GfxMetalPicaDevice() = default;
    ~GfxMetalPicaDevice();

    GfxMetalPicaDevice(const GfxMetalPicaDevice&) = delete;
    GfxMetalPicaDevice& operator=(const GfxMetalPicaDevice&) = delete;

    [[nodiscard]] bool Initialize(SDL_Renderer* renderer, std::string* error = nullptr);
    [[nodiscard]] bool Initialize(CA::MetalLayer* layer, std::string* error = nullptr);
    void Shutdown();
    [[nodiscard]] bool IsReady() const;
    [[nodiscard]] MTL::Device* Device() const;
    [[nodiscard]] MTL::CommandQueue* CommandQueue() const;
    [[nodiscard]] CA::MetalLayer* Layer() const;

    // Waits for all previously submitted work on this queue to complete.
    [[nodiscard]] bool WaitIdle(std::string* error = nullptr);

  private:
    MTL::Device* mDevice = nullptr;
    MTL::CommandQueue* mCommandQueue = nullptr;
    CA::MetalLayer* mLayer = nullptr;
};

} // namespace Fast::Backends
