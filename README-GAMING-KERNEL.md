# Universal9611 Gaming + KernelSU-Next + SUSFS (m31)

Target: Galaxy M31 (`exynos9611-m31_defconfig`), kernel 4.14.357, lineage-24.0 base:
https://github.com/Parbindar7/android_kernel_samsung_universal9611

Folder: `C:\Users\<you>\Downloads\universal9611_gaming_kernel\`
- `kernel/` = shallow git clone (Windows checkout incomplete due to `aux.c` reserved name — normal, full checkout happens inside WSL ext4)
- `WSL-INSTALL-ADMIN.ps1` = run as Admin to install WSL2 + Ubuntu
- `ubuntu-setup.sh`, `integrate-ksu-susfs.sh`, `gaming.cfg`, `build-m31-gaming.sh` = run inside Ubuntu WSL

## 0. Why WSL?
Kernel builds need Linux (case-sensitive ext4, clang, dtbo tools). Windows NTFS cannot even checkout `drivers/gpu/drm/nouveau/nvkm/subdev/i2c/aux.c` (`AUX` reserved). So we build on ext4 `~/universal9611_gaming_kernel`, output zip copied back to Downloads.

## 1. Install WSL (ADMIN, one time)
1. Right-click PowerShell -> Run as Administrator
2. `cd C:\Users\<you>\Downloads\universal9611_gaming_kernel`
3. `Set-ExecutionPolicy Bypass -Scope Process -Force; .\WSL-INSTALL-ADMIN.ps1`
4. REBOOT
5. Open `Ubuntu` from Start, create user/pass

## 2. Setup Ubuntu (inside Ubuntu WSL)
```bash
cd /mnt/c/Users/*/Downloads/universal9611_gaming_kernel
# copy scripts to Linux home if needed (auto in setup)
bash ubuntu-setup.sh
```

What it does:
- apt deps (clang, llvm, gcc-aarch64, libelf, dtc, ccache...)
- fresh `git clone --depth 1 -b lineage-24.0` to `~/universal9611_gaming_kernel/kernel` (ext4, no AUX issue)
- Proton Clang 13 to `kernel/toolchain/bin/clang` (expected by `build_kernel.py`)

## 3. Integrate KernelSU-Next + SUSFS
```bash
cd ~/universal9611_gaming_kernel
bash integrate-ksu-susfs.sh
```
- KernelSU-Next `legacy`: `curl .../setup.sh | bash -s legacy`
- SUSFS `kernel-4.14`: `gitlab.com/simonpunk/susfs4ksu` branch `kernel-4.14`
  - `10_enable_susfs_for_ksu.patch` -> `KernelSU/`
  - `50_add_susfs_in_kernel-4.14.patch` -> root + `fs/susfs.c` + `include/linux/susfs.h`
- 5 manual hooks (fs/exec.c, fs/open.c, fs/read_write.c, fs/stat.c, kernel/reboot.c) idempotent, per https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html
- If `MANUAL_HOOKS_NEED_REVIEW` or `*.rej`, fix manually before build.

## 4. Gaming config (`gaming.cfg`)
Merged on top of `exynos9611-m31_defconfig`:
- KSU + SUSFS + KPROBES fallback
- GOV: performance + schedutil + ondemand + interactive, devfreq performance
- NET: BBR + Westwood + fq_codel + WireGuard
- MEM: ZRAM LZ4 + KSM + THP
- FS: F2FS LZ4/ZSTD
- DEBUG stripped (DEBUG_INFO=n, FTRACE=n, CORESIGHT=n...) for fps
- Build with `KCFLAGS="-O3 -pipe -fno-plt -fno-addrsig"`

Tune: edit `gaming.cfg`, rebuild. Keep HZ=250 and PREEMPT (Samsung stable). Do not disable AUDIT/SELINUX or you bootloop.

## 5. Build
```bash
cd ~/universal9611_gaming_kernel
bash build-m31-gaming.sh
```
Output: `Everline-GAMING-KSUN-SUSFS_m31_YYYY-MM-DD.zip` in both `~/universal9611_gaming_kernel/kernel/` and `Downloads/universal9611_gaming_kernel/`. Flash via AnyKernel3 (TWRP / FKM).

## 6. Verify root hiding
- Manager: KernelSU-Next APK
- Module: `susfs4ksu-module` (sidex15) + `ksu_susfs` tool in `/data/adb/ksu/bin`
- Test: `ksu_susfs` in root shell, Play Integrity / banking apps.

## Notes / risks
- Non-GKI 4.14 SUSFS needs manual patch; rejects are normal on Samsung trees — fix by hand.
- `mnt_id_reorder` SUSFS feature bootloops non-GKI — left disabled.
- Kprobe on Samsung 4.14 often broken — we use manual hooks (`KSU_KPROBE_HOOKS=n`).
- Overclock/UV not enabled by default (stability). Add only if you know your board.
- Always backup boot/dtbo before flashing.

## Switch device?
`build_kernel.py --target` supports a51/f41/m31s/m31/m21/gta4xl/gta4xlwifi. Edit `build-m31-gaming.sh` TARGET + defconfig + dtbo cfg.
