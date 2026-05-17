# =============================================================================
# Dockerfile — Modular Cruncher Base Image
# =============================================================================
# Thin orchestrator that runs build-time scripts (01-07) to install all public
# infrastructure. Deploy-time scripts (08-12) run AFTER the container boots
# on Vast.ai, triggered by token-watcher.sh when a GitHub token arrives.
#
# Build:  docker build -t homelander0x/cruncher-base .
# Push:   docker push homelander0x/cruncher-base:latest
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
ENV LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENV LIBRARY_PATH="/usr/local/cuda/lib64/stubs"

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

# Pre-create onstart.sh — Vast.ai automatically runs this on boot
RUN cat > /root/onstart.sh << 'ONSTART'
#!/bin/bash
# Auto-start services on container boot

# Fix .bash_profile permission (Vast.ai creates it as root-only,
# which causes "Permission denied" spam on su - postgres calls)
chmod 644 /root/.bash_profile 2>/dev/null || true

# Start Redis
if command -v redis-server &>/dev/null && [ -f /etc/redis/redis.conf ]; then
    redis-server /etc/redis/redis.conf
    echo "Redis started."
fi

# Start PostgreSQL (if cluster exists)
PG_VERSION=$(find /usr/lib/postgresql/ -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
PG_DATA="/var/lib/postgresql/${PG_VERSION}/main"
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
if [ -n "$PG_VERSION" ] && [ -d "$PG_DATA" ]; then
    su - postgres -c "$PG_BIN/pg_ctl -D $PG_DATA -l /var/log/postgresql/postgresql-${PG_VERSION}-main.log start" 2>/dev/null
    echo "PostgreSQL $PG_VERSION started."
fi

# Start token-watcher daemon
/usr/local/bin/deploy/token-watcher.sh &

# Start cron (for auto-pull)
service cron start 2>/dev/null
ONSTART
RUN chmod +x /root/onstart.sh

WORKDIR /root

# Expose ports: SSH (22), token-watcher HTTP (9191)
EXPOSE 22 9191

# CMD as fallback for non-Vast environments (Vast overrides this with /.launch)
CMD ["/bin/bash", "-c", "/usr/local/bin/deploy/token-watcher.sh & exec bash"]
