#!/bin/bash
# Ubuntu WSL setup for universal9611 gaming kernel (m31)
# Run inside Ubuntu WSL: bash ubuntu-setup.sh
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/4] apt deps ==="
sudo apt update
sudo apt install -y \
  git curl wget python3 python3-pip bc bison flex \
  build-essential clang llvm lld \
  libssl-dev libelf-dev libncurses-dev libncurses5-dev \
  dwarves cpio rsync unzip zip binutils-aarch64-linux-gnu \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  device-tree-compiler ccache u-boot-tools

echo "=== [2/4] workspace on ext4 (avoids Windows AUX.c issue) ==="
mkdir -p ~/universal9611_gaming_kernel
cd ~/universal9611_gaming_kernel
WIN_PROJ="/mnt/c/Users/$(cmd.exe /c echo %USERNAME% 2>/dev/null | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' || echo $USER)/Downloads/universal9611_gaming_kernel"
# fallback: try common path
if [ ! -d "$WIN_PROJ" ]; then
  WIN_PROJ=$(ls -d /mnt/c/Users/*/Downloads/universal9611_gaming_kernel 2>/dev/null | head -n1 || echo "")
fi
echo "WIN_PROJ=$WIN_PROJ"
if [ -n "$WIN_PROJ" ]; then
  cp -v "$WIN_PROJ"/gaming.cfg ./ 2>/dev/null || true
  cp -v "$WIN_PROJ"/integrate-ksu-susfs.sh ./ 2>/dev/null || true
  cp -v "$WIN_PROJ"/build-m31-gaming.sh ./ 2>/dev/null || true
fi

echo "=== [3/4] clone kernel fresh on ext4 ==="
if [ ! -d kernel ]; then
  git clone --depth 1 --branch lineage-24.0 https://github.com/Parbindar7/android_kernel_samsung_universal9611 kernel
else
  echo "kernel/ exists, fetching..."
  git -C kernel fetch --depth 1 origin lineage-24.0 || true
fi

echo "=== [4/4] toolchain (Proton Clang 13, proven for 4.14 Samsung) ==="
if [ ! -x kernel/toolchain/bin/clang ]; then
  mkdir -p /tmp/tc
  cd /tmp/tc
  # Proton Clang 13 stable - small download, good 4.14 support
  if [ ! -d proton-clang ]; then
    git clone --depth 1 https://github.com/kdrag0n/proton-clang proton-clang || \
    wget -q https://github.com/kdrag0n/proton-clang/archive/refs/heads/master.tar.gz -O proton.tar.gz
  fi
  mkdir -p ~/universal9611_gaming_kernel/kernel/toolchain
  if [ -d proton-clang/bin ]; then
    cp -a proton-clang/bin ~/universal9611_gaming_kernel/kernel/toolchain/
    cp -a proton-clang/lib ~/universal9611_gaming_kernel/kernel/toolchain/ 2>/dev/null || true
    cp -a proton-clang/include ~/universal9611_gaming_kernel/kernel/toolchain/ 2>/dev/null || true
  fi
  cd ~/universal9611_gaming_kernel
fi

# verify
~/universal9611_gaming_kernel/kernel/toolchain/bin/clang -v || kernel/toolchain/bin/clang -v || echo "WARN: toolchain not ready, build script will retry with apt clang"

echo ""
echo "Setup done. Next:"
echo "  cd ~/universal9611_gaming_kernel"
echo "  bash integrate-ksu-susfs.sh"
echo "  bash build-m31-gaming.sh"
