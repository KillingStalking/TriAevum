#!/usr/bin/env python3
"""Configure and build the first iOS cross-compilation smoke target on Windows.

This is intentionally a library-only smoke build. It does not create an .app or
IPA and does not claim that the modern PICA renderer has a Metal implementation.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOLCHAIN = ROOT / "cmake" / "toolchains" / "ios-windows.cmake"
DOCTOR = ROOT / "win" / "doctor.py"
DEFAULT_TARGET = "oot3d_metal_shader_translation"


def run(command: list[str], cwd: Path) -> None:
    print("+", subprocess.list2cmdline(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build-ios-windows")
    parser.add_argument("--config", default="Release", choices=("Debug", "Release", "RelWithDebInfo", "MinSizeRel"))
    parser.add_argument("--target", default=DEFAULT_TARGET,
                        help=f"CMake target to build (default: {DEFAULT_TARGET})")
    parser.add_argument("--jobs", type=int, default=max(1, os.cpu_count() or 1))
    parser.add_argument("--clean", action="store_true", help="remove the build directory before configuring")
    args = parser.parse_args()

    if sys.platform != "win32":
        parser.error("This driver is for Windows hosts")
    if not TOOLCHAIN.is_file():
        parser.error(f"toolchain file is missing: {TOOLCHAIN}")
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")

    if args.clean and args.build_dir.exists():
        import shutil
        shutil.rmtree(args.build_dir)

    run([sys.executable, str(DOCTOR)], ROOT)
    args.build_dir = args.build_dir.resolve()
    configure = [
        "cmake", "-S", str(ROOT), "-B", str(args.build_dir), "-G", "Ninja",
        f"-DCMAKE_TOOLCHAIN_FILE={TOOLCHAIN}",
        f"-DCMAKE_BUILD_TYPE={args.config}",
        "-DOOT3D_ENABLE_VULKAN_RENDERER=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_VULKAN=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_METAL_PICA=ON",
        "-DTHREE_DS_RECOMP_ENABLE_NRI=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_NRI_UPSCALER_SDKS=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_DLSS_MODULE=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_SSSR=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_CACAO=OFF",
        "-DTHREE_DS_RECOMP_ENABLE_IMMERSE=OFF",
        "-DTHREE_DS_RECOMP_BUILD_TESTS=OFF",
    ]
    run(configure, ROOT)
    run(["cmake", "--build", str(args.build_dir), "--target", args.target,
         "--config", args.config, "--parallel", str(args.jobs)], ROOT)
    print(f"Smoke target built: {args.target}")
    print("Metal PICA shader/device/frame foundation built for iOS.")
    print("No iOS app bundle or IPA was produced by this smoke build.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
