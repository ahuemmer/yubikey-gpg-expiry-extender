#!/bin/bash

DEFAULT_IMAGE_FILE=./image.iso
MBR_BIN_PATH=/usr/share/syslinux/mbr.bin

usb_device=
image_file=
real_device=
yes_mode=false

while getopts "d:i:y" opt; do
   case ${opt} in
       d) usb_device=${OPTARG};;
       i) image_file=${OPTARG};;
       y) yes_mode=true; echo "\"Yes-Mode\" enabled by \"-y\" flag. Assuming positive answer on all \"Are you sure...?\"-like questions."
   esac
done

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
    die "Device \"${real_device}\" does not exist or isn't a block device!"
  fi
}

get_partitions() {
  echo $(ls ${real_device})
}

get_image_file() {
  if [ -z "${image_file}" ]; then
    echo "No image file given using \"-i\" parameter. Trying to use default image file \"${DEFAULT_IMAGE_FILE}\"."
    image_file=${DEFAULT_IMAGE_FILE}
  fi
  image_file=$(realpath ${image_file})
  if [[ ! -r ${image_file} ]]; then
    die "Image file \"${image_file}\" is not present or not readable. Please supply a valid image file path using the \"-i\" parameter. Aborting."
  fi
}

check_real_device() {
  partitions=$(get_partitions ${real_device})
  while read -r partition; do
    if [ -z "${partition}" ]; then
      continue
    fi
    if $(findmnt -rno SOURCE "${partition}" >/dev/null); then
      die "It seems that at least the partition \"${partition}\" of the device \"${real_device}\" is mounted! Aborting."
    fi
  done <<< "${partitions}"

  if [ -z "${partitions}" ]; then
    echo "It seems there are no (identifyable) partitions on \"${real_device}\". Please note that any data on the device will be lost if you continue though."
  else
    partition_count=$(echo "{$partitions}" | wc -l)
    echo "Device \"${real_device}\" contains ${partition_count} partition(s). All data on these partitions will be deleted!"
  fi
}


check_prerequisites
get_real_device
get_image_file
check_real_device


if ${yes_mode} || yesNoInput "Really go on?"; then
  echo "STARTING PROCESS. This may take a while..."
  echo
  echo -n "Writing image to ${real_device}..."
##  dd if=${image_file} of=${real_device} >/dev/null || die "dd failed!"
  dd if=/dev/zero of=${real_device} bs=512 count=1
  wipefs -afq ${real_device}
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
        set 2 boot on
  if [ $? -ne 0 ]; then
    die "parted failed. Aborting."
  fi
  sgdisk ${real_device} --hybrid 2:1
  parted -s -a optimal -- ${real_device} \
    set 2 boot on
  cat "${MBR_BIN_PATH}" > ${real_device}
  mkfs.vfat -F 32 -n XFCE ${real_device}2 >/dev/null || die "mkfs.fat32 failed. Aborting."
  mkfs.ext4 -L persistence ${real_device}3 >/dev/null || die "mkfs.ext4 failed. Aborting."
  sync || echo "Warning: Sync failed."
  echo "finished!"
  mkdir -p /media/live-usb
  mount ${real_device}2 /media/live-usb
  pushd /media/live-usb >/dev/null
  7z x ${image_file}
  mv isolinux syslinux
  mv syslinux/isolinux.cfg syslinux/syslinux.cfg
  mv syslinux/isolinux.bin syslinux/syslinux.bin
  cp boot/grub/grub.cfg boot/grub/grub.cfg.bak
  sed -i 's/\(boot=live.*\)$/\1 persistence/' boot/grub/grub.cfg
  cp syslinux/menu.cfg syslinux/menu.cfg.bak
  sed -i 's/\(boot=live.*\)$/\1 persistence/' syslinux/menu.cfg
  mkdir -p /media/live-usb-persistence
  mount ${real_device}3 /media/live-usb-persistence
  echo / union > /media/live-usb-persistence/persistence.conf
  grub-install --target=x86_64-efi --efi-directory=/media/live-usb --boot-directory=/media/live-usb/boot --removable --recheck ${real_device}
  #grub-install --target=i386-pc --boot-directory=/media/live-usb/boot --recheck --removable ${real_device}
  popd >/dev/null
  umount ${real_device}2
  umount ${real_device}3
  rm -r /media/live-usb
  rm -r /media/live-usb-persistence
  echo
  echo "PROCESS FINISHED"
  exit 0
else
  echo
  echo "PROCESS ABORTED"
  exit 1
fi
