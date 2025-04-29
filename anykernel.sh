### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers
### AnyKernel setup
# global properties
#!/bin/bash
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
set -e

# 初始化环境
export PATH="/system/bin:$PATH"
LOGFILE="/dev/null"  # 可替换为实际日志路径

COLOR_NORMAL=""
COLOR_GREEN=""
COLOR_RED=""
COLOR_YELLOW=""
[ -t 1 ] && {
    COLOR_NORMAL="\033[0m"
    COLOR_GREEN="\033[32m"
    COLOR_RED="\033[31m"
    COLOR_YELLOW="\033[33m"
}

log() {
    echo "${COLOR_YELLOW}[$(date '+%T')] $1${COLOR_NORMAL}"
}

abort() {
    echo "${COLOR_RED}ERROR: $1${COLOR_NORMAL}" >&2
    exit 1
}

[ "$(id -u)" -ne 0 ] && abort "请以root权限运行此脚本"

trap 'rm -f dtb.* dts.dtb.* dtbo_new.img dtbo.img 2>/dev/null' EXIT

# 自定义函数：从指定分区读取 dtbo 数据并保存为本地文件
read_dtbo_from_partition() {
    local partition_path="$1"
    local output_file="$2"
    log "从分区 $partition_path 读取 dtbo 数据并保存到 $output_file"
    dd if="$partition_path" of="$output_file" bs=1M 2>/dev/null || abort "从分区 $partition_path 读取数据失败"
    log "读取完成，文件已保存到 $output_file"
}

# 获取当前槽位信息
current_slot=$(getprop ro.boot.slot_suffix)
[ -z "$current_slot" ] && abort "未检测到A/B分区，请确认设备支持A/B系统"
target_slot=$([ "$current_slot" = "_a" ] && echo "_b" || echo "_a")
log "分区槽信息：当前槽位=${current_slot} 目标槽位=${target_slot}"

# 定义分区路径
DTBO_A="/dev/block/by-name/dtbo_a"
DTBO_B="/dev/block/by-name/dtbo_b"

# 从当前槽位的 dtbo 分区读取数据并保存为本地文件
read_dtbo_from_partition "/dev/block/by-name/dtbo${current_slot}" "dtbo.img"

# 开始处理 dtbo 镜像
log "开始处理 dtbo 镜像..."
log "步骤1/4 解包 dtbo.img"
./bin/mkdtimg dump dtbo.img -b dtb >$LOGFILE 2>&1 || abort "dtbo 解包失败"

log "步骤2/4 转换 dtb 至 dts"
for dtb_file in dtb.*; do
    [ -f "$dtb_file" ] || continue
    log "正在处理: $dtb_file"
    ./bin/dtc -I dtb -O dts -@ -o "${dtb_file}.dts" "$dtb_file" >$LOGFILE 2>&1 || abort "DTB 转 DTS 失败"
    mv "${dtb_file}.dts" "dts.${dtb_file}"
done

log "步骤3/4 修改标识"
sed_modified=false
for dts_file in dts.dtb.*; do
    [ -f "$dts_file" ] || continue
    sed -i 's/HMBIRD_OGKI/HMBIRD_GKI/g' "$dts_file"
    grep -q 'HMBIRD_GKI' "$dts_file" && sed_modified=true
done
$sed_modified || abort "关键字符串替换未生效"

log "步骤4/4 重新打包 dtbo"
for dts_file in dts.dtb.*; do
    [ -f "$dts_file" ] || continue
    ./bin/dtc -I dts -O dtb -@ -o "${dts_file}.dtb" "$dts_file" >$LOGFILE 2>&1 || abort "DTS 转 DTB 失败"
    mv "${dts_file}.dtb" "${dts_file#dts.}"
done

./bin/mkdtimg create dtbo_new.img dtb.* >$LOGFILE 2>&1 || abort "dtbo 重组失败"
log "第一阶段完成，生成文件大小: $(du -sh dtbo_new.img | cut -f1)"

SOURCE="dtbo_new.img"
TARGET="dtbo.img"

verify_partition() {
    local partition="$1"
    [ -b "$partition" ] || abort "无法定位分区: $partition"
    log "验证分区可写性：[ $partition ]"
    dd if=/dev/zero of="$partition" bs=1 count=1 conv=notrunc 2>/dev/null || {
        echo "${COLOR_YELLOW}警告：分区可能处于只读状态，尝试重新挂载..."
        blockdev --setrw "$partition" 2>/dev/null || abort "分区写保护解除失败"
    }
}

# 还原目标槽位的 dtbo 分区
log "还原目标槽位的 dtbo 分区..."
if [ "$target_slot" = "_a" ]; then
    verify_partition "$DTBO_A"
    dd if="$TARGET" of="$DTBO_A" bs=1M 2>/dev/null || abort "还原分区失败"
else
    verify_partition "$DTBO_B"
    dd if="$TARGET" of="$DTBO_B" bs=1M 2>/dev/null || abort "还原分区失败"
fi
sync
log "还原完成，等待缓存同步"

# 将修改后的 dtbo 文件刷入当前槽位
log "将修改后的 dtbo 文件刷入当前槽位..."
if [ "$current_slot" = "_a" ]; then
    verify_partition "$DTBO_A"
    dd if="$SOURCE" of="$DTBO_A" bs=1M 2>/dev/null || abort "分区刷写失败"
else
    verify_partition "$DTBO_B"
    dd if="$SOURCE" of="$DTBO_B" bs=1M 2>/dev/null || abort "分区刷写失败"
fi
sync
log "刷写完成，等待缓存同步"

# 执行分区校验
log "执行分区校验..."
if [ "$current_slot" = "_a" ]; then
    dd if="$DTBO_A" of="$TARGET" bs=1M 2>/dev/null || abort "验证数据提取失败"
else
    dd if="$DTBO_B" of="$TARGET" bs=1M 2>/dev/null || abort "验证数据提取失败"
fi