### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
## cyberknight777 @ xda-developers
## bachnxuan @ esk-project

### AnyKernel setup
# global properties
properties() { '
kernel.string=SukiSU Ultra Kernel for xaga (HyperOS / GKI)
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

ui_print "- [+] Checking kernel image..."
"$BIN/busybox" sha256sum -cs Image.zst.sha256 || abort "[!] SHA256 mismatch"
ui_print "- [+] SHA256 OK"

ui_print "- [+] Unpacking kernel image..."
"$BIN/zstd" -d -q --no-progress -o "$AKHOME/Image" "$AKHOME/Image.zst" ||
  abort "[!] Failed to decompress kernel image"
ui_print "- [+] Kernel image unpacked"

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
