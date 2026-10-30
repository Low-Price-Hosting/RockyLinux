#!/bin/bash
set -euo pipefail

# Kiwi calls this after unmounting its shared package cache, before packaging.
# Fail rather than publish an image containing the build-only CA bundle.
if [ -e /var/cache/kiwi/koji-build-ca.pem ]; then
    echo 'Build-only CA bundle remains in the image filesystem' >&2
    exit 1
fi
rm -f /image/koji-build-ca.pem /image/build-repo-ca.sh

if [ -f /.profile ]; then
    . /.profile
fi

# oci-import publishes this tree verbatim.
if [[ "${kiwi_profiles:-}" == *"Container"* ]]; then
    rm -f /.profile /.kconfig
    rm -f /var/log/dnf.log /var/log/dnf.librepo.log /var/log/dnf.rpm.log \
          /var/log/hawkey.log

    # <rpm-locale-filtering> is inert under dnf: kiwi writes %_install_langs
    # to usr/lib/rpm/macros.d, which rpm resolves against the host rather
    # than the install root. Match what %_install_langs en_US would keep.
    find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en' \
         ! -name 'en_*' ! -name 'en@*' -exec rm -rf {} +
fi
