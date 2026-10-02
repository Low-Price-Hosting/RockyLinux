#!/bin/bash
set -euo pipefail

# Kiwi calls this after unmounting its shared package cache, before packaging.
# Fail rather than publish an image containing the build-only CA bundle.
if [ -e /var/cache/kiwi/koji-build-ca.pem ]; then
    echo 'Build-only CA bundle remains in the image filesystem' >&2
    exit 1
fi
rm -f /image/koji-build-ca.pem /image/build-repo-ca.sh
