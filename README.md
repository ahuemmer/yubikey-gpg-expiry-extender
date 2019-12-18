# yubikey-gpg-expiry-extender
Collection of bash scripts for unattended extension of the expiry dates of gpg keys stored on a YubiKey

## What is it?

If you use a [YubiKey](https://www.yubico.com/products/) and its functionality to store GPG keys on it, as described [here](https://blog.josefsson.org/2014/06/23/offline-gnupg-master-key-and-subkeys-on-yubikey-neo-smartcard/) and/or [here](https://github.com/drduh/YubiKey-Guide), you might stumble upon the need to extend the expiry date of your keys every now and then.

This is a manual process consisting of many steps, especially if your're working on an offline machine and using LUKS encrypted storage usb sticks (which both seems quite reasonable to me). The scripts provided here will - in an ideal case :wink: - do the whole thing with you only needing to enter your LUKS encryption password, nothing more.

Please note, that the scripts are adapted to my setup and needs and though configurable (mostly via `settings.sh`) **rather considered as a referenace example** then something that would work "on the fly" on your machine! Nevertheless it took me quite a while to figure some things out and do some of the tricks to make it work.

## What will it do?

If everything goes well, the process should consist of:

1. Creating a temporary in-RAM `GNUPHHOME` which is used from then on
1. Decrypting the "master" usb stick containing your key
1. Copying its "last" `GNUPGHOME` dir over to the in-RAM one created at first
1. Extend the expiry date of the master key and all subkeys by `DAYS_UNTIL_EXPIRY` days (set in `settings.sh`)
1. Copy the new Keys to the "master" usb stick (a new `gnupghome_${date}` is created)
1. Backup all the "master" usb stick contents to the "backup" usb stick (which is also decrypted before)
1. *Then* copy your new keys onto the YubiKey
1. Export your new public key to a "transport" usb stick
1. Clean up

## Prerequisites

For this to work, a few prerequisites are needed (again, please note that this is just a reference implementation on my setup):

- The disk IDs of the "master", "backup" and "transport" USB sticks must be entered in `settings.sh`
- Dito for the master key fingerprint and id and smartcard number of the YubiKey
- On the "master" usb stick, there must be a file called `Passwords.txt` (or whatever you point `PASSWORD_FILE` to), containing the GPG passphrase of the private master key and the Admin PIN of your YubiKey in the lines denoted in `settings.sh`. *)
- Your system must contain the needed packages (again: see [here](https://blog.josefsson.org/2014/06/23/offline-gnupg-master-key-and-subkeys-on-yubikey-neo-smartcard/) and [here](https://github.com/drduh/YubiKey-Guide)) in a recent version
- There must be some keys present on your YubiKey already (so there's something to "overwrite")
- I might sure have forgotten some more...

*) This seems reasonably safe to me as the whole thing is intended to work offline!

## How to use it

1. Set up your offline system. The `create_usb_stick.sh` script *might* be helpful to achieve this (especially when given a Debian live ISO image :wink:), but you will have to install some more packages later on. (I even had to install a newer version of `gpg` to get things working...)
1. Edit `settings.sh` and replace my dummy values with the ones you need as mentioned above.
1. Run `update_expiry.sh` to do the magic. You *can* (and probably should...) use the only supported command line parameter `-i` / `--interactive` in order to be asked for confirmation before each block of actions is executed. Some prerequisites will be checked in the beginning.

## Disclaimer

I cannot guarantee the the scripts will work on your system! Furthermore, I even cannot ensure that they aren't harmful to your system, your YubiKey or the security of your data! 
These scripts are free software. It comes without any warranty, not even for merchantability or fitness for a particular purpose.

## Todo

There are lots of improvements supposable for the scripts:

- Better checking of prerequisited (including, e. g., presence of the tools and versions needed)
- Better error handling
- Checking the outcome of the specific steps (e. g. "Is the new key date *really* "today + 128 days"?)
- Improve cleaning up on error
- Improve (OK, create :wink:) documentation
- ...

I'm quite aware that they're far from perfect and some things they do (like the fake-pinentry stuff) are arguable, but for the moment, the whole thing suits my needs. I might add some improvements from time to time. Anyway, issues and pull requests are welcome and are more or less likely to be answered. :wink:

## References

- [Simon Josefsson: "Offline GnuPG Master Key and Subkeys on YubiKey NEO Smartcard"](https://blog.josefsson.org/2014/06/23/offline-gnupg-master-key-and-subkeys-on-yubikey-neo-smartcard/)
- [Simon Josefsson: "The Case for Short OpenPGP Key Validity Periods"](https://blog.josefsson.org/2014/08/26/the-case-for-short-openpgp-key-validity-periods/)
- [drduh's YubiKey-Guide](https://github.com/drduh/YubiKey-Guide)

Thanks to them (and many more) for their great work!