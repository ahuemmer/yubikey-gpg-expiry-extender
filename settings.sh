#!/bin/bash

# CONSTANTS - probably no need to change
SERVER_TO_PING=www.google.de
RAM_DRIVE_MOUNTPOINT=/media/ram-secret
DATE_TIME_FORMAT=%Y%m%d%H%M%S
GNUPG_HOME_PREFIX=gnupghome_

# For some reason, the Yubikey will report with a string containing "Yubikey" OR "Yubico" when using `gpg --card-status`
# As of now, I couldn't find out why... Adapt this according to what your system behaves like.
# You might as well use a more specific value like the serial number of your YubiKey - it just needs to be part of the
# output of `gpg --card-status` in order for the Yubikey to be considered present.
YUBIKEY_GPG_CARD_STATUS_IDENTIFIER=Yubico

BACKUP_USB_STICK_UUID=usb-VendorCo_ProductCode_1231231231231231231-0:0-part1
BACKUP_USB_STICK_MOUNTPOINT=/media/key-backup
BACKUP_USB_STICK_MAPPING_NAME=key-backup

MASTER_USB_STICK_UUID=usb-VendorCo_ProductCode_9879879879879879879-0:0-part1
MASTER_USB_STICK_MOUNTPOINT=/media/key-master
MASTER_USB_STICK_MAPPING_NAME=key-master

MASTER_KEY_FINGERPRINT=123456789ABCDEFFEDCBA9876543210123456789
MASTER_KEY_ID=0xFEDCBA9876543210
SMARTCARD_NUMBER=01234567

# Todo: Retrieve automatically from gpg --card-status?
SUB_KEY_FINGERPRINTS="123456789ABCDEFFEDCBA9876543210123456789 123456789ABCDEFFEDCBA9876543210123456789 123456789ABCDEFFEDCBA9876543210123456789"

PUBLIC_USB_STICK_UUID=usb-VendorCo_ProductCode_6546546546546546546-0:0-part1
PUBLIC_USB_STICK_MOUNTPOINT=/media/public

# Days "from now" until "new" key expiry
DAYS_UNTIL_EXPIRY=128

# File containing the passwords and lines in it containing the specific ones neeeded:
PASSWORD_FILE=${MASTER_USB_STICK_MOUNTPOINT}/Passwords.txt
SECRET_KEY_PASSWORD_LINE=6
ADMIN_PIN_LINE=18

KEY_SCRIPT_FOLDER_NAME=key-scripts
FAKE_PINENTRY_SH_TEMPLATE_FILE_NAME=fake-pinentry.sh.template
FAKE_PINENTRY_SH_FILE_NAME=fake-pinentry.sh
