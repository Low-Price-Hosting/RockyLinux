#!/bin/bash
# helps build a quick wsl image. that way a user doesn't have to use emapandas
# nor some other method. mock is probably not necessary, but it's up to you.
# label@resf.org

YELLOW=$(tput setaf 3)
NORMAL=$(tput sgr0)
SCRNAME="$(basename "$0")"
SCRDIR="$(dirname "${BASH_SOURCE[0]}")"

set -o errexit
set -o pipefail

export __usage
__usage="
usage: $SCRNAME [OPTIONS]

Options:
  -o, --output-dir  DIR
  -c, --wsl-image   NAME #
  -p, --peridot     ID   # optional. will use peridot repos.
  -d, --debug            # optional

"

OPTS=$(getopt -a -n wsl-build -o c:,o:,p:,d,h \
  -l wsl-image:,output-dir:,peridot:,debug,help -- "$@")

function is_in_path() {
  builtin type -P "${1}" &> /dev/null
}

function usage() {
  echo "$__usage"
}

eval set -- "$OPTS"
while :; do
  case "$1" in
    -c | --wsl-image)   WSL="$2"        ; shift 2 ;;
    -o | --output-dir)  OUTPUTDIR="$2"  ; shift 2 ;;
    -p | --peridot)     PERIDOTID="$2"  ; shift 2 ;;
    -d | --debug)       DEBUG="--debug" ; shift   ;;
    -h | --help)        usage                     ;;
    --) shift ; break ;;
  esac
done

if [ -z "$WSL" ] || [ -z "$OUTPUTDIR" ]; then
  echo "Options are not set properly."
  usage
  exit 12
fi

if [ -e "/sys/fs/selinux/enforce" ]; then
  enforce_check="$(cat /sys/fs/selinux/enforce)"
  if [ "$enforce_check" -eq "1" ]; then
    printf "%sWARNING:%s Running with selinux enforcing may cause issues with the final image.\n" "${YELLOW}" "${NORMAL}"
    printf "Proceed at your own risk.\n"
  fi
fi

set +e
is_in_path kiwi-ng
ret_val=$?
set -e

if [ "$ret_val" -ne "0" ]; then
  echo "kiwi-ng not found. kiwi packages are likely not installed on this system."
  exit 32
fi

function switch_repo_to_peridot() {
  ID="$1"
  # https://yumrepofs.build.resf.org/v1/projects/${ID}/repo/
  pushd repositories || { echo "not found"; exit 1; }
  sed -i "s;ZZ_INTERNAL_BaseOS_REPO_URL_ZZ;https://yumrepofs.build.resf.org/v1/projects/${ID}/repo/BaseOS/\$basearch;g" core-peridot.xml
  sed -i "s;ZZ_INTERNAL_AppStream_REPO_URL_ZZ;https://yumrepofs.build.resf.org/v1/projects/${ID}/repo/AppStream/\$basearch;g" core-peridot.xml
  sed -i "s;ZZ_INTERNAL_CRB_REPO_URL_ZZ;https://yumrepofs.build.resf.org/v1/projects/${ID}/repo/CRB/\$basearch;g" core-peridot.xml
  sed -i "s;ZZ_INTERNAL_extras_REPO_URL_ZZ;https://yumrepofs.build.resf.org/v1/projects/${ID}/repo/extras/\$basearch;g" core-peridot.xml
  rm core.xml
  ln -sf core-peridot.xml core.xml
  popd
}

function main() {
  /bin/rm config.xml
  if [ ! -f "rocky-wsl.xml" ]; then
    echo "${WSL} was not found. Is it supported?"
    exit 42
  fi

  if [ -n "$PERIDOTID" ]; then
    switch_repo_to_peridot "${PERIDOTID}"
  fi

  # shellcheck disable=SC2086
  kiwi-ng $DEBUG --profile="WSL-$WSL" --kiwi-file="rocky-wsl.xml" \
    --color-output system build --description="$SCRDIR" --target-dir "$OUTPUTDIR"
}

main
