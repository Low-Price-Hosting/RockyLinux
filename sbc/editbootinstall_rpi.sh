#!/bin/bash
# from: https://build.opensuse.org/package/show/openSUSE:Factory:ToTest/kiwi-templates-Minimal
set -euxo pipefail

diskname=$1
devname="$2"
loopname="${devname%*p?}"
loopdev=${loopname#/dev/mapper/*}

#==========================================
# copy Raspberry Pi firmware to EFI partition
#------------------------------------------
echo "RPi EFI system, installing firmware on ESP"
mkdir -p ./mnt-pi
mount ${loopname}p3 ./mnt-pi
( rm -fv ./mnt-pi/boot/initramfs-* )
umount ./mnt-pi
rmdir ./mnt-pi

