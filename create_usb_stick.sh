#!/bin/bash

DEFAULT_IMAGE_FILE=./image.iso
MBR_BIN_PATH=/usr/share/syslinux/mbr.bin
DEFAULT_LOG_FILE=./create_usb_stick.log

usb_device=
image_file=
real_device=
yes_mode=false

# Colors and formatting:
red="\e[31m"
yellow="\e[93m"
reset="\e[0m"
code="\e[2m"
green="\e[32m"
bold="\e[1m"

while getopts "d:i:l:y" opt; do
   case ${opt} in
       d) usb_device=${OPTARG};;
       i) image_file=${OPTARG};;
       l) log_file=${OPTARG};;
       y) yes_mode=true; echo "\"Yes-Mode\" enabled by \"-y\" flag. Assuming positive answer on all \"Are you sure...?\"-like questions."
   esac
done

ok() {
  echo -e "${green}OK${reset}"
}

die() {
  >&2 echo -e $1
  exit 1
}

yesNoInput() {
while true; do
  read -p "$1 [y/n]: " yn
      case $yn in
          [Yy]* ) return 0; break;;
          [Nn]* ) return 1; break;;
          * ) echo "Please answer y or n.";;
      esac
  done

}

check_prerequisites() {
  if [[ ! -x "$(command -v wipefs)" ]]; then
    die "Command wipefs not found. Cannot continue."
  fi
  if [[ ! -x "$(command -v sgdisk)" ]]; then
    die "Command sgdisk not found. Cannot continue.\n(Hint: On Gentoo, install \"sys-apps/gptfdisk\". The package name MIGHT be similar in other distros.)"
  fi
  if [[ ! -x "$(command -v parted)" ]]; then
    die "Command parted not found. Cannot continue.\n(Hint: On Gentoo, install \"sys-block/parted\". The package name should be similar in other distros.)"
  fi
  if [[ ! -x "$(command -v 7z)" ]]; then
    die "Command 7z not found. Cannot continue.\n(Hint: On Gentoo, install \"app-arch/p7zip\". The package name should be similar in other distros.)"
  fi
  if [[ ! -x "$(command -v grub-install)" ]]; then
    die "Command grub-install not found. Cannot continue.\n(Hint: On Gentoo, install \"sys-boot/grub\". The package name should be similar in other distros.)"
  fi
  if [[ ! -f "${MBR_BIN_PATH}" ]]; then
    die "MBR image not found at ${MBR_BIN_PATH}. Cannot continue.\n(Hint: On Gentoo, install \"sys-boot/syslinux\". The package should have a similar name in other distros.)"
  fi
}

get_device_path() {
  local device=$1
  if [[ $name =~ ^.[0-9]$ ]]; then
   die "It seems you entered a _partition_ rather than a device."
  fi
  if [[ ${device} == /dev/* ]]; then
    echo ${device}
    return
  fi
  echo "/dev/${device}"
}

get_real_device() {
  if [ -z "${usb_device}" ]; then
    echo -n "Please specify device of USB stick: "
    read usb_device
  fi

  real_device=$(get_device_path ${usb_device})
  if [[ ! -b ${real_device} ]]; then
    die "${red}Device \"${real_device}\" does not exist or isn't a block device!${reset}"
  fi
}

get_log_file() {
  if [ -z "${log_file}" ]; then
    log_file=${DEFAULT_LOG_FILE}
  fi
  touch ${log_file} || die "${red}Log file at ${reset}${code}${log_file}${reset}${red} does not seem to be writable! Aborting."
  echo -e "Logging command outputs to ${code}${log_file}${reset}."
  echo
}

get_image_file() {
  if [ -z "${image_file}" ]; then
    echo -e "No image file given using ${code}-i${reset} parameter. Trying to use default image file ${code}${DEFAULT_IMAGE_FILE}${reset}."
    image_file=${DEFAULT_IMAGE_FILE}
  fi
  image_file=$(realpath ${image_file})
  if [[ ! -r ${image_file} ]]; then
    die "${red}Image file ${reset}${code}${image_file}${reset}${red} is not present or not readable. Please supply a valid image file path using the ${reset}${code}-i${reset}${red} parameter. Aborting.${reset}"
  fi
}

check_real_device() {
  deviceNameShort=${real_device#/dev/}
  partitions=$(ls ${real_device}*)
  while read -r partition; do
    if [ -z "${partition}" ]; then
      continue
    fi
    if $(findmnt -rno SOURCE "${partition}" >/dev/null); then
      die "${red}It seems that at least the partition ${reset}{$code}${partition}${reset}${red} of the device ${reset}${code}${real_device}${reset}${red} is mounted! Aborting.${reset}"
    fi
  done <<< "${partitions}"

  echo -e -n ${yellow}
  if [ -z "${partitions}" ]; then
    echo "It seems there are no (identifyable) partitions on ${reset}${code}${real_device}${reset}${yellow}. Please note that any data on the device will be lost if you continue though."
  else
    numPartitions=$(($(lsblk | grep ${deviceNameShort} | wc -l) - 1))
    echo -e "Device ${reset}${code}${real_device}${reset}${yellow} contains ${numPartitions} partition(s). All data on these partitions will be deleted!"
  fi
  echo -e -n ${reset}
}

check_prerequisites
get_real_device
get_image_file
get_log_file
check_real_device

answer=0

if [[ "${yes_mode}" != true ]]; then
  yesNoInput "Really go on?"
  answer=$?
fi

if [[ $answer -ne 0 ]]; then
  echo
  echo -e "${red}${bold}PROCESS ABORTED${reset}"
  exit 1
fi

echo -e "${bold}STARTING PROCESS${reset}"
echo "This may take a while..."
echo
echo -n "  - Erasing boot block of device... "
dd if=/dev/zero of=${real_device} bs=512 count=2 >>${log_file} 2>&1 && ok
echo -n "  - Wiping existing file systems... "
wipefs -afq ${real_device}  >>${log_file} 2>&1 && ok
echo -n "  - Re-partitioning device..."
parted -s -a optimal -- ${real_device} \
  mklabel gpt \
      unit mib \
      mkpart primary 1 3 \
      name 1 grub \
      set 1 bios_grub on \
      mkpart primary 3 4099 \
      name 2 rootfs \
      mkpart primary 4099 -1 \
      name 3 persistence \
      set 2 boot on \
       >>${log_file} 2>&1
if [ $? -ne 0 ]; then
  die "${code}parted${reset}${red} failed. Aborting.${reset}"
else
  ok
fi
echo -n "  - Hybridizing partition table... "
sgdisk ${real_device} --hybrid 2:1 >>${log_file} 2>&1 && ok
echo -n "  - Making partition 2 bootable... "
parted -s -a optimal -- ${real_device} \
  set 2 boot on \
   >>${log_file} 2>&1
ok
echo -n "  - Writing new boot block to device... "
cat "${MBR_BIN_PATH}" > ${real_device} && ok
echo -n "  - Formatting partition 2 with FAT32... "
mkfs.vfat -F 32 ${real_device}2  >>${log_file} 2>&1 && ok || die "mkfs.fat32 failed. Aborting."
echo -n "  - Formatting partition 3 with Ext4... "
mkfs.ext4 -L persistence ${real_device}3  >>${log_file} 2>&1 && ok || die "mkfs.ext4 failed. Aborting."
sync || echo "${yellow}  Warning: Sync failed.${reset}"
echo -n "  - Extracting image contents to partition 2... "
mkdir -p /media/live-usb >>${log_file} 2>&1
mount ${real_device}2 /media/live-usb
pushd /media/live-usb >>${log_file} 2>&1
7z x ${image_file}  >>${log_file} 2>&1
ok
echo -n "  - Preparing files... "
mv isolinux syslinux >>${log_file} 2>&1
mv syslinux/isolinux.cfg syslinux/syslinux.cfg >>${log_file} 2>&1
mv syslinux/isolinux.bin syslinux/syslinux.bin >>${log_file} 2>&1
cp boot/grub/grub.cfg boot/grub/grub.cfg.bak >>${log_file} 2>&1
sed -i 's/\(boot=live.*\)$/\1 persistence/' boot/grub/grub.cfg >>${log_file} 2>&1
cp syslinux/menu.cfg syslinux/menu.cfg.bak >>${log_file} 2>&1
sed -i 's/\(boot=live.*\)$/\1 persistence/' syslinux/menu.cfg >>${log_file} 2>&1
ok
echo -n "  - Preparing persistence partition... "
mkdir -p /media/live-usb-persistence >>${log_file} 2>&1
mount ${real_device}3 /media/live-usb-persistence >>${log_file} 2>&1
echo / union > /media/live-usb-persistence/persistence.conf
ok
echo -n "  - Installing GRUB... "
grub-install --target=x86_64-efi --efi-directory=/media/live-usb --boot-directory=/media/live-usb/boot --removable --recheck ${real_device} >>${log_file} 2>&1 && ok
#grub-install --target=i386-pc --boot-directory=/media/live-usb/boot --recheck --removable ${real_device}
echo -n "  - Cleaning up... "
popd  >>${log_file} 2>&1
umount ${real_device}2 >>${log_file} 2>&1
umount ${real_device}3 >>${log_file} 2>&1
rm -r /media/live-usb >>${log_file} 2>&1
rm -r /media/live-usb-persistence >>${log_file} 2>&1
ok
echo
echo -e "${green}${bold}PROCESS FINISHED${reset}"
exit 0
