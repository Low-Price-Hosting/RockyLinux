#!/bin/sh
# This is an annoying hack to get around grub deciding it has to probe for
# the host's boot data.
echo "###" "$0" "$@"

echo "Try to prevent grub from probing our host distribution"
echo "GRUB_DISABLE_OS_PROBER=true" >> etc/default/grub
cat etc/default/grub
