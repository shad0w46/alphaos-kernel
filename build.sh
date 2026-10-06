#!/bin/bash
# ==============================================================================
# AlphaOS Kernel Build Script
# Configures, builds, signs (Secure Boot / Shim), and packages Linux 7 for AlphaOS
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

KERNEL_DIR="${SCRIPT_DIR}/linux"
CONFIG_FILE="${SCRIPT_DIR}/configs/alpha-7.3.config"
PATCH_FILE="${SCRIPT_DIR}/patches/builddeb-shim-initramfs.patch"
CERTS_DIR="${SCRIPT_DIR}/certs"
SHIM_PRIV="${CERTS_DIR}/alphaos-shim.priv"
SHIM_PEM="${CERTS_DIR}/alphaos-shim.pem"
SHIM_DER="${CERTS_DIR}/alphaos-shim.der"
JOBS="$(nproc)"

echo "==> [1/5] Checking build dependencies..."
for cmd in make gcc openssl dpkg-buildpackage fakeroot unshare; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required tool '$cmd' is not installed." >&2
        exit 1
    fi
done

# Ensure PATH includes sbin and local user bin
export PATH="/usr/sbin:/sbin:${HOME}/.local/usr/bin:${PATH}"

if ! command -v sbsign >/dev/null 2>&1; then
    echo "Warning: 'sbsign' not found in PATH. Attempting ~/.local/usr/bin/sbsign..."
    if [ ! -x "${HOME}/.local/usr/bin/sbsign" ]; then
        echo "Error: sbsign is required for UEFI Shim signing. Install 'sbsigntool'." >&2
        exit 1
    fi
fi

if [ ! -d "${KERNEL_DIR}" ]; then
    echo "Error: kernel source directory '${KERNEL_DIR}' not found." >&2
    echo "Please clone or initialize the linux submodule." >&2
    exit 1
fi

echo "==> [2/5] Setting up AlphaOS Secure Boot Shim Keys..."
mkdir -p "${CERTS_DIR}"
if [ ! -f "${SHIM_PRIV}" ] || [ ! -f "${SHIM_PEM}" ]; then
    echo "Generating new AlphaOS Secure Boot Shim keypair..."
    openssl req -new -x509 -newkey rsa:2048 -nodes -days 3650 \
        -subj "/CN=AlphaOS Secure Boot Shim Key/" \
        -keyout "${SHIM_PRIV}.tmp" -out "${SHIM_PEM}"
    cat "${SHIM_PEM}" >> "${SHIM_PRIV}.tmp"
    mv "${SHIM_PRIV}.tmp" "${SHIM_PRIV}"
    chmod 600 "${SHIM_PRIV}"
fi

if [ ! -f "${SHIM_DER}" ]; then
    openssl x509 -in "${SHIM_PEM}" -outform DER -out "${SHIM_DER}"
fi

# Sync keys into linux/certs for kernel module signing
mkdir -p "${KERNEL_DIR}/certs"
cp "${SHIM_PRIV}" "${KERNEL_DIR}/certs/alphaos-shim.priv"
cp "${SHIM_PEM}" "${KERNEL_DIR}/certs/alphaos-shim.pem"
cp "${SHIM_DER}" "${KERNEL_DIR}/certs/alphaos-shim.der"

echo "==> [3/5] Applying builddeb shim & initramfs patch..."
if [ -f "${PATCH_FILE}" ]; then
    if git -C "${KERNEL_DIR}" apply --check "${PATCH_FILE}" >/dev/null 2>&1; then
        git -C "${KERNEL_DIR}" apply "${PATCH_FILE}"
        echo "Successfully applied ${PATCH_FILE}."
    else
        echo "Patch already applied or modified."
    fi
fi

echo "==> [4/5] Preparing kernel configuration..."
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Error: config file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

cp "${CONFIG_FILE}" "${KERNEL_DIR}/.config"
make -C "${KERNEL_DIR}" olddefconfig
make -C "${KERNEL_DIR}" LOCALVERSION="" syncconfig
make -C "${KERNEL_DIR}" LOCALVERSION="" prepare

RELEASE="$(make -s -C "${KERNEL_DIR}" LOCALVERSION="" kernelrelease)"
echo "==> Target Kernel Release: ${RELEASE}"

echo "==> [5/5] Building kernel, signing EFI binary, bundling initramfs, and packaging..."
make -C "${KERNEL_DIR}" -j"${JOBS}" LOCALVERSION="" KDEB_PKGVERSION=1 bindeb-pkg

echo ""
echo "===================================================================="
echo "Build complete! Artifacts produced in ${SCRIPT_DIR}:"
echo "  - Kernel Image Deb: linux-image-${RELEASE}_1_amd64.deb"
echo "  - Headers Deb:      linux-headers-${RELEASE}_1_amd64.deb"
echo "  - Signed vmlinuz:   vmlinuz-${RELEASE}"
echo "  - Standalone initrd:initrd.img-${RELEASE}"
echo "===================================================================="
