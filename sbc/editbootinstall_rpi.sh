#!/bin/bash
# from: https://build.opensuse.org/package/show/openSUSE:Factory:ToTest/kiwi-templates-Minimal
set -euxo pipefail

diskname=$1
devname="$2"
loopname="${devname%*p?}"
#loopdev=${loopname#/dev/mapper/*}

#==========================================
# copy Raspberry Pi firmware to EFI partition
#------------------------------------------
echo "RPi EFI system, installing firmware on ESP"
mkdir -p ./mnt-pi
mount ${loopname}p3 ./mnt-pi
( rm -fv ./mnt-pi/boot/initramfs-* )
umount ./mnt-pi
rmdir ./mnt-pi

#==========================================
# Change partition label type to MBR
#------------------------------------------
#
# The target system doesn't support GPT, so let's move it to
# MBR partition layout instead.
#
# Also make sure to set the ESP partition to type 0xc so that
# broken firmware (Rpi) detects it as FAT.
#
# Use tabs, "<<-" strips tabs, but no other whitespace!
cat > gdisk.tmp <<-'EOF'
		x
		r
		g
		t
		1
		c
		w
		y
	EOF
dd if=$loopname of=mbrid.bin bs=1 skip=440 count=4
gdisk $loopname < gdisk.tmp
dd of=$loopname if=mbrid.bin bs=1 seek=440 count=4
rm -f mbrid.bin
rm -f gdisk.tmp
