#!/bin/bash
# Integrate KernelSU-Next (legacy) + SUSFS (kernel-4.14) into universal9611 4.14.357
# Run: bash integrate-ksu-susfs.sh (inside ~/universal9611_gaming_kernel)
set -e
KROOT="$HOME/universal9611_gaming_kernel/kernel"
[ -d "$KROOT" ] || KROOT="$(pwd)/kernel"
echo "KROOT=$KROOT"
cd "$KROOT"

echo "=== [1/4] KernelSU-Next legacy ==="
if [ ! -d KernelSU-Next ] && [ ! -d KernelSU ]; then
  curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
else
  echo "KSU dir exists, skipping setup.sh"
fi
if [ -d KernelSU-Next/kernel ]; then
  KSU_DIR="KernelSU-Next"
elif [ -d KernelSU/kernel ]; then
  KSU_DIR="KernelSU"
else
  ls KernelSU-Next/kernel/ksu.c drivers/kernelsu 2>/dev/null || { echo "ERROR: KernelSU setup failed"; exit 1; }
  KSU_DIR="KernelSU-Next"
fi
echo "KSU_DIR=$KSU_DIR"
ls "$KSU_DIR/kernel/ksu.c" || { echo "ERROR: KernelSU setup failed"; exit 1; }

echo "=== [2/4] SUSFS kernel-4.14 ==="
rm -rf /tmp/susfs4ksu
git clone --depth 1 --branch kernel-4.14 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs4ksu
echo "SUSFS commit: $(git -C /tmp/susfs4ksu rev-parse --short HEAD)"
cp -v /tmp/susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch "$KSU_DIR/" || \
cp -v /tmp/susfs4ksu/kernel_patches/KernelSU/*.patch "$KSU_DIR/" || true
cp -v /tmp/susfs4ksu/kernel_patches/fs/susfs.c fs/ || cp -v /tmp/susfs4ksu/kernel_patches/susfs.c fs/ || true
mkdir -p include/linux
cp -v /tmp/susfs4ksu/kernel_patches/include/linux/susfs.h include/linux/ || cp -v /tmp/susfs4ksu/kernel_patches/susfs.h include/linux/ || true
# find 50 patch (name varies: 50_add_susfs_in_kernel-4.14.patch)
SUSFS_PATCH=$(ls /tmp/susfs4ksu/kernel_patches/50_add_susfs_in_kernel*4.14*.patch 2>/dev/null | head -n1 || ls /tmp/susfs4ksu/kernel_patches/50_add*4.14*.patch 2>/dev/null | head -n1 || echo "")
echo "SUSFS_PATCH=$SUSFS_PATCH"
if [ -n "$SUSFS_PATCH" ]; then cp -v "$SUSFS_PATCH" ./50_susfs.patch; fi

echo "--- patch KernelSU for SUSFS ---"
cd "$KSU_DIR"
if patch -p1 --dry-run < 10_enable_susfs_for_ksu.patch >/dev/null 2>&1; then
  patch -p1 < 10_enable_susfs_for_ksu.patch
  echo "KSU+SUSFS glue OK"
else
  echo "KSU glue already applied or FAILED (check manually)"
  patch -p1 < 10_enable_susfs_for_ksu.patch || true
fi
cd "$KROOT"

echo "--- patch kernel for SUSFS ---"
SUSFS_OK=1
if [ -f 50_susfs.patch ]; then
  if patch -p1 --dry-run < 50_susfs.patch >/dev/null 2>&1; then
    patch -p1 < 50_susfs.patch && echo "SUSFS kernel patch OK" || SUSFS_OK=0
  else
    echo "SUSFS patch dry-run FAILED, trying with fuzz..."
    patch -p1 --fuzz=3 < 50_susfs.patch || SUSFS_OK=0
  fi
else
  echo "WARN: no 50_susfs.patch found"
  SUSFS_OK=0
fi
if [ "$SUSFS_OK" = "0" ]; then
  echo "!!! SUSFS kernel patch had rejects. KSU will still build, but SUSFS needs manual fix."
  echo "Check *.rej files: git -C $KROOT status --porcelain | grep rej"
fi
echo "$SUSFS_OK" > /tmp/susfs_ok

echo "=== [3/4] Manual KSU hooks (5 sites, idempotent) ==="
python3 - <<'PY'
import pathlib
kroot = pathlib.Path(".")
def patch_file(path, marker, decl, anchor, insert):
    p = kroot / path
    t = p.read_text()
    if marker in t:
        print(f"{path}: already patched, skip")
        return True
    if anchor not in t:
        print(f"{path}: ANCHOR NOT FOUND: {anchor[:60]!r} -> MANUAL FIX NEEDED")
        return False
    # add decl once after last #include if not present
    if decl.strip() and decl.strip() not in t:
        # insert decl before first blank-line-separated function? simplest: before anchor
        t = t.replace(anchor, decl + "\n" + anchor, 1)
        print(f"{path}: decl added")
    else:
        # decl already or empty
        pass
    # add insert before anchor's return? we use anchor->insert+anchor logic via replace
    # Here anchor is the line to prepend insert to; caller passes full anchor + insert handling
    p.write_text(t)
    return True

# We do two-step: decl + hook. Simpler: direct string replaces with checks.

def ensure_replace(path, old, new, tag):
    p = pathlib.Path(path)
    t = p.read_text()
    if tag in t:
        print(f"{path} [{tag}]: already present")
        return True
    if old not in t:
        print(f"{path} [{tag}]: OLD NOT FOUND, need manual")
        return False
    t = t.replace(old, new, 1)
    p.write_text(t)
    print(f"{path} [{tag}]: patched")
    return True

ok = True
# 1. fs/exec.c - do_execve
ok &= ensure_replace("fs/exec.c",
  "int do_execve(struct filename *filename,",
  "#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,\n\t\t\t\tvoid *argv, void *envp, int *flags);\n#endif\nint do_execve(struct filename *filename,",
  "ksu_handle_execveat")
# add call inside do_execve (before return do_execveat_common in do_execve)
# Find first do_execve body: insert after "struct user_arg_ptr envp"
p = pathlib.Path("fs/exec.c"); t = p.read_text()
if "ksu_handle_execveat((int *)AT_FDCWD" not in t:
    # insert after envp line in do_execve (non-compat)
    old = "\tstruct user_arg_ptr envp = { .ptr.native = __envp };\n\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);\n}\n\nstatic int compat_do_execve"
    new = "\tstruct user_arg_ptr envp = { .ptr.native = __envp };\n#ifdef CONFIG_KSU\n\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);\n#endif\n\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);\n}\n\nstatic int compat_do_execve"
    if old in t:
        p.write_text(t.replace(old, new, 1)); print("fs/exec.c [execve call]: patched")
    else:
        print("fs/exec.c [execve call]: pattern not found, check manually"); ok=False
else:
    print("fs/exec.c [execve call]: already present")

# 2. fs/open.c - faccessat
ok &= ensure_replace("fs/open.c",
  "SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)",
  "#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *mode, int *flags);\n#endif\nSYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)",
  "ksu_handle_faccessat")
p = pathlib.Path("fs/open.c"); t = p.read_text()
if "ksu_handle_faccessat(&dfd" not in t:
    old = "\tunsigned int lookup_flags = LOOKUP_FOLLOW;"
    new = "#ifdef CONFIG_KSU\n\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n#endif\n\n\tunsigned int lookup_flags = LOOKUP_FOLLOW;"
    if old in t:
        p.write_text(t.replace(old, new, 1)); print("fs/open.c [faccessat call]: patched")
    else:
        print("fs/open.c [faccessat call]: pattern not found"); ok=False
else:
    print("fs/open.c [faccessat call]: already present")

# 3. fs/read_write.c - sys_read
ok &= ensure_replace("fs/read_write.c",
  "SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)",
  "#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern __attribute__((cold)) int ksu_handle_sys_read(unsigned int fd,\n\t\t\t\tchar __user **buf_ptr, size_t *count_ptr);\n#endif\nSYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)",
  "ksu_handle_sys_read")
p = pathlib.Path("fs/read_write.c"); t = p.read_text()
if "ksu_handle_sys_read(fd" not in t:
    old = "\tstruct fd f = fdget_pos(fd);\n\tssize_t ret = -EBADF;"
    new = "\tstruct fd f = fdget_pos(fd);\n\tssize_t ret = -EBADF;\n\n#ifdef CONFIG_KSU\n\tif (unlikely(ksu_vfs_read_hook))\n\t\tksu_handle_sys_read(fd, &buf, &count);\n#endif"
    if old in t:
        p.write_text(t.replace(old, new, 1)); print("fs/read_write.c [read call]: patched")
    else:
        print("fs/read_write.c [read call]: pattern not found"); ok=False
else:
    print("fs/read_write.c [read call]: already present")

# 4. fs/stat.c - newfstatat
ok &= ensure_replace("fs/stat.c",
  "SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,",
  "#ifdef CONFIG_KSU\n__attribute__((hot))\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user,\n\t\t\t\tint *flags);\n#endif\nSYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,",
  "ksu_handle_stat")
p = pathlib.Path("fs/stat.c"); t = p.read_text()
if "ksu_handle_stat(&dfd" not in t:
    old = "\tstruct kstat stat;\n\tint error;"
    # only patch the newfstatat one (first occurrence after our decl) - replace first
    if old in t:
        p.write_text(t.replace(old, "\tstruct kstat stat;\n\tint error;\n\n#ifdef CONFIG_KSU\n\tksu_handle_stat(&dfd, &filename, &flag);\n#endif", 1)); print("fs/stat.c [stat call]: patched")
    else:
        print("fs/stat.c [stat call]: pattern not found"); ok=False
else:
    print("fs/stat.c [stat call]: already present")

# 5. kernel/reboot.c - sys_reboot
ok &= ensure_replace("kernel/reboot.c",
  "SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,",
  "#ifdef CONFIG_KSU\nextern int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg);\n#endif\nSYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,",
  "ksu_handle_sys_reboot")
p = pathlib.Path("kernel/reboot.c"); t = p.read_text()
if "ksu_handle_sys_reboot(magic1" not in t:
    old = "\t/* We only trust the superuser with rebooting the system. */"
    new = "#ifdef CONFIG_KSU\n\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);\n#endif\n\t/* We only trust the superuser with rebooting the system. */"
    if old in t:
        p.write_text(t.replace(old, new, 1)); print("kernel/reboot.c [reboot call]: patched")
    else:
        print("kernel/reboot.c [reboot call]: pattern not found"); ok=False
else:
    print("kernel/reboot.c [reboot call]: already present")

print("MANUAL_HOOKS_OK" if ok else "MANUAL_HOOKS_NEED_REVIEW")
PY

echo "=== [4/4] done ==="
echo "If MANUAL_HOOKS_NEED_REVIEW appeared, open the listed file and apply:"
echo " https://kernelsu-next.github.io/webpage/pages/how-to-integrate-for-non-gki.html (manual section)"
echo ""
echo "Next: bash build-m31-gaming.sh"
