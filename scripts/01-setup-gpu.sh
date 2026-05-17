#!/usr/bin/env bash
# =============================================================================
# 01-setup-gpu.sh — CUDA 12.8 Development Libraries
# =============================================================================
# Installs NVIDIA CUDA development toolkit on top of the cuda runtime base image.
# Swap this script for 01-setup-gpu-rocm.sh to target AMD GPUs instead.
#
# Base image: nvidia/cuda:12.8.1-runtime-ubuntu22.04
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  01 — Setting up CUDA 12.8 development libraries"
echo "================================================"

# --- Detect architecture ---
ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
echo "Detected architecture: $ARCH"

# --- Version pins (CUDA 12.8.1) ---
NV_CUDA_LIB_VERSION="12.8.1-1"
NV_CUDA_CUDART_DEV_VERSION="12.8.90-1"
NV_NVML_DEV_VERSION="12.8.90-1"
NV_LIBCUSPARSE_DEV_VERSION="12.5.8.93-1"
NV_LIBNPP_DEV_VERSION="12.3.3.100-1"
NV_LIBNPP_DEV_PACKAGE="libnpp-dev-12-8=${NV_LIBNPP_DEV_VERSION}"

NV_LIBCUBLAS_DEV_PACKAGE_NAME="libcublas-dev-12-8"
NV_LIBCUBLAS_DEV_VERSION="12.8.4.1-1"
NV_LIBCUBLAS_DEV_PACKAGE="${NV_LIBCUBLAS_DEV_PACKAGE_NAME}=${NV_LIBCUBLAS_DEV_VERSION}"

NV_CUDA_NSIGHT_COMPUTE_VERSION="12.8.1-1"
NV_CUDA_NSIGHT_COMPUTE_DEV_PACKAGE="cuda-nsight-compute-12-8=${NV_CUDA_NSIGHT_COMPUTE_VERSION}"

NV_LIBNCCL_DEV_PACKAGE_NAME="libnccl-dev"
NV_LIBNCCL_DEV_PACKAGE_VERSION="2.25.1-1"
NV_LIBNCCL_DEV_PACKAGE="${NV_LIBNCCL_DEV_PACKAGE_NAME}=${NV_LIBNCCL_DEV_PACKAGE_VERSION}+cuda12.8"

# nvprof is only available on amd64
NVPROF_PACKAGES=""
if [ "$ARCH" = "amd64" ]; then
    NV_NVPROF_VERSION="12.8.90-1"
    NVPROF_PACKAGES="cuda-nvprof-12-8=${NV_NVPROF_VERSION}"
fi

# --- Install CUDA dev packages ---
echo "Installing CUDA development packages..."
apt-get update && apt-get install -y --no-install-recommends \
    cuda-cudart-dev-12-8=${NV_CUDA_CUDART_DEV_VERSION} \
    cuda-command-line-tools-12-8=${NV_CUDA_LIB_VERSION} \
    cuda-minimal-build-12-8=${NV_CUDA_LIB_VERSION} \
    cuda-libraries-dev-12-8=${NV_CUDA_LIB_VERSION} \
    cuda-nvml-dev-12-8=${NV_NVML_DEV_VERSION} \
    ${NVPROF_PACKAGES} \
    ${NV_LIBNPP_DEV_PACKAGE} \
    libcusparse-dev-12-8=${NV_LIBCUSPARSE_DEV_VERSION} \
    ${NV_LIBCUBLAS_DEV_PACKAGE} \
    ${NV_LIBNCCL_DEV_PACKAGE} \
    ${NV_CUDA_NSIGHT_COMPUTE_DEV_PACKAGE} \
    && rm -rf /var/lib/apt/lists/*

# --- Pin packages to prevent auto-upgrade ---
echo "Pinning CUDA packages..."
apt-mark hold ${NV_LIBCUBLAS_DEV_PACKAGE_NAME} ${NV_LIBNCCL_DEV_PACKAGE_NAME}

# --- Set environment variables for subsequent scripts ---
ENV_FILE="/etc/profile.d/cuda-env.sh"
cat > "$ENV_FILE" << 'EOF'
export PATH="/usr/local/cuda/bin:/opt/nvidia/nsight-compute-cli:${PATH}"
export LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/nvidia/lib64:${LD_LIBRARY_PATH}"
export LIBRARY_PATH="/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}"
export NVIDIA_VISIBLE_DEVICES=all
export NVIDIA_DRIVER_CAPABILITIES=compute,utility
EOF

# Source it for this session
# shellcheck source=/dev/null
source "$ENV_FILE"

echo ""
echo "✅ CUDA 12.8 development libraries installed successfully"
nvcc --version 2>/dev/null || echo "(nvcc available after PATH is set)"
echo ""
