#!/usr/bin/env python3
"""Validate the Windows-hosted iOS cross-compilation toolchain."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path


def locate(name: str, roots: list[Path], *, path_fallback: bool = True) -> Path | None:
    for root in roots:
        candidate = root / name
        if candidate.is_file():
            return candidate
    if path_fallback:
        found = shutil.which(name)
        if found:
            return Path(found)
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    llvm_root = Path(os.environ["LLVM_ROOT"]) if os.environ.get("LLVM_ROOT") else None
    sdk_root = Path(os.environ["IOS_SDK_ROOT"]) if os.environ.get("IOS_SDK_ROOT") else None
    llvm_bins = [llvm_root / "bin"] if llvm_root else []

    if not llvm_root:
        errors.append("LLVM_ROOT is not set")
    if not sdk_root:
        errors.append("IOS_SDK_ROOT is not set")
    elif not (sdk_root / "System" / "Library" / "Frameworks").is_dir():
        errors.append(f"IOS_SDK_ROOT is not a valid iPhoneOS SDK: {sdk_root}")

    required = {
        "clang": ("clang.exe", "clang"),
        "clang++": ("clang++.exe", "clang++"),
        "ld64.lld": ("ld64.lld.exe", "ld64.lld"),
        "llvm-ar": ("llvm-ar.exe", "llvm-ar"),
        "llvm-ranlib": ("llvm-ranlib.exe", "llvm-ranlib"),
        "llvm-nm": ("llvm-nm.exe", "llvm-nm"),
        "cmake": ("cmake.exe", "cmake"),
        "ninja": ("ninja.exe", "ninja"),
    }
    resolved: dict[str, Path] = {}
    for label, candidates in required.items():
        roots = llvm_bins if label in {"clang", "clang++", "ld64.lld", "llvm-ar", "llvm-ranlib", "llvm-nm"} else []
        hit = next((candidate for name in candidates
                    if (candidate := locate(name, roots, path_fallback=label not in {"clang", "clang++", "ld64.lld", "llvm-ar", "llvm-ranlib", "llvm-nm"}))), None)
        if hit is None:
            where = "LLVM_ROOT/bin" if label in {"clang", "clang++", "ld64.lld", "llvm-ar", "llvm-ranlib", "llvm-nm"} else "PATH"
            errors.append(f"{label} not found ({where})")
        else:
            resolved[label] = hit

    # Metal tools are optional for the first C++ smoke target, but required
    # before generating or compiling precompiled .metallib assets.
    metal = locate("metal.exe", []) or locate("metal", [])
    metallib = locate("metallib.exe", []) or locate("metallib", [])
    if not args.quiet:
        for label, path in resolved.items():
            print(f"[OK] {label}: {path}")
        if sdk_root and sdk_root.is_dir():
            print(f"[OK] iPhoneOS SDK: {sdk_root}")
        print(f"[{'OK' if metal else 'INFO'}] metal: {metal or 'not installed (not needed for C++ smoke target)'}")
        print(f"[{'OK' if metallib else 'INFO'}] metallib: {metallib or 'not installed (not needed for C++ smoke target)'}")

    if errors:
        for error in errors:
            print(f"[ERROR] {error}", file=sys.stderr)
        return 2
    if not args.quiet:
        print("Toolchain checks passed. This validates tools only, not Apple licensing or runtime compatibility.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
