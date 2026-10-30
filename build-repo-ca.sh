#!/bin/bash
set -euo pipefail

# The optional root is for isolated tests; Kiwi runs this inside the image.
root=${1:-/}
root=${root%/}
mounted=false
# stat-based mount checks miss bind mounts on the same filesystem.
if [[ -r "$root/proc/self/mountinfo" ]]; then
    while read -r id parent device source target rest; do
        if [[ $target == /var/cache/kiwi ]]; then
            mounted=true
            break
        fi
    done < "$root/proc/self/mountinfo"
fi
if ! "$mounted"; then
    echo 'Kiwi shared cache must be mounted before configuring build trust' >&2
    exit 1
fi

# DNF and microdnf share this Kiwi-generated configuration. Use only bash
# and coreutils: minimal containers have neither Python nor necessarily awk.
config=$root/kiwi_dnf4.config
section=
reposdir=
content=
while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*\[([^]]+)\][[:space:]]*$ ]]; then
        section=${BASH_REMATCH[1]}
        content+="$line"$'\n'
        if [[ $section == main ]]; then
            content+=$'sslcacert = /var/cache/kiwi/koji-build-ca.pem\nsslverify = 1\n'
        fi
        continue
    fi
    if [[ $section == main ]]; then
        if [[ $line =~ ^[[:space:]]*reposdir[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
            reposdir=${BASH_REMATCH[1]}
        fi
        if [[ $line =~ ^[[:space:]]*(sslcacert|sslverify)[[:space:]]*= ]]; then
            continue
        fi
    fi
    content+="$line"$'\n'
done < "$config"
if [[ $reposdir != /var/cache/kiwi/dnf/repos ]]; then
    echo "Unexpected Kiwi repository directory: $reposdir" >&2
    exit 1
fi

# Copy the full public and internal bundle without changing image trust.
cp "$root/image/koji-build-ca.pem" "$root/var/cache/kiwi/koji-build-ca.pem"
printf '%s' "$content" > "$config"
echo 'Using full buildroot CA bundle for temporary DNF configuration'
