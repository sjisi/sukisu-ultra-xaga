### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## cyberknight777 @ xda-developers
## bachnxuan @ esk-project

### AnyKernel setup
# global properties
properties() { '
kernel.string=SukiSU Ultra Kernel for xaga (Redmi Note 11T Pro / POCO X4 GT)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=xaga
device.name2=xagain
device.name3=xagapro
device.name4=xagaproin
supported.versions=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install

# boot shell variables
BLOCK=boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto
NO_MAGISK_CHECK=true

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

reset_dir() {
    rm -rf "$1" || abort "[!] Failed to reset $1"
    mkdir -p "$1" || abort "[!] Failed to create $1"
}

if [ -f /system/framework/MiuiBooster.jar ]; then
    abort "[!] HyperOS detected, please use the generic package."
fi

ui_print " " "- [+] Starting kernel image flashing..."
ui_print "- [*] Checking kernel image..."
"$BIN/busybox" sha256sum -cs Image.zst.sha256 || abort "[!] SHA256 mismatch"
ui_print "- [*] SHA256 OK"

ui_print "- [*] Unpacking kernel image..."
"$BIN/zstd" -d -q --no-progress -o "$AKHOME/Image" "$AKHOME/Image.zst" ||
    abort "[!] Failed to decompress kernel image"
ui_print "- [*] Kernel image unpacked"

ui_print "- [+] Flashing kernel image..."
# boot install
split_boot # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk

if [ -f "$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
fi
## end boot install

rm -f "$AKHOME/Image" || abort "[!] Failed to remove extracted Image"

module_archive="$AKHOME/module.tar.xz"
module_extract_dir="$AKHOME/_module"

if [ -f "$module_archive" ]; then
    ui_print " " "- [+] Unpacking module package..."
    reset_dir "$module_extract_dir"
    busybox tar -xpf "$module_archive" -C "$module_extract_dir" ||
        abort "- [!] Failed to extract module.tar.xz"
fi

# vendor_boot shell variables
BLOCK=vendor_boot
IS_SLOT_DEVICE=1
RAMDISK_COMPRESSION=auto
PATCH_VBMETA_FLAG=auto

# reset for vendor_boot patching
reset_ak

# vendor_boot install
split_boot # use split_boot to skip ramdisk unpack, e.g. for dtb on devices with hdr v4 but no vendor_kernel_boot

if [ -d "$module_extract_dir/vendor_boot" ]; then
    ui_print " " "- [+] Starting vendor_ramdisk modules update..."

    vendor_boot_ramdisk_dir="$AKHOME/_vendor_boot_ramdisk"

    reset_dir "$vendor_boot_ramdisk_dir"

    ui_print "- [*] Unpacking ramdisk..."
    (
        cd "$vendor_boot_ramdisk_dir" &&
            "$BIN/busybox" cpio -i -d <"$SPLITIMG/vendor_ramdisk/ramdisk.cpio"
    ) || abort "- [!] Failed to unpack ramdisk.cpio"

    ui_print "- [*] Updating ramdisk.cpio modules..."
    rm -rf "$vendor_boot_ramdisk_dir/lib/modules" ||
        abort "- [!] Failed to remove old modules"
    mkdir -p "$vendor_boot_ramdisk_dir/lib" ||
        abort "- [!] Failed to prepare ramdisk modules directory"
    cp -a "$module_extract_dir/vendor_boot/lib/." "$vendor_boot_ramdisk_dir/lib/" ||
        abort "- [!] Failed to copy vendor_boot modules"

    ui_print "- [*] Repacking ramdisk.cpio..."
    (
        cd "$vendor_boot_ramdisk_dir" &&
            busybox find . | busybox cpio -o -H newc >"$SPLITIMG/vendor_ramdisk/ramdisk.cpio" 2>/dev/null
    ) || abort "[!] Failed to repack ramdisk.cpio"

    rm -rf "$vendor_boot_ramdisk_dir" ||
        abort "- [!] Failed to remove working directory"
fi

ui_print "- [+] Flashing new vendor_boot image..."
flash_boot # use flash_boot to skip ramdisk repack, e.g. for dtb on devices with hdr v4 but no vendor_kernel_boot
## end vendor_boot install

## vendor_dlkm install
if [ -d "$module_extract_dir/vendor_dlkm" ]; then
    # reset for vendor_dlkm patching
    reset_ak

    ui_print " " "/dev/block/mapper/vendor_dlkm${SLOT}"
    ui_print " " "- [+] Starting /vendor_dlkm modules update..."

    ui_print "- [*] Pulling /vendor_dlkm image from current slot (${SLOT})..."
    dd if=/dev/block/mapper/vendor_dlkm"${SLOT}" of="${AKHOME}"/vendor_dlkm.img ||
        abort "[!] Failed to pull vendor_dlkm${SLOT}.img"
    extract_vendor_dlkm_dir=${AKHOME}/_extract_vendor_dlkm
    reset_dir "$extract_vendor_dlkm_dir"

    ui_print "- [*] Unpacking /vendor_dlkm image..."
    "${BIN}"/extract.erofs -i "${AKHOME}"/vendor_dlkm.img -x -T8 -o "${extract_vendor_dlkm_dir}" >/dev/null 2>&1 ||
        abort "[!] Failed to unpack the vendor_dlkm image"
    sync

    ui_print "- [*] Updating /vendor_dlkm modules..."
    extract_vendor_dlkm_modules_dir=${extract_vendor_dlkm_dir}/vendor_dlkm/lib/modules
    rm -f "${extract_vendor_dlkm_modules_dir}"/* ||
        abort "[!] Failed to remove pre-existing files in ${extract_vendor_dlkm_modules_dir}"
    rm -f "${extract_vendor_dlkm_dir}"/config/vendor_dlkm_fs_config "${extract_vendor_dlkm_dir}"/config/vendor_dlkm_file_contexts ||
        abort "[!] Failed to remove pre-existing fs_config and file_contexts in ${extract_vendor_dlkm_dir}/config"
    cp -a "$module_extract_dir/vendor_dlkm/lib/modules/." "${extract_vendor_dlkm_modules_dir}/" ||
        abort "[!] Failed to copy vendor_dlkm modules"
    mv "${AKHOME}"/config/vendor_dlkm* "${extract_vendor_dlkm_dir}"/config/ ||
        abort "[!] Failed to move fs_config and file_contexts to ${extract_vendor_dlkm_dir}/config"

    ui_print "- [*] Repacking /vendor_dlkm image..."
    rm -f "${AKHOME}"/vendor_dlkm.img ||
        abort "[!] Failed to remove pre-existing vendor_dlkm.img"
    "${BIN}"/mkfs.erofs \
        --mount-point /vendor_dlkm \
        --fs-config-file "${extract_vendor_dlkm_dir}"/config/vendor_dlkm_fs_config \
        --file-contexts "${extract_vendor_dlkm_dir}"/config/vendor_dlkm_file_contexts \
        -z lz4 \
        -b 4096 \
        -C 262144 \
        -T 1230768000 \
        "${AKHOME}"/vendor_dlkm.img "${extract_vendor_dlkm_dir}"/vendor_dlkm ||
        abort "[!] Failed to repack the vendor_dlkm image"
    rm -rf "${extract_vendor_dlkm_dir}" ||
        abort "[!] Failed to remove working directory"
    unset extract_vendor_dlkm_dir extract_vendor_dlkm_modules_dir

    vendor_dlkm_block_size=$(blockdev --getsize64 /dev/block/mapper/vendor_dlkm"${SLOT}")
    if [ "$(wc -c <"$AKHOME"/vendor_dlkm.img)" -lt "${vendor_dlkm_block_size}" ]; then
        ui_print "- [*] Generated /vendor_dlkm image size is smaller than the block device..."
        ui_print "- [*] Truncating to fill the erofs image file..."
        truncate -c -s "$vendor_dlkm_block_size" "$AKHOME"/vendor_dlkm.img
    fi

    ui_print "- [+] Flashing new /vendor_dlkm image..."
    flash_generic vendor_dlkm
fi

rm -rf "$module_extract_dir"
## end vendor_dlkm install
