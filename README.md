# alphaos-kernel

Kernel patch selection, configuration, and build scripts (Tier 2: curated patch set on vanilla mainline) for **Project Alpha (AlphaOS)**.

## Overview

This repository contains the curated Linux kernel configuration, build automation, Secure Boot signing pipeline, and patch set for AlphaOS.

- **Target Mainline**: Linux 7.3.0-rc4 (`7.3.0-rc4-alpha`)
- **Tuned for**: Highest possible compilation throughput, low-latency preemption, memory pressure resilience, and eBPF extensibility.
- **Packaging**: Debian binary packages (`.deb`) with UEFI Secure Boot Authenticode signature and pre-bundled initramfs.

## Repository Structure

```
alphaos-kernel/
├── build.sh                                 # Automated kernel build & packaging script
├── configs/
│   ├── alpha-7.3.config                    # Active Linux 7.3 configuration (compilation power optimized)
│   ├── alpha-6.19.config                   # Linux 6.19 kernel configuration
│   └── alpha-6.12.config                   # Linux 6.12 kernel configuration
├── patches/
│   └── builddeb-shim-initramfs.patch       # Builddeb patch for shim signing & initramfs bundling
├── certs/
│   └── alphaos-shim.der                    # Public MOK certificate for UEFI Secure Boot enrollment
├── linux/                                  # Linux kernel submodule (mainline)
└── .gitmodules                             # Submodule definition
```

## Compilation Power Optimizations

The kernel configuration includes targeted performance tuning for heavy compilation workloads (GCC, Clang, Rustc, multi-core parallel builds):
- **CPU Governor**: `CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y` locks all CPU cores at maximum boost frequency without governor ramp-up latency.
- **Memory Pressure & Swap Prevention**: `CONFIG_ZSWAP=y` enabled by default with Zstandard (`zstd`) compression to compress evicted memory in RAM instead of thrashing disk swap during memory-intensive linker stages.
- **Hugepages**: `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=y` and `CONFIG_THP_SWAP=y` to drastically reduce DTLB misses and page walk overhead for compiler ASTs and memory maps.
- **Page Reclaiming**: `CONFIG_LRU_GEN=y` (Multi-Gen LRU) enabled for fast, modern page reclamation under high allocation concurrency.
- **Task Scheduling**: `CONFIG_SCHED_AUTOGROUP=y` and `CONFIG_SCHED_CLASS_EXT=y` (sched-ext) for extensible BPF scheduling and interactive session protection during `-j$(nproc)` builds.
- **Module Compression**: `CONFIG_MODULE_COMPRESS_ZSTD=y` for fast multi-threaded compression during build and rapid boot-time decompression.
- **Timer Frequency & Preemption**: `CONFIG_HZ=250` (75% lower timer interrupt overhead) and `CONFIG_PREEMPT_DYNAMIC=y` allowing runtime switching (`preempt=voluntary`).

## Prerequisites

On a Debian 13 (Trixie) or Debian-based build host:

```bash
sudo apt update
sudo apt install build-essential libncurses-dev bison flex libssl-dev libelf-dev \
    bc sbsigntool fakeroot initramfs-tools zstd libdw-dev
```

## Quick Start Build

1. Initialize submodule (if cloning fresh):
   ```bash
   git submodule update --init --depth 1
   ```

2. Run the build script:
   ```bash
   ./build.sh
   ```

The script automatically:
- Checks build dependencies
- Generates/verifies the AlphaOS Secure Boot Shim keypair in `certs/`
- Applies builddeb packaging enhancements
- Builds the kernel with all CPU cores
- Signs the EFI PE executable (`vmlinuz`) with Authenticode
- Generates and bundles the initramfs (`initrd.img`) into `/boot/`
- Emits Debian `.deb` packages and standalone boot images into the repository root.

## Secure Boot / Shim Enrollment

To enroll the generated kernel key in UEFI Secure Boot via MOK:

```bash
sudo mokutil --import certs/alphaos-shim.der
```

Set a one-time password, reboot, and confirm enrollment in the blue Shim MOK management screen.
