#!/usr/bin/env bash
#
# SukiSU Ultra - xaga (Redmi Note 11T Pro / POCO X4 GT) kernel build script
#
# Linux only (Ubuntu 22.04+/Debian 12+ recommended). Builds the kernel with
# SukiSU Ultra integrated and packages an AnyKernel3 zip (flashable with
# Kernel Flasher / FKM / recovery).
#
# Two device paths are supported:
#   TARGET=hyperos (default) - GKI 5.10 kernel, for HyperOS / Android 13+ ROMs
#   TARGET=miui             - MTK 5.10 kernel, for MIUI / Android 12 ROMs
#
# Usage:
#   ./build/build_xaga.sh                     # HyperOS (GKI) AnyKernel3 zip
#   TARGET=miui ./build/build_xaga.sh         # MIUI (MTK) AnyKernel3 zip
#   STOCK_BOOT_IMG=/path/boot.img TARGET=miui ./build/build_xaga.sh  # also repack boot.img
#
# Environment overrides:
#   KERNEL_SRC   path to the (already patched) kernel source
#   CLANG_DIR    path to an AOSP/LLVM clang toolchain (auto-downloaded if unset)
#   JOBS         parallel jobs (default: nproc)
#   OUT_DIR      output directory (default: ./out)
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

OUT_DIR="$(realpath "${OUT_DIR:-$ROOT/out}")"
WORK_DIR="$(realpath "${WORK_DIR:-$ROOT/work}")"
KERNEL_OUT="$WORK_DIR/kernel-out"
MODULES_STAGE="$WORK_DIR/modules"
MOD_FLAT="$WORK_DIR/mod-flat"
MOD_STAGE="$WORK_DIR/mod-stage"
CLANG_DIR="${CLANG_DIR:-$WORK_DIR/clang}"
JOBS="${JOBS:-$(nproc --all)}"

info()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "missing dependency: $c (see docs/FLASH-xaga.md for the install command)"
    done
}

TARGET="${TARGET:-hyperos}"
case "$TARGET" in
    hyperos)
        KERNEL_SRC="${KERNEL_SRC:-$ROOT/gki-kernel}"
        AK3_DIR="$SCRIPT_DIR/anykernel3-hyperos"
        GKI_CONFIG="$SCRIPT_DIR/gki-sukisu.config"
        KERNEL_REPO="https://github.com/ESK-Project/android12-5.10-gki.git"
        KERNEL_BRANCH="main"
        KERNEL_COMMIT="3cf4b57431b4ea85538be9b303dbabb5e8e5c74c"
        PATCH_FILE="$SCRIPT_DIR/gki-kernel-sukisu-ultra.patch"
        ;;
    miui)
        KERNEL_SRC="${KERNEL_SRC:-$ROOT/xaga-kernel}"
        AK3_DIR="$SCRIPT_DIR/anykernel3"
        KERNEL_REPO="https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git"
        KERNEL_BRANCH="xaga-s-oss"
        KERNEL_COMMIT="56ec519f688b624acf71a2dc3b81dd29dd23664b"
        PATCH_FILE="$SCRIPT_DIR/xaga-kernel-sukisu-ultra.patch"
        ;;
    *) die "unknown TARGET: $TARGET (use hyperos or miui)" ;;
esac

MODULES_LOAD_DIR="$SCRIPT_DIR/modules-load"

###############################################################################
# 0. Host dependencies
###############################################################################
prepare_host() {
    info "Checking host dependencies"
    require_cmd bc bison flex make python3 zip zstd xz tar cpio find sed awk grep
    command -v depmod >/dev/null 2>&1 || require_cmd kmod
    command -v llvm-strip >/dev/null 2>&1 || true
    ok "Host dependencies satisfied"
}

###############################################################################
# 1. Kernel source
###############################################################################
prepare_kernel() {
    if [[ ! -d "$KERNEL_SRC" ]]; then
        info "Fetching $TARGET kernel source (pinned to $KERNEL_COMMIT)..."
        git clone --depth 1 --single-branch --branch "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC"
    fi
    if [[ ! -d "$KERNEL_SRC/drivers/kernelsu" ]]; then
        info "Applying SukiSU integration patch..."
        ( cd "$KERNEL_SRC" && git apply "$PATCH_FILE" ) || die "failed to apply $PATCH_FILE to $KERNEL_SRC"
    fi
    [[ -d "$KERNEL_SRC/drivers/kernelsu" ]] || die "Kernel source is not patched with SukiSU: $KERNEL_SRC (missing drivers/kernelsu)"
    info "Using pre-patched kernel source: $KERNEL_SRC"
}

###############################################################################
# 2. Toolchain
###############################################################################
prepare_toolchain() {
    if [[ -x "$CLANG_DIR/bin/clang" ]]; then
        info "Using existing toolchain: $CLANG_DIR"
        return
    fi

    info "Downloading AOSP Clang toolchain (this is a large download)"
    mkdir -p "$WORK_DIR"
    local url
    url=$(curl -fsSL "https://api.github.com/repos/bachnxuan/aosp_clang_mirror/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*clang-r[^"]*\.tar\.gz"' | head -n1 | cut -d'"' -f4)
    [[ -n "$url" ]] || die "Failed to resolve Clang download URL"

    curl -fL --retry 5 -o "$WORK_DIR/clang.tar.gz" "$url"
    mkdir -p "$CLANG_DIR"
    tar -xzf "$WORK_DIR/clang.tar.gz" -C "$CLANG_DIR"
    rm -f "$WORK_DIR/clang.tar.gz"
    [[ -x "$CLANG_DIR/bin/clang" ]] || die "Clang toolchain extraction failed"
    ok "Toolchain ready: $("$CLANG_DIR/bin/clang" --version | head -n1)"
}

###############################################################################
# 3. Build
###############################################################################
build_kernel() {
    rm -rf "$KERNEL_OUT"
    mkdir -p "$KERNEL_OUT"
    if [[ "$TARGET" == "hyperos" ]]; then
        info "Merging GKI defconfig + SukiSU overlay"
        (
            cd "$KERNEL_SRC"
            scripts/kconfig/merge_config.sh -m -r -O "$KERNEL_OUT" \
                arch/arm64/configs/gki_defconfig \
                "$GKI_CONFIG"
        )
    else
        info "Merging xaga defconfig (gki_defconfig + defconfig + xaga_defconfig)"
        (
            cd "$KERNEL_SRC"
            scripts/kconfig/merge_config.sh -m -r -O "$KERNEL_OUT" \
                arch/arm64/configs/gki_defconfig \
                arch/arm64/configs/defconfig \
                arch/arm64/configs/xaga_defconfig
        )
    fi

    info "Building kernel (Image + dtbs + modules) with $JOBS jobs"
    make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 \
        CC="$CLANG_DIR/bin/clang" CROSS_COMPILE=aarch64-linux-gnu- \
        LLVM=1 LD="$CLANG_DIR/bin/ld.lld" LLVM_IAS=1 \
        -j"$JOBS" Image modules

    if [[ "$TARGET" == "miui" ]]; then
        make -C "$KERNEL_SRC" O="$KERNEL_OUT" ARCH=arm64 \
            CC="$CLANG_DIR/bin/clang" CROSS_COMPILE=aarch64-linux-gnu- \
            LLVM=1 LD="$CLANG_DIR/bin/ld.lld" LLVM_IAS=1 \
            INSTALL_MOD_PATH="$MODULES_STAGE" modules_install
    fi

    [[ -f "$KERNEL_OUT/arch/arm64/boot/Image" ]] || die "Image not produced - build failed"
    ok "Kernel built: $KERNEL_OUT/arch/arm64/boot/Image"
}

###############################################################################
# 4. Modules staging (vendor_boot + vendor_dlkm)
###############################################################################
flatten_modules() {
    info "Flattening kernel modules"
    rm -rf "$MOD_FLAT" "$MOD_STAGE"
    mkdir -p "$MOD_FLAT"
    shopt -s globstar nullglob
    for file in "$MODULES_STAGE"/lib/modules/**/*.ko; do
        cp -p "$file" "$MOD_FLAT/"
        if command -v llvm-strip >/dev/null 2>&1; then
            llvm-strip --strip-debug "$MOD_FLAT/$(basename "$file")"
        fi
    done
    shopt -u globstar nullglob
}

stage_vendor_boot_modules() {
    info "Staging vendor_boot modules"
    local krel src payload mods_dir depmod_root depmod_meta_dir depmod_dir
    local -a modules

    mkdir -p "$MOD_STAGE/vendor_boot/lib/modules"
    krel="$(make -s -C "$KERNEL_SRC" O="$KERNEL_OUT" kernelrelease)"
    src="$MODULES_STAGE/lib/modules/$krel"
    payload="$MOD_STAGE/vendor_boot"
    mods_dir="$payload/lib/modules"

    depmod_root="$WORK_DIR/depmod_boot"
    depmod_meta_dir="$depmod_root/lib/modules/0.0"
    depmod_dir="$depmod_meta_dir/lib/modules"
    mkdir -p "$depmod_dir"

    mapfile -t modules < <(cat "$MODULES_LOAD_DIR/modules.load.vendor_boot" \
                              "$MODULES_LOAD_DIR/modules.load.recovery" | sort -u)
    for mod in "${modules[@]}"; do
        if [[ -f "$MOD_FLAT/$mod" ]]; then
            cp -p "$MOD_FLAT/$mod" "$mods_dir/"
            cp -p "$MOD_FLAT/$mod" "$depmod_dir/"
        else
            warn "module not found in this build: $mod (skipped)"
        fi
    done

    cp -p "$MODULES_LOAD_DIR/modules.load.vendor_boot" "$mods_dir/modules.load"
    cp -p "$MODULES_LOAD_DIR/modules.load.recovery" "$mods_dir/modules.load.recovery"
    cp -p "$src"/modules.{order,builtin,builtin.modinfo} "$depmod_meta_dir/" 2>/dev/null || true
    depmod -b "$depmod_root" 0.0
    cp -p "$depmod_meta_dir"/modules.{alias,dep,softdep} "$mods_dir/" 2>/dev/null || true
    sed -i -e 's|\([^: ]*lib/modules/[^: ]*\)|/\1|g' "$mods_dir/modules.dep" 2>/dev/null || true
    rm -rf "$depmod_root"
}

stage_vendor_dlkm_modules() {
    info "Staging vendor_dlkm modules"
    local mods_dir depmod_root depmod_dir name

    mkdir -p "$MOD_STAGE/vendor_dlkm/lib/modules"
    mods_dir="$MOD_STAGE/vendor_dlkm/lib/modules"

    depmod_root="$WORK_DIR/depmod_dlkm"
    depmod_dir="$depmod_root/lib/modules/0.0"
    mkdir -p "$depmod_dir"

    shopt -s nullglob
    for file in "$MOD_FLAT"/*.ko; do
        cp -p "$file" "$mods_dir/"
        cp -p "$file" "$depmod_dir/"
    done
    shopt -u nullglob

    cp -p "$MODULES_LOAD_DIR/modules.load" "$mods_dir/modules.load"
    depmod -b "$depmod_root" 0.0
    cp -p "$depmod_dir"/modules.{alias,dep,softdep} "$mods_dir/" 2>/dev/null || true
    rm -rf "$depmod_root"
}

###############################################################################
# 5. AnyKernel3 packaging
###############################################################################
package_anykernel3() {
    info "Packaging AnyKernel3"
    local version
    version="$(make -s -C "$KERNEL_SRC" O="$KERNEL_OUT" kernelrelease)"
    local package_name="sukisu-ultra-$version-xaga-$TARGET"
    local package_path="$OUT_DIR/$package_name-AnyKernel3.zip"
    mkdir -p "$OUT_DIR"

    (
        cd "$AK3_DIR"
        cp -p "$KERNEL_OUT/arch/arm64/boot/Image" .
        zstd -19 -T0 --no-progress -o Image.zst Image >/dev/null 2>&1
        rm -f Image
        sha256sum Image.zst > Image.zst.sha256

        if [[ "$TARGET" == "miui" ]]; then
            rm -f module.tar.xz
            tar -cJf module.tar.xz -C "$MOD_STAGE" vendor_boot vendor_dlkm
        else
            rm -f module.tar.xz
        fi

        find . -type f -name 'placeholder' -delete 2>/dev/null || true
        rm -f "$package_path"
        zip -r9q -T -X -y -n .zst "$package_path" . -x '.git*' '*.log' '.github/*' 'README.md' '.git-ak3-origin/*'
    )
    ok "AnyKernel3 package: $package_path"
    echo "$package_path" > "$OUT_DIR/last-package.txt"
}

###############################################################################
# 6. Optional boot.img repack (fastboot path)
###############################################################################
repack_boot_image() {
    [[ -n "${STOCK_BOOT_IMG:-}" ]] || return 0
    [[ -f "$STOCK_BOOT_IMG" ]] || die "STOCK_BOOT_IMG not found: $STOCK_BOOT_IMG"

    info "Repacking boot image from $STOCK_BOOT_IMG"
    local mkboot="$WORK_DIR/mkbootimg"
    [[ -d "$mkboot" ]] || git clone --depth 1 \
        "https://android.googlesource.com/platform/system/tools/mkbootimg" "$mkboot"

    local unpack="$WORK_DIR/unpacked-boot"
    local header_version ramdisk_file
    rm -rf "$unpack"; mkdir -p "$unpack"
    (
        cd "$unpack"
        python3 "$mkboot/unpack_bootimg.py" --boot_img="$STOCK_BOOT_IMG"
        header_version="$(python3 "$mkboot/unpack_bootimg.py" --boot_img="$STOCK_BOOT_IMG" --format json 2>/dev/null \
            | grep -o '"header_version": *[0-9]*' | head -n1 | grep -o '[0-9]*' || true)"
        header_version="${header_version:-2}"
        ramdisk_file="ramdisk"
        [[ -f "$ramdisk_file" ]] || ramdisk_file=""
        python3 "$mkboot/mkbootimg.py" \
            --kernel "$KERNEL_OUT/arch/arm64/boot/Image" \
            --ramdisk "$ramdisk_file" \
            --dtb dtb \
            --header_version "$header_version" \
            --output "$OUT_DIR/sukisu-ultra-boot.img" \
            --os_version "12.0.0" --os_patch_level "2099-12"
    )
    ok "Repacked boot image: $OUT_DIR/sukisu-ultra-boot.img"
}

###############################################################################
main() {
    prepare_host
    prepare_kernel
    prepare_toolchain
    build_kernel
    if [[ "$TARGET" == "miui" ]]; then
        flatten_modules
        stage_vendor_boot_modules
        stage_vendor_dlkm_modules
    fi
    package_anykernel3
    if [[ "$TARGET" == "miui" ]]; then
        repack_boot_image
    fi
    ok "All done. Artifacts are in $OUT_DIR"
}

main "$@"
