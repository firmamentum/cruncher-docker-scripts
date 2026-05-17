#!/usr/bin/env bash
# =============================================================================
# 05-setup-opencl.sh — OpenCL Vendor Configuration
# =============================================================================
set -euo pipefail

echo "================================================"
echo "  05 — Configuring OpenCL"
echo "================================================"

# --- NVIDIA OpenCL ICD ---
mkdir -p /etc/OpenCL/vendors
echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd
echo "Created /etc/OpenCL/vendors/nvidia.icd"

# --- Symlink OpenCL libraries ---
if [ -f /usr/local/cuda/lib64/libOpenCL.so.1 ]; then
    mkdir -p /usr/lib/x86_64-linux-gnu
    ln -sfn /usr/local/cuda/lib64/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so.1
    ln -sfn /usr/lib/x86_64-linux-gnu/libOpenCL.so.1 /usr/lib/x86_64-linux-gnu/libOpenCL.so
    echo "OpenCL library symlinks created"
else
    echo "Warning: /usr/local/cuda/lib64/libOpenCL.so.1 not found, skipping symlinks"
fi

# --- NVIDIA library paths ---
echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf
echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf
ldconfig

echo ""
echo "✅ OpenCL configured"
echo ""
