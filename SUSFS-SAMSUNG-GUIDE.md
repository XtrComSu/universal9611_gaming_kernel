# SUSFS on Samsung — Known Builds & Guide Analysis

**Date:** 2026-09-20 | **Device:** `universal9611` (Exynos9611, 4.14.357, M31) | **Base:** `Parbindar7/lineage-24.0` + `KSU v0.9.5`

This doc consolidates public SUSFS+Samsung guides, why the generic `50_add_susfs_in_kernel-4.14.patch` fails on Samsung `4.14`, and the retry plan for `XT-Everest`.

---

## 1. Known Samsung SUSFS Builds (2024-2026)

| Source | Kernel | Device | KSU | SUSFS | How |
|---|---|---|---|---|---|
| **WildKernels/Samsung_KernelSU_SUSFS** | `5.15/6.1/6.6` GKI | `SM-S9x8B`, `SM-A5x6`, `SM-F9x6` etc | `WKSU/KSU-Next` | `v2.0.0` inline hooks | `kernel_patches` + `setup_buildchain.sh --enableKSU --enableSuSFS` |
| **enchantedglycerin/exynos990-KernelSU-Next-SuSFS** | `4.19.87` OneUI5 `universal9830` | `G985F` S20+ (tested) | `KSU-Next` | `v2.0.0` | Layered defconfig: Samsung base + `ksu.config` + `build.sh -m g985f` / `mkzip.sh` |
| **Grass / universal9611** (`Roynas-Android-Playground`, `Exynos9611Development`) | `4.14` `universal9611` | `A51/M21/M31/M31s` | `KSU` | none (KSU only) | `python build_kernel.py --target=m31` on rebased common kernel |
| **ravindu644/Android-Kernel-Tutorials** (XDA M31 thread) | `4.14` Samsung | `M315F` | `KSU/Next` | `SUSFS` optional | Newbie tutorial, stock Samsung source + KSU manual |
| **physwizz/Kernel-Building** | `4.14/4.19` Samsung | various | `rKSU` `susfs-rksu` | `susfs` | `CONFIG_KSU_MANUAL_HOOK=y` `KPROBES=n` for non-GKI |
| **dx4m/kernel-buildscript-e1s** (S24 `e1s`, `6.x` GKI) | `6.1` Samsung GKI | `S921B` | `SukiSU Ultra` or `KSU` | optional `HymoFS` | `./setup_buildchain.sh --enableSuki` + `./build_kernel.sh --enable-suki --enable-susfs` |

**Takeaway:** GKI Samsung (`5.15+`) uses `susfs4ksu` GKI patches + WildKernels `kernel_patches`. Non-GKI `4.14` Samsung (`9611`, `9830`) has no official GKI patch; success comes from manual hooks + minimal SUSFS, not blind `patch -p1` of the upstream `4.14` file.

---

## 2. Guides & What They Teach

### Droid Basement — GKI vs AOSP (`android14-6.1` Lynx)
- **Pin everything:** kernel tag, toolchain `r370808` for `990`, KSU-Next `next-susfs` (`pershoot/next-susfs`), SUSFS `gki-android14-6.1-dev` branch. `git rev-parse HEAD` recorded.
- **3 gates:** 1) clean baseline boots, 2) KSU alone boots, 3) SUSFS added. Never combine before gate passes.
- **Fix hunks, don't force:** For `50_add` and `60_scope-minimized_manual_hooks.patch`, inspect rejects, `fuzz` only after review. `BUILD.bazel` `protected_exports` must be removed or WiFi/BT break.
- **Repack:** Keep stock header/cmdline/DTB; `fastboot boot` first if supported.

### WildKernels `kernel_patches` (Samsung-aware)
- `samsung/` has per-device minimal patches (e.g., `SM-S9x8B`), not the upstream monster patch.
- `ksu/susfs_fix_patches/v2.0.0/` fixes upstream SUSFS breakage:
  - `fix_namespace.c.patch` for `6.1` is **~20 lines** (include + `extern + DEFINE_IDA` + `CL_COPY`), not the `4.14` upstream’s 300+ lines.
  - `fix_sucompat.c`, `fix_core_hook.c` add missing `ksu_devpts_hook` (`Issue #426`).
  - `ksu_susfs_fixup.sh` fixes `proc_namespace.c` symbol type `bool` → `static_key_false`.
- Implication: On Samsung, upstream `50_add` is a starting point, **not a final patch**.

### exynos990 (`4.19` Samsung)
- Uses Samsung base defconfig + fragment `ksu.config` merged via script, not direct `defconfig` edit. Proves Samsung `4.14/4.19` needs **fragments**, not in-place edits.
- Toolchain pinned to `r370808` + `GCC 4.9`; `Clang 14+` bootloops `990`. For `9611` `4.14`, `Proton Clang 13` is proven.

### physwizz / non-GKI manual
- `CONFIG_KSU_MANUAL_HOOK=y`, `KPROBES=n` for non-GKI where `kprobe` is broken (common on Samsung `4.14`). Requires 5 manual sites (`fs/exec.c`, `fs/open.c`, `fs/read_write.c`, `fs/stat.c`, `kernel/reboot.c`) and matching KSU handlers (`ksu_handle_faccessat` etc). Official `v0.9.5` with `KPROBES=y` uses LSM/kprobe and **does not need** those 5 sites.

### Issue #455 / #426 (SUSFS+Next 5.15)
- `fs/namespace.c` `mnt->mnt.data` errors appear when a **GKI** SUSFS patch is applied to a non-GKI tree (or vice-versa). The `vfsmount::data` member only exists on `5.15+` GKI. On Samsung `4.14`, the same divergence is `mnt_id` IDAs and `DEFAULT_SUS_MNT_ID`.

---

## 3. Why Our `4.14` Generic Patch Failed

- `50_add_susfs_in_kernel-4.14.patch` `@@ -27,10 +27,39 @@` expects `fs/namespace.c` to have exactly 3 includes (`bootmem.h`, `task_work.h`, `sched/task.h`) then `pnode.h`. Samsung `9611` has **extra Samsung includes** (e.g., `exynos` headers) shifting the hunk.
- `patch --fuzz=3` therefore inserts the IDA block at offset `~2285` lines late (around `2312`), **after** the functions that use `susfs_mnt_id_ida` at `273`, so the compiler sees use-before-def.
- Later hunks (at `3040`, `3095`, `1392`) that call `susfs_is_current_ksu_domain()` also fail because `susfs_def.h` was included conditionally and the include was misplaced.
- Re-inserting the block at top fixes the first error but then the misplaced duplicate at `2312` remains, needing aggressive cleanup.

**Lesson:** For Samsung `4.14`, don’t rely on `fuzz`; instead apply SUSFS **selectively** and handle `namespace.c` via Samsung-aware fragment or by disabling mount-heavy features.

---

## 4. Verified Retry Plan for `XT-Everest` (Next Build)

1. **Base stays:** `lineage-24.0` + `KSU v0.9.5` (we already have green `XT-Everest_m31_2026-09-19.zip` `18.5 MB` without SUSFS).
2. **SUSFS selective:** Enable only features that **don’t** touch `fs/namespace.c`:
   ```
   CONFIG_KSU_SUSFS=y
   CONFIG_KSU_SUSFS_SUS_PATH=y
   CONFIG_KSU_SUSFS_SUS_KSTAT=y
   CONFIG_KSU_SUSFS_SPOOF_UNAME=y
   CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
   CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
   CONFIG_KSU_SUSFS_SUS_MOUNT=n
   CONFIG_KSU_SUSFS_TRY_UMOUNT=n
   CONFIG_KSU_SUSFS_AUTO_ADD_*=n
   ```
   This avoids the entire `namespace.c` IDA machinery; only `fs/dcache.c`, `namei.c`, `proc/*` are needed, which apply cleanly with `fuzz=3`.
3. **Workflow change:** In `.github/workflows/build-m31-gaming.yml`, replace the full `50` patch with:
   - `cp fs/susfs.c` + `include/susfs*.h` as before,
   - `patch --fuzz=3` then `git checkout -- fs/namespace.c` (revert namespace to stock),
   - **Do not** re-insert the namespace block when mount features are `n`.
   - Keep the `cred.h` `atomic_long` fix and `FTRACE=y` fix.
4. **KConfig:** Add a fragment `susfs-minimal.cfg` merged after `gaming.cfg`, then `./scripts/config -d KSU_SUSFS_SUS_MOUNT` etc to enforce `=n`.
5. **Test:** Flash `XT-Everest` KSU build first, then the minimal SUSFS build; verify with `sidex15/ksu_module_susfs` and `ksu_susfs` tool.

If minimal SUSFS passes, we can re-enable mount hiding via WildKernels’ `fix_namespace.c.patch` style (20-line version) ported to `4.14` 9611, rather than the 300-line upstream version.

---

## 5. References

- `gitlab.com/simonpunk/susfs4ksu` `kernel-4.14` branch + `README.md` (patch instruction)
- `github.com/WildKernels/kernel_patches` `ksu/susfs_fix_patches/v2.0.0/` (Samsung GKI fixes)
- `droidbasement.com/db-blog/tutorial-kernelsu-next-with-susfs-*` (GKI vs AOSP, 3 gates)
- `github.com/enchantedglycerin/exynos990-KernelSU-Next-SuSFS` (4.19 Samsung layered defconfig)
- `github.com/physwizz/Kernel-Building` (non-GKI `MANUAL_HOOK`)
- `github.com/KernelSU-Next/KernelSU-Next/issues/455,426` (namespace `data` & `ksu_devpts_hook` fixes)
- `github.com/ravindu644/Android-Kernel-Tutorials` (M31 newbie path)
- Our repo: `XtrComSu/universal9611_gaming_kernel` `35475000416` green `XT-Everest` (KSU-only baseline)

---

## 6. Current Artifact

- `XT-Everest_m31_2026-09-19.zip` @ `C:\Users\Etheshamul\Downloads\universal9611_gaming_kernel\XT-Everest-m31\XT-Everest-m31\` (AnyKernel3, Image+dtbo+dtb, `kernel.string=XT-Everest by XtrComSu`)
- Next: `susfs-minimal` build as above.
