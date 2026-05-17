# =============================================================================
# Dockerfile — Modular Cruncher Base Image
# =============================================================================
# Thin orchestrator that runs build-time scripts (01-07) to install all public
# infrastructure. Deploy-time scripts (08-12) run AFTER the container boots
# on Vast.ai, triggered by token-watcher.sh when a GitHub token arrives.
#
# Build:  docker build -t firmamentum/cruncher-base .
# Push:   docker push firmamentum/cruncher-base:latest
#
# For development (COPY from local):
#   docker build -t firmamentum/cruncher-base .
#
# For production (curl from GitHub — uncomment the curl block below and
# comment out the COPY block):
#   docker build --build-arg SCRIPTS_BASE=https://raw.githubusercontent.com/firmamentum/deploy/main/scripts -t firmamentum/cruncher-base .
# =============================================================================

ARG IMAGE_NAME=nvidia/cuda
FROM ${IMAGE_NAME}:12.8.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Africa/Nairobi

# --- Copy all scripts into the image ---
# Development mode: COPY from local (no need for GitHub push first)
ARG DEPLOY_DIR=/usr/local/bin/deploy
COPY scripts/ ${DEPLOY_DIR}/
RUN chmod +x ${DEPLOY_DIR}/*.sh

# --- Production mode (uncomment to curl from GitHub instead): ---
# ARG SCRIPTS_BASE=https://raw.githubusercontent.com/firmamentum/deploy/main/scripts
# ARG DEPLOY_DIR=/usr/local/bin/deploy
# RUN mkdir -p ${DEPLOY_DIR} && \
#     for script in \
#       01-setup-gpu.sh 02-setup-system.sh 03-setup-go.sh \
#       04-setup-python-conan.sh 05-setup-opencl.sh \
#       06-setup-postgres.sh 07-setup-redis.sh \
#       08-clone-repos.sh 09-build-deps.sh 10-build-cruncher.sh \
#       11-setup-databases.sh 12-setup-services.sh \
#       token-watcher.sh repo-setup.sh; do \
#         curl -fsSL ${SCRIPTS_BASE}/${script} -o ${DEPLOY_DIR}/${script} && \
#         chmod +x ${DEPLOY_DIR}/${script}; \
#     done

# =============================================================================
# Build-time: Public infrastructure (each RUN = cached Docker layer)
# =============================================================================

# 01 — CUDA 12.8 development libraries
RUN ${DEPLOY_DIR}/01-setup-gpu.sh

# Set CUDA environment (persists across RUN layers)
ENV PATH="/usr/local/cuda/bin:/opt/nvidia/nsight-compute-cli:/usr/local/nvidia/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/nvidia/lib64:${LD_LIBRARY_PATH}"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV LIBRARY_PATH="/usr/local/cuda/lib64/stubs:${LIBRARY_PATH}"

# 02 — System packages, timezone, git config, speedtest
RUN ${DEPLOY_DIR}/02-setup-system.sh

# 03 — Go 1.24.0
RUN ${DEPLOY_DIR}/03-setup-go.sh

# Set Go environment (persists across RUN layers)
ENV PATH="/usr/local/go/bin:${PATH}"

# 04 — Conan (C++ package manager)
RUN ${DEPLOY_DIR}/04-setup-python-conan.sh

# 05 — OpenCL vendor config
RUN ${DEPLOY_DIR}/05-setup-opencl.sh

# 06 — PostgreSQL server + dev headers
RUN ${DEPLOY_DIR}/06-setup-postgres.sh

# 07 — Redis configuration
RUN ${DEPLOY_DIR}/07-setup-redis.sh

# =============================================================================
# Final setup
# =============================================================================

RUN mkdir -p /root/logs && touch /root/.no_auto_tmux

WORKDIR /root

# Deploy-time scripts (08-12) are NOT run here.
# They execute when token-watcher.sh detects a GitHub token after container boot.
#
# Container entry point should start token-watcher.sh:
#   /usr/local/bin/deploy/token-watcher.sh &
