# FPGA Development Container for iCESugar-Pro
# Using precompiled OSS CAD Suite from YosysHQ

FROM debian:bookworm-slim

LABEL maintainer="FPGA Development"
LABEL description="Open source FPGA toolchain for iCESugar-Pro (ECP5)"

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    g++ \
    git \
    libftdi1-2 \
    libusb-1.0-0 \
    libudev1 \
    make \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    usbutils \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Download and install OSS CAD Suite (precompiled toolchain)
# Includes: yosys, nextpnr, prjtrellis, icarus verilog, gtkwave, verilator, etc.
ARG OSS_CAD_VERSION=2024-09-23
ARG OSS_CAD_DATE=20240923
RUN curl -L https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${OSS_CAD_VERSION}/oss-cad-suite-linux-x64-${OSS_CAD_DATE}.tgz \
    | tar -xzC /opt

# Add OSS CAD Suite to PATH
ENV PATH="/opt/oss-cad-suite/bin:${PATH}"

# Install Python tools for FPGA development
RUN pip3 install --break-system-packages \
    amaranth \
    cocotb \
    cocotb-bus

# Create workspace directory
WORKDIR /workspace

# Create non-root user for development
RUN useradd -m -s /bin/bash fpga && \
    chown -R fpga:fpga /workspace

# Add udev rules for FTDI devices (used when running with --privileged)
RUN mkdir -p /etc/udev/rules.d && \
    echo 'ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="602b", MODE="0666", GROUP="plugdev"' > /etc/udev/rules.d/99-icesugar.rules

# Default to fpga user
USER fpga

# Verify installations
RUN yosys --version && \
    nextpnr-ecp5 --version && \
    iverilog -V | head -1

CMD ["/bin/bash"]
