#!/bin/bash
# Run only in a disposable privileged Rocky container, with this checkout at
# /description. Requires dnf, microdnf, openssl, createrepo_c, diffutils and python3.
set -euo pipefail

work=$(mktemp -d)
root=$work/image
server_pid=
mounts=()
cleanup() {
    [[ -z $server_pid ]] || kill "$server_pid"
    for ((i=${#mounts[@]}-1; i>=0; i--)); do
        umount "${mounts[i]}"
    done
}
trap cleanup EXIT
bind() {
    mount --bind "$1" "$2"
    mounts+=("$2")
}
mkdir -p "$root"/{usr,proc,dev,etc,image,var/cache/kiwi} "$work/repo"
ln -s usr/bin "$root/bin"
ln -s usr/lib "$root/lib"
ln -s usr/lib64 "$root/lib64"
bind /usr "$root/usr"
bind /dev "$root/dev"
bind /proc "$root/proc"
cp -a /etc/pki "$root/etc/"
cp /etc/os-release "$root/etc/"
bundle=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
cp "$bundle" "$work/original.pem"

# Serve real repository metadata using a private test CA. The image initially
# has only the original system trust, while the buildroot gets the extra CA.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=Test-CA \
    -keyout "$work/ca.key" -out "$work/ca.pem" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj /CN=localhost \
    -keyout "$work/server.key" -out "$work/server.csr" >/dev/null 2>&1
printf 'subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' > "$work/extensions"
openssl x509 -req -in "$work/server.csr" -CA "$work/ca.pem" \
    -CAkey "$work/ca.key" -CAcreateserial -days 1 -extfile "$work/extensions" \
    -out "$work/server.pem" >/dev/null 2>&1
cat "$work/ca.pem" >> "$bundle"
createrepo_c "$work/repo" >/dev/null
python3 - "$work" <<'PY' &
import functools
import http.server
from pathlib import Path
import ssl
import sys

work = Path(sys.argv[1])
server = http.server.HTTPServer(
    ('127.0.0.1', 18443),
    functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(work / 'repo')),
)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(work / 'server.pem', work / 'server.key')
server.socket = context.wrap_socket(server.socket, server_side=True)
(work / 'ready').touch()
server.serve_forever()
PY
server_pid=$!
for ((i=0; i<100; i++)); do
    [[ ! -e $work/ready ]] || break
    sleep 0.1
done
test -e "$work/ready"

mkdir -p /var/cache/kiwi/dnf/{repos,cache,vars}
bind /var/cache/kiwi "$root/var/cache/kiwi"
cat > /var/cache/kiwi/dnf/repos/test.repo <<'EOF'
[test]
name=Private CA test
baseurl=https://127.0.0.1:18443/
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF
cat > "$root/kiwi_dnf4.config" <<'EOF'
[main]
reposdir=/var/cache/kiwi/dnf/repos
cachedir=/var/cache/kiwi/dnf/cache
varsdir=/var/cache/kiwi/dnf/vars
plugins=0
EOF
cp /description/{koji-build-ca.pem,build-repo-ca.sh,post_bootstrap.sh,images.sh} "$root/image/"
for manager in dnf microdnf; do
    if chroot "$root" "$manager" --config=/kiwi_dnf4.config --releasever=9 \
        makecache > "$work/$manager-before.log" 2>&1; then
        echo "$manager unexpectedly trusted the test CA before the hook" >&2
        exit 1
    fi
    grep -Ei 'certificate|issuer' "$work/$manager-before.log"
done
chroot "$root" bash /image/post_bootstrap.sh
cmp "$bundle" /var/cache/kiwi/koji-build-ca.pem
cmp "$work/original.pem" "$root$bundle"
for manager in dnf microdnf; do
    chroot "$root" "$manager" --config=/kiwi_dnf4.config --releasever=9 clean all
    chroot "$root" "$manager" --config=/kiwi_dnf4.config --releasever=9 makecache
done

# Reproduce import_files and cache unmount before the packaging hook.
cp "$root/image/koji-build-ca.pem" "$root/image/build-repo-ca.sh" "$root/var/cache/kiwi/"
umount "$root/var/cache/kiwi"
unset 'mounts[${#mounts[@]}-1]'
# A leaked bundle must prevent packaging, rather than silently be published.
cp "$bundle" "$root/var/cache/kiwi/koji-build-ca.pem"
if chroot "$root" bash /image/images.sh; then
    echo 'Packaging hook accepted a leaked CA bundle' >&2
    exit 1
fi
rm "$root/var/cache/kiwi/koji-build-ca.pem"
chroot "$root" bash /image/images.sh
test ! -e "$root/image/koji-build-ca.pem"
test ! -e "$root/image/build-repo-ca.sh"
test ! -e "$root/var/cache/kiwi/koji-build-ca.pem"
cmp "$work/original.pem" "$root$bundle"
echo 'PASS: DNF and microdnf HTTPS trust, full bundle, unchanged image trust, cleanup'
