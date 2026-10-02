#!/bin/bash
# Modify this script to handle disk changes as needed.
# Some of this may be incorrect or not needed. You will need to verify this.

set -ex

#diskname="$1"
#devname="$2"
#loopname="${devname%*p2}"
#loopdev=/dev/${loopname#/dev/mapper/*}

# shellcheck disable=SC2034
image_fs="$1"
root_partnum="$2"
root_device="/dev/mapper/loop*p${root_partnum}"
loop_name="$(basename $root_device | cut -f 1-2 -d 'p')"
disk_device="/dev/${loop_name}"

# pi's probably don't support GPT.

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

  dd if="$disk_device" of=mbrid.bin bs=1 skip=440 count=4
  gdisk "$disk_device" < gdisk.tmp
  dd of="$disk_device" if=mbrid.bin bs=1 seek=440 count=4
  rm -f mbrid.bin
  rm -rf gdisk.tmp
