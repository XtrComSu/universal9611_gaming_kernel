#!/bin/bash
# Ultra-gaming build for exynos9611-m31 + KernelSU-Next + SUSFS
# Run inside ~/universal9611_gaming_kernel : bash build-m31-gaming.sh
set -e
PROJ="$HOME/universal9611_gaming_kernel"
KROOT="$PROJ/kernel"
CFG_SRC="$PROJ/gaming.cfg"
# fallback if run from Windows copy
[ -f "$CFG_SRC" ] || CFG_SRC="$(pwd)/gaming.cfg"
[ -f "$CFG_SRC" ] || CFG_SRC="/mnt/c/Users/$(ls /mnt/c/Users/ | head -n1)/Downloads/universal9611_gaming_kernel/gaming.cfg"
TARGET="m31"
JOBS=$(nproc)

cd "$KROOT"
echo "=== Gaming build: $TARGET ==="
echo "KROOT=$(pwd)"
git rev-parse --short HEAD || true

# toolchain
if [ ! -x toolchain/bin/clang ]; then
  echo "WARN: toolchain/bin/clang missing, trying apt clang + gcc cross"
  export PATH="/usr/lib/llvm-14/bin:$PATH" || true
else
  export PATH="$KROOT/toolchain/bin:$PATH"
  echo "Toolchain: $(toolchain/bin/clang --version | head -n1)"
fi
clang --version | head -n1 || true
aarch64-linux-gnu-gcc --version | head -n1 || true

OUT="$KROOT/out"
rm -rf "$OUT"
mkdir -p "$OUT"

MAKE_BASE=(make O=out ARCH=arm64 LLVM=1 CROSS_COMPILE=aarch64-linux-gnu- CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar OBJDUMP=llvm-objdump READELF=llvm-readelf NM=llvm-nm OBJCOPY=llvm-objcopy -j"$JOBS")

echo "=== defconfig ==="
"${MAKE_BASE[@]}" "exynos9611-${TARGET}_defconfig"

echo "=== merge gaming.cfg ==="
if [ -f "$CFG_SRC" ]; then
  ./scripts/kconfig/merge_config.sh -m -O out out/.config "$CFG_SRC"
  (cd out && make ARCH=arm64 olddefconfig)
  echo "--- merged key configs ---"
  grep -E "CONFIG_KSU|CONFIG_TCP_CONG|CONFIG_CPU_FREQ_GOV|CONFIG_WIREGUARD|CONFIG_ZRAM|CONFIG_DEBUG_INFO " out/.config || true
else
  echo "WARN: $CFG_SRC not found, building stock defconfig + KSU only"
fi

# ensure KSU/SUSFS on even if merge missed
./scripts/config --file out/.config -e KSU -e KSU_SUSFS -e KPROBES -e TCP_CONG_BBR -e WIREGUARD -e ZRAM || true
(cd out && make ARCH=arm64 olddefconfig)

echo "=== build kernel (KCFLAGS -O3 gaming) ==="
START=$(date +%s)
# -O3 + fast-math-ish safe + cortex tune. Keep compatible with clang 4.14.
export KCFLAGS="-O3 -pipe -fno-plt -fno-addrsig"
"${MAKE_BASE[@]}" KCFLAGS="$KCFLAGS"
echo "=== dtbo / dtb ==="
python3 "$KROOT/build_kernel/bin/mkdtboimg.py" cfg_create "$OUT/arch/arm64/boot/dtbo-${TARGET}.img" "$KROOT/build_kernel/configs/dtbo/${TARGET}.cfg" -d "$OUT/arch/arm64/boot/dts/samsung"
python3 "$KROOT/build_kernel/bin/mkdtboimg.py" cfg_create "$OUT/arch/arm64/boot/exynos9611.dtb" "$KROOT/build_kernel/configs/dtb/exynos9611.cfg" --dtb-dir "$OUT/arch/arm64/boot/dts/exynos"
END=$(date +%s)
echo "Build took $((END-START))s"

echo "=== package AnyKernel3 ==="
AK3="$KROOT/AnyKernel3"
cp -v "$OUT/arch/arm64/boot/Image" "$AK3/Image"
cp -v "$OUT/arch/arm64/boot/dtbo-${TARGET}.img" "$AK3/dtbo.img"
cp -v "$OUT/arch/arm64/boot/exynos9611.dtb" "$AK3/dtb"
KVER=$(grep -o '"[^"]*"' "$OUT/include/generated/utsrelease.h" | tr -d '"' | head -n1)
KSU_VER=$(cat KernelSU/kernel/version 2>/dev/null || grep -r KSU_VERSION KernelSU 2>/dev/null | head -n1 || echo "KSUN")
DATE=$(date +%Y-%m-%d)
ZIP="Everline-GAMING-KSUN-SUSFS_${TARGET}_${DATE}.zip"
(cd "$AK3" && zip -r9 "$KROOT/$ZIP" Image dtbo.img dtb META-INF tools anykernel.sh version)
rm -f "$AK3/Image" "$AK3/dtbo.img" "$AK3/dtb"
echo "=== DONE ==="
echo "ZIP: $KROOT/$ZIP"
echo "KVER: $KVER"
ls -lh "$KROOT"/*.zip
# copy back to Windows Downloads for ease
WIN_DL=$(ls -d /mnt/c/Users/*/Downloads/universal9611_gaming_kernel 2>/dev/null | head -n1 || echo "")
if [ -n "$WIN_DL" ]; then
  cp -v "$KROOT/$ZIP" "$WIN_DL/" && echo "Copied to $WIN_DL/"
fi
