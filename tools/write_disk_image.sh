###############################################
# 该脚本用于将disk_mount目录下的文件写入到disk.img的第一个分区中，
#       并在磁盘镜像中安装grub引导程序
#
# 用法：bash write_disk_image.sh --bios legacy/uefi
# 如果之前创建的disk.img是MBR分区表，那么请这样运行它：bash write_disk_image.sh --bios legacy
# 如果之前创建的disk.img是GPT分区表，那么请这样运行它：bash write_disk_image.sh --bios uefi
###############################################

ARCH="x86_64"
# 内核映像
root_folder=$(dirname $(pwd))
kernel="${root_folder}/bin/kernel/kernel.elf"
boot_folder="${root_folder}/bin/disk_mount/boot"
mount_folder="${root_folder}/bin/disk_mount"
ARGS=`getopt -o p -l bios: -- "$@"`
eval set -- "${ARGS}"
#echo formatted parameters=[$@]
echo "开始写入磁盘镜像..."


# toolchain
OS=`uname -s`
if [ "${OS}" == "Linux" ]; then
    GRUB_PATH="$(dirname $(which grub-file))"
elif [ "${OS}" == "Darwin" ]; then
    GRUB_PATH="${root_folder}/tools/grub-2.06/build/grub/bin"
fi
export PATH="${GRUB_PATH}:$PATH"

# ==============检查文件是否齐全================

bins[0]=${kernel}

for file in ${bins[*]};do
if [ ! -x $file ]; then
echo "$file 不存在！"
exit
fi
done

# ===============文件检查完毕===================

# 如果是 i386/x86_64，需要判断是否符合 multiboot2 标准
if [ ${ARCH} == "i386" ] || [ ${ARCH} == "x86_64" ]; then
    if ${GRUB_PATH}/grub-file --is-x86-multiboot2 ${kernel}; then
        echo Multiboot2 Confirmed!
    else
        echo NOT Multiboot2!
        exit
    fi
fi

# 判断是否存在硬盘镜像文件，如果不存在，就创建一个(docker模式下，由于镜像中缺少qemu-img不会创建)
if [ ! -f "${root_folder}/bin/disk.img" ]; then
    echo "创建硬盘镜像文件..."
    case "$1" in
        --bios) 
        case "$2" in
                uefi)
            sudo bash ./create_hdd_image.sh -P GPT #GPT分区
            ;;
                legacy)
            sudo bash ./create_hdd_image.sh -P MBR #MBR分区
            ;;
            esac       
        ;;
    *)
        # 默认创建MBR分区
        sudo bash ./create_hdd_image.sh -P MBR #MBR分区
        ;;
    esac
fi

# 拷贝程序到硬盘
mkdir -p ${root_folder}/bin/disk_mount
bash mount_virt_disk.sh || exit 1
mkdir -p ${boot_folder}/grub
cp ${kernel} ${root_folder}/bin/disk_mount/boot
# 拷贝用户程序到磁盘镜像
mkdir -p ${root_folder}/bin/disk_mount/bin
mkdir -p ${root_folder}/bin/disk_mount/dev
mkdir -p ${root_folder}/bin/disk_mount/proc
cp -r ${root_folder}/bin/user/* ${root_folder}/bin/disk_mount/bin
touch ${root_folder}/bin/disk_mount/dev/keyboard.dev

# 设置 grub 相关数据
if [ ${ARCH} == "i386" ] || [ ${ARCH} == "x86_64" ]; then
    
    touch ${root_folder}/bin/disk_mount/boot/grub/grub.cfg
cfg_content='set timeout=15
    set default=0
    menuentry "DragonOS" {
    multiboot2 /boot/kernel.elf "KERNEL_ELF"
}'
echo "echo '${cfg_content}' >  ${boot_folder}/grub/grub.cfg" | sh
fi

# rm -rf ${iso_folder}
LOOP_DEVICE=$(lsblk | grep disk_mount|sed 's/.*\(loop[0-9]*\)p1.*/\1/1g'|awk 'END{print $0}')
echo $LOOP_DEVICE
case "$1" in
    --bios) 
        case "$2" in
                uefi) #uefi
            grub-install --target=x86_64-efi  --efi-directory=${mount_folder}  --boot-directory=${boot_folder}  --removable
            ;;
                legacy) #传统bios
            grub-install --target=i386-pc --boot-directory=${boot_folder} /dev/$LOOP_DEVICE
            ;;
        esac
        ;;
    *)
    echo "参数错误"
    ;;
           
esac

sync
bash umount_virt_disk.sh
