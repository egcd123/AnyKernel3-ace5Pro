### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
#修补dtbo
lfdtget=$MODPATH/bin/fdtget
lfdtput=$MODPATH/bin/fdtput

PATCH_DTB() {
    ui_print "- 正在对 $1 打补丁"
    local lfinded=0
    local alpatched=0

    for i in $($lfdtget $1 /__fixups__ soc); do
        local lpath=$(echo $i | sed 's/\:target\:0//g')
        if $lfdtget -l $1 ${lpath}/__overlay__ | grep -q hmbird; then
            if [ $($lfdtget $1 ${lpath}/__overlay__/oplus,hmbird/version_type type) == "HMBIRD_GKI" ]; then
                alpatched=1
                ui_print "- $1 已打补丁"
            fi
            break
        fi
    done

    if [ $alpatched -eq 0 ]; then
        for i in $($lfdtget $1 /__fixups__ soc); do
            local lpath=$(echo $i | sed 's/\:target\:0//g')
            if $lfdtget -l $1 ${lpath}/__overlay__ | grep -q hmbird; then
                local lfinded=1
                ui_print "- $1 已找到gki补丁位置"
                $lfdtput -t s $1 ${lpath}/__overlay__/oplus,hmbird/version_type type HMBIRD_GKI
                break
            fi
        done

        if [ $lfinded -eq 0 ]; then
            ui_print "- 为非ogki $1 添加补丁"
            for i in $($lfdtget $1 /__fixups__ soc); do
                local ppath=$(echo $i | sed 's/\:target\:0//g')
                if $lfdtget -l $1 ${ppath}/__overlay__ | grep -q reboot_reason; then
                    $lfdtput -p -c $1 ${ppath}/__overlay__/oplus,hmbird/version_type
                    $lfdtput -t s $1 ${ppath}/__overlay__/oplus,hmbird/version_type type HMBIRD_GKI
                    break
                fi
            done
        fi
    fi
}

REPACKDTBO() {
    ui_print ""
    ui_print ""
    ui_print "* 开始DTBO修改过程"
    ui_print ""
    ui_print ""
    LMKDT=$MODPATH/bin/mkdtimg
    ui_print "- 解包DTBO中。。。"
    $LMKDT dump $DTBOTMP -b dtb >/dev/null 2>&1
    wait

    for i in dtb.*; do
        PATCH_DTB $i &
    done
    wait
    ui_print "- 打包DTBO中。。。"

    $LMKDT create $DTBOTMP --page_size=4096 dtb.* >/dev/null 2>&1
    wait
}

model=$(getprop ro.product.vendor.name)
ui_print "机型代号: $model"
ui_print ""

DTBO_PARTI="/dev/block/bootdevice/by-name/dtbo$(getprop ro.boot.slot_suffix)"
DTBOTMP="${TMPDIR}/dtbo.img"

chmod +x $MODPATH/bin/*
dd if=$DTBO_PARTI of=$DTBOTMP
REPACKDTBO
ui_print ""
ui_print ""
ui_print "！ 刷入中，请勿关机"
dd if=$DTBOTMP of=$DTBO_PARTI

rm -r $MODPATH/bin
rm -r $MODPATH/patch
### AnyKernel setup
# global properties
properties() { '
kernel.string=Wild Plus Kernel by TheWildJames or Morgan Weedman
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

kernel_version=$(cat /proc/version | awk -F '-' '{print $1}' | awk '{print $3}')
case $kernel_version in
    5.1*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac

ui_print " " "  -> ksu_supported: $ksu_supported"
$ksu_supported || abort "  -> Non-GKI device, abort."

# boot install
if [ -L "/dev/block/bootdevice/by-name/init_boot_a" -o -L "/dev/block/by-name/init_boot_a" ]; then
    split_boot # for devices with init_boot ramdisk
    flash_boot # for devices with init_boot ramdisk
else
    dump_boot # use split_boot to skip ramdisk unpack, e.g. for devices with init_boot ramdisk
    write_boot # use flash_boot to skip ramdisk repack, e.g. for devices with init_boot ramdisk
fi
flash_dtbo
## end boot install
