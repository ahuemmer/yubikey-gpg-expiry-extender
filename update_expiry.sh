#!/bin/bash

source ./base.sh

currentDate=$(date "+${DATE_TIME_FORMAT}")
luksPassphrase=
keyPassphrase=
GNUPGHOME=
scriptPath="$(cd "$(dirname "$0")" ; pwd -P)"
interactive=""

if [[ "$1" == "-i" ]] || [[ "$1" == "--interactive" ]]; then
  echo "\"Interactive\" flag was given. Using interactive mode to ask for continuation before each command block."
  echo
  interactive=true
fi

pre_checks() {
  echo "Running pre-checks..."
  echo -n "  - Absence of Internet access... "
  ping -c 1 ${SERVER_TO_PING} >/dev/null 2>&1 && die "System is connected to the internet!"
  ok
  echo -n "  - Presence of key master usb stick... "
  [[ -b /dev/disk/by-id/${MASTER_USB_STICK_UUID} ]] || die "Not found!"
  ok
  echo -n "  - Presence of key backup usb stick... "
  [[ -b /dev/disk/by-id/${BACKUP_USB_STICK_UUID} ]] || die "Not found!"
  ok
  echo -n "  - Presence of \"transport\" usb stick... "
  [[ -b /dev/disk/by-id/${PUBLIC_USB_STICK_UUID} ]] || die "Not found!"
  ok
  echo -n "  - Presence of YubiKey ... "
  gpg --card-status 2>&1 | grep Yubikey >/dev/null || die "Not found!"
  ok
  echo ""
}

ask_credentials() {
  [[ $interactive ]] && confirm "Go on asking for credentials?"
  if [[ -z "${LUKS_PASSPHRASE}" ]]; then
    echo "Asking for credentials:"
    echo -n "  - Please enter LUKS passphrase: "
    read -rs luksPassphrase
    echo -e "${green}OK${reset} (<-- this doesn't mean the passphrase is valid!)"
    echo
  else
    luksPassphrase=${LUKS_PASSPHRASE}
  fi
}

mount_ram_drive() {
  [[ $interactive ]] && confirm "Mount RAM drive for ephemeral GNUPGHOME?"
  echo "Mounting RAM drive:"
  echo -n "  - Check and do mount... "
  if mountpoint -q ${RAM_DRIVE_MOUNTPOINT}; then
    die "Was mounted already!"
  fi
  sudo mkdir -p ${RAM_DRIVE_MOUNTPOINT} || die "Could not find/create ${RAM_DRIVE_MOUNTPOINT}!"
  sudo mount -t tmpfs none -o size=32M ${RAM_DRIVE_MOUNTPOINT} || die "Could not mount RAM drive at ${RAM_DRIVE_MOUNTPOINT}!"
  export GNUPGHOME=$(mktemp -d -p ${RAM_DRIVE_MOUNTPOINT})
  ok
  echo "    --> New GNUPGHOME is ${GNUPGHOME}."
  echo -n "  - Restarting pcscd... "
  sudo -E systemctl restart pcscd && sleep 2 || die "Failed!"
  ok
  echo -n "  - Creating fake pinentry script... "
  fakePinentryPath=${GNUPGHOME}/${FAKE_PINENTRY_SH_FILE_NAME}
  echo "#!/bin/bash" > ${fakePinentryPath} || die "Echo failed!"
  echo ${adminPin@A} >> ${fakePinentryPath} || die "Echo failed!"
  echo "cardNumber=${SMARTCARD_NUMBER@Q}" >> ${fakePinentryPath} || die "Echo failed!"
  echo ${keyPassphrase@A} >> ${fakePinentryPath} || die "Echo failed!"
  echo "masterKeyId=${MASTER_KEY_ID}" >> ${fakePinentryPath} || die "Echo failed!"
  cat ${scriptPath}/${FAKE_PINENTRY_SH_TEMPLATE_FILE_NAME} >> ${fakePinentryPath} || die "Cat failed!"
  chmod u+x ${fakePinentryPath} || die "Chmod failed!"
  ok
  echo -n "  - Creating gpg-agent.conf... "
  echo "pinentry-program ${fakePinentryPath}" > ${GNUPGHOME}/gpg-agent.conf || die "Failed!"
  ok
  echo
}

umount_ram_drive() {
  [[ $interactive ]] && confirm "Umount RAM drive of ephemeral GNUPGHOME?"
  echo "Unmounting RAM drive:"
  echo -n "  - Executing Unmount... "
  if mountpoint -q ${RAM_DRIVE_MOUNTPOINT}; then
    sudo umount ${RAM_DRIVE_MOUNTPOINT} || die "Could not unmount RAM drive at ${RAM_DRIVE_MOUNTPOINT}!"
    ok
  else
    echo "Seems not to have been mounted..."
  fi
  echo -n "  - Resetting GNUPGHOME... "
  export GNUPGHOME=
  echo -e "${green}OK${reset} - Reset GNUPGHOME to empty string."
  echo
}

mount_luks() {
  [[ $interactive ]] && confirm "LUKS-mount $1 USB stick?"
  if [[ "$1" == "master" ]]; then
    echo -n "Mounting encrypted USB stick (master) "
    mountingpoint=${MASTER_USB_STICK_MOUNTPOINT}
    mountdevice=/dev/disk/by-id/${MASTER_USB_STICK_UUID}
    mappingname=${MASTER_USB_STICK_MAPPING_NAME}
  elif [[ "$1" == "backup" ]]; then
    echo -n "Mounting encrypted USB stick (backup) "
    mountingpoint=${BACKUP_USB_STICK_MOUNTPOINT}
    mountdevice=/dev/disk/by-id/${BACKUP_USB_STICK_UUID}
    mappingname=${BACKUP_USB_STICK_MAPPING_NAME}
  else
    die "Must specify \"master\" or \"backup\" as first argument to ${FUNCNAME[0]}!"
  fi

  if [[ ! -b $mountdevice ]]; then
    die "Device ${mountdevice} not found!"
  fi
  
  optionFlag=ro
  if [[ "$2" == "rw" ]]; then
    echo "with read and write access: "
    optionFlag=rw
  else
    echo "read-only: "
  fi
  
  echo -n "  - Cheking mountpoint... "
  sudo mkdir -p ${mountingpoint} || die "Could not find/create ${mountingpoint}!"
  if mountpoint -q ${mountingpoint}; then
    echo
    echo -n "  Was mounted alreay! Remounting..."
    optionFlag=remount,${optionFlag}
  fi
  ok
  
  if [[ -z "${luksPassphrase}" ]]; then
    echo -n "  Please enter LUKS passphrase: "
    read -s luksPassphrase
    echo ""
  fi
  
  echo -n "  - Decrypting volume... "
  echo -n "${luksPassphrase}" | sudo cryptsetup luksOpen ${mountdevice} ${mappingname} -d - || die "Could not decrypt volume ${mountdevice} using given password!"
  ok
    
  echo -n "  - Mounting decrypted volume... "
  sudo mount /dev/mapper/${mappingname} ${mountingpoint} -o ${optionFlag} || die "Could not (re)mount /dev/mapper/${mappingname} at ${mountingpoint}!"
  ok
  
  echo
}

retrieve_secret_data() {
  [[ $interactive ]] && confirm "Retrieve secret data from ${PASSWORD_FILE}?"
  echo "Retrieving secret data: "
  echo -n "  - Checking for file presence... "
  [[ -f ${PASSWORD_FILE} ]] || die "File not found!"
  ok
  echo -n "  - Retrieving passphrase... "
  keyPassphrase=$(sed "${SECRET_KEY_PASSWORD_LINE}q;d" ${PASSWORD_FILE}) || die "Failed!"
  [[ -z "${keyPassphrase}" ]] && die "Got an empty passphrase!"
  #keyPassphrase=$(cat ${PASSWORD_FILE}|sed -n 2p|tr -d '\r\n') || die "Failed!"
  ok
  echo -n "  - Retrieving admin pin... "
  adminPin=$(sed "${ADMIN_PIN_LINE}q;d" ${PASSWORD_FILE}) || die "Failed!"
  [[ -z "${adminPin}" ]] && die "Got an empty passphrase!"
  ok
  echo
}

umount_luks() {
  [[ $interactive ]] && confirm "LUKS-Unmount $1 usb stick?"
  if [ "$1" == "master" ]; then
    echo "Unmounting encrypted USB stick (master): "
    mountingpoint=${MASTER_USB_STICK_MOUNTPOINT}
    mappingname=${MASTER_USB_STICK_MAPPING_NAME}
  elif [ "$1" == "backup" ]; then
    echo "Unmounting encrypted USB stick (backup): "
    mountingpoint=${BACKUP_USB_STICK_MOUNTPOINT}
    mappingname=${BACKUP_USB_STICK_MAPPING_NAME}
  else
    die "Must specify \"master\" or \"backup\" as first argument to ${FUNCNAME[0]}!"
  fi
  
  echo -n "  - Checking mountpoint... "
  if mountpoint -q ${mountingpoint}; then
    sudo umount /dev/mapper/${mappingname} || die "Could not unmount /dev/mapper/${mappingname}!"
    ok
  else
    echo "Seems not to be mounted..."
  fi
  
  echo -n "  - Undecrypting device... "
  if [ -b "/dev/mapper/${mappingname}" ]; then
    sudo cryptsetup luksClose ${mappingname} || die "Could not undecrypt device!"
    ok
  else
    echo "Seems not to have been decrypted..."
  fi  
  echo
}

copy_old_gnupghome() {
  [[ $interactive ]] && confirm "Copy old GNUPGHOME content?"
  echo "Copying old GNUPGHOME content: "
  echo -n "  - Searching for last GNUPGHOME... "
  #echo "Executing: ls -td ${MASTER_USB_STICK_MOUNTPOINT}/${GNUPG_HOME_PREFIX}* | head -1"
  oldgnupghome=$(ls -td ${MASTER_USB_STICK_MOUNTPOINT}/${GNUPG_HOME_PREFIX}* | head -1)
  if [[ -z "${oldgnupghome}" ]] || [[ "." == "${oldgnupghome}" ]]; then
    die "Could not find old GNUPGHOME."
  fi
  echo -e "${green}OK${reset} - found ${oldgnupghome}."
  echo -n "  - Copying data... "
  sudo cp -r ${oldgnupghome}/* ${GNUPGHOME} || die "Could not copy data from ${oldgnupghome}/* to ${GNUPGHOME}!"
  ok
  echo -n "  - Adjusting access rights... "
  sudo chown -R user ${GNUPGHOME} || die "Failed!"
  ok
  echo
}

set_new_expiry_date() {
  [[ $interactive ]] && confirm "Update key expiry dates?"
  echo "Updating key expiry dates: "
  echo -n "  - Updating master key expiry date... "
  #gpg --pinentry-mode loopback --quick-set-expire --passphrase "${keyPassphrase}" "${MASTER_KEY_FINGERPRINT}" ${DAYS_UNTIL_EXPIRY} || die "Could not update expiry date of key with fingerprint ${MASTER_KEY_FINGERPRINT}!"
  gpg --quick-set-expire "${MASTER_KEY_FINGERPRINT}" ${DAYS_UNTIL_EXPIRY} || die "Could not update expiry date of key with fingerprint ${MASTER_KEY_FINGERPRINT}!"
  ok
  echo -n "  - Updating subkeys expiry date... "
  gpg --quick-set-expire "${MASTER_KEY_FINGERPRINT}" ${DAYS_UNTIL_EXPIRY} '*' || die "Could not update expiry date of subkeys of key with fingerprint ${MASTER_KEY_FINGERPRINT}!"
  ok
  echo -n "  - Generating new revocation certificate... "
  if [[ -f ${GNUPGHOME}/revoke.asc ]]; then
    rm ${GNUPGHOME}/revoke.asc || die "Could not delete old revocation certificate!"
  fi
  echo -e "y\n0\n\ny\n" | gpg --command-fd 0 --output ${GNUPGHOME}/revoke.asc --no-tty --gen-revoke ${MASTER_KEY_ID} || die "Failed!"
  [[ -s "${GNUPGHOME}/revoke.asc" ]] || die "Failed! Revocation certificate file does not exist or is empty!"
  ok
  echo
}

copy_new_gnupghome() {
  [[ $interactive ]] && confirm "Copy new GNUPGHOME to master USB stick?"
  folderName=${GNUPG_HOME_PREFIX}${currentDate}
  umount_luks master
  mount_luks master rw
  echo "Copying new GNUPGHOME:"
  echo -n "  - Creating new dir ${MASTER_USB_STICK_MOUNTPOINT}/${folderName}... "
  sudo mkdir -p ${MASTER_USB_STICK_MOUNTPOINT}/${folderName} || die "Could not create dir!"
  ok
  echo -n "  - Copying GNUPGHOME content to newly created dir..."
  sudo cp -r ${GNUPGHOME}/* ${MASTER_USB_STICK_MOUNTPOINT}/${folderName} || die "Could not copy files!"
  ok
  echo -n "  - Correcting access rights..."
  sudo chown user ${MASTER_USB_STICK_MOUNTPOINT}/${folderName} || die "Chown failed!"
  sudo chmod 0700 ${MASTER_USB_STICK_MOUNTPOINT}/${folderName} || die "Chmod failed!"
  ok
  echo -n "  - Copying key-scripts... "
  sudo mkdir -p ${MASTER_USB_STICK_MOUNTPOINT}/${KEY_SCRIPT_FOLDER_NAME} || die "Folder creation failed!"
  sudo cp -r ${scriptPath}/* ${MASTER_USB_STICK_MOUNTPOINT}/${KEY_SCRIPT_FOLDER_NAME} || die "Copying scripts failed!"
  ok
  echo
  umount_luks master
  #Remount read-only
  mount_luks master
}

create_backups() {
  [[ $interactive ]] && confirm "Backup master USB stick contents to backup USB stick?"
  mount_luks backup rw
  echo "Backing up master USB stick contents to backup USB stick:"
  echo -n "  - Creating backup of master usb stick on backup usb stick... "
  sudo cp -r ${MASTER_USB_STICK_MOUNTPOINT}/* ${BACKUP_USB_STICK_MOUNTPOINT} || die "Copy Failed!"
  ok
  echo
  umount_luks backup
}

move_keys_to_yubikey() {
  [[ $interactive ]] && confirm "Move regenerated keys to YubiKey?"
  echo "Moving regenerated keys to YubiKey:"
  echo -n "  - Making sure YubiKey is still present... "
  gpg --card-status 2>&1 | grep Yubikey >/dev/null || die "YubiKey not found any more!"
  ok
  echo -n "  - Moving Keys to YubiKey... "
  echo -e "key 1\nkeytocard\n1\ny\nkey 1\nkey 2\nkeytocard\n2\ny\nkey 2\nkey 3\nkeytocard\n3\ny\nsave\n"|gpg --command-fd 0 --no-tty --edit-key ${MASTER_KEY_ID} >/dev/null 2>&1 || die "Failed!"
  #gpg --edit-key ${MASTER_KEY_ID} || die "Failed!"
  ok
  echo
}

copy_public_files() {
  [[ $interactive ]] && confirm "Copy public files to \"transport\" USB stick?"
  echo "Copying public files to \"transport\" USB stick:"
  echo -n "  - Mounting \"transport\" usb stick... "
  sudo mkdir -p ${PUBLIC_USB_STICK_MOUNTPOINT} || die "Could not create/access mount point at ${PUBLIC_USB_STICK_MOUNTPOINT}."
  if mountpoint -q ${PUBLIC_USB_STICK_MOUNTPOINT}; then
    echo -n "Something is already mounted at ${PUBLIC_USB_STICK_MOUNTPOINT}! Unmouting..."
    sudo umount ${PUBLIC_USB_STICK_MOUNTPOINT} || die "Unmounting failed!"
    ok
    echo -n "  - Mounting \"transport\" stick now... "
  fi
  sudo mount /dev/disk/by-id/${PUBLIC_USB_STICK_UUID} ${PUBLIC_USB_STICK_MOUNTPOINT} || die "Failed!"
  ok
  echo -n "  - Checking / correcting access rights... "
  pushd ${PUBLIC_USB_STICK_MOUNTPOINT} >/dev/null 2>&1 || die "Pushd failed!"
  chown user . || die "Chown failed!"
  chmod 700 . || die "Chmod failed!"
  popd >/dev/null 2>&1 || die "Popd failed!"
  ok
  echo -n "  - Exporting public key to to \"transport\" usb stick... "
  gpg --export --armor --output ${PUBLIC_USB_STICK_MOUNTPOINT}/public_key_${currentDate}.asc ${MASTER_KEY_ID} || die "Failed!"
  ok
  echo -n "  - Copying key-scripts to \"transport\" usb stick... "
  mkdir -p ${PUBLIC_USB_STICK_MOUNTPOINT}/${KEY_SCRIPT_FOLDER_NAME} || die "Folder creation failed!"
  cp -r ${scriptPath}/* ${PUBLIC_USB_STICK_MOUNTPOINT}/${KEY_SCRIPT_FOLDER_NAME} || die "Copying scripts failed!"
  ok
  echo -n "  - Unmounting \"transport\" usb stick..."
  sudo umount ${PUBLIC_USB_STICK_MOUNTPOINT} || die "Failed!"
  ok  
  echo
}

cleanup() {
  if [[ $? -ne 0 ]]; then
    [[ $interactive ]] && confirm "Clean up after unsuccessful operation?"
    echo "Cleaning up after unsuccessful operation... "
    sudo umount ${MASTER_USB_STICK_MOUNTPOINT} || true
    sudo umount ${BACKUP_USB_STICK_MOUNTPOINT} || true
    sudo cryptsetup luksClose /dev/mapper/${MASTER_USB_STICK_MAPPING_NAME} || true
    sudo cryptsetup luksClose /dev/mapper/${BACKUP_USB_STICK_MAPPING_NAME} || true
    sudo umount ${RAM_DRIVE_MOUNTPOINT}  || true
    echo "done"
    echo
  else
    echo -e "${bold}${green}Finished successfully! :-)${reset}"
    echo
  fi
  
}

trap cleanup EXIT

pre_checks
ask_credentials
mount_luks master
retrieve_secret_data
mount_ram_drive
copy_old_gnupghome
set_new_expiry_date
copy_new_gnupghome
create_backups
move_keys_to_yubikey
copy_public_files
umount_luks master
umount_ram_drive


