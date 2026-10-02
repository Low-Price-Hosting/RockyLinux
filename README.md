## rocky-kiwi-descriptions

Kiwi descriptions for Rocky Linux 9.

`config.xml` is a symlink to `rocky.xml`. this way the symlink can just be
changed to deal with live images (as kiwi doesn't seem to support using the
--kiwi-file option for iso).

### What can I build?

At the time of this writing, you can create cloud images, live images, and
containers. You can run any of the scripts to do so:

* cloud-build.sh
* container-build.sh
* live-build.sh

### Can't you use the same config.xml? Why are you symlinking?

Yes and the reason why we're symlinking is that "name" and "displayname" are
not flexible. They are only set/read at the very top level `<image>` (at least
from testing at the time of this writing). As our images and volume names (at
least for live images) have a very specific format, and we want it to be easy
to rename them, we did it this way.

Cloud, container, vagrant images can all use the first config, likely just fine.
The live images were the problematic ones, thus, symlinks with a default to the
`rocky.xml` config.

### Build-only repository trust

Rocky 9 builds may download packages from internal HTTPS servers, including
`dl.rockylinux.org` and `kojidev.rockylinux.org`. These servers require the
internal CA already trusted by the buildroot.

`koji-build-ca.pem` is a symlink to the buildroot's extracted CA bundle.
Every description includes `components/bootstrap.xml`, which imports the
bundle and `build-repo-ca.sh` for all profiles. The helper uses bash and
coreutils so minimal containers do not need Python or additional packages.
`post_bootstrap.sh` copies the full bundle, including public and internal
CAs, into Kiwi's mounted shared cache and sets `sslcacert` globally in
`/kiwi_dnf4.config`. All repositories inherit this trust unless they explicitly
override it. TLS verification stays enabled. No certificate is installed in
the image's trust store, and its normal DNF configuration is untouched.

This uses the Kiwi 11.0.2 DNF4 configuration shared by DNF and microdnf,
and its hook lifecycle. The helper refuses to run without the shared cache
mount or with an unexpected repository directory. After Kiwi unmounts the
cache, `images.sh` removes the imported
files and refuses to package an image with a leftover cached CA bundle.
No Pungi or Koji plugin changes are needed.

Run the focused tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

The HTTPS and cleanup integration test must run in a disposable privileged
container: it mounts an image root and changes that container's CA bundle.
From this checkout, run:

```sh
podman run --rm --privileged -v "$PWD:/description:ro" \
  --entrypoint /bin/bash docker.io/rockylinux/rockylinux:9 -c \
  'dnf -y install microdnf openssl createrepo_c diffutils && bash /description/tests/test_build_repo_ca_lifecycle.sh'
```

### I found an issue...

Please fork and make a PR! We're still learning how this tool works ourselves.

### How to try it out

You can run this on a running system, in a mock root, or a podman container. In
fact, most builds may fail in mock due to loop devices being unusable.

**Note**: SELinux is recommended to be permissive if the images do not come out
correctly.

**Note**: There may be cases where a build will fail in mock. If this is the
case, you may need to use `--isolation=simple` or forego the use of mock entirely.

**Note**: If you receive an error about loop devices while running in mock, run
this on the host instead.

#### Live Image Example on Rocky Linux 9 without using mock

```
# Use SIG/Core
% dnf install rocky-release-core
% dnf install kiwi-cli git \
  dracut-kiwi-live \
  kiwi-systemdeps-{bootloaders,containers,core,disk-images,filesystems,image-validation,iso-media}

# optional
% sudo setenforce 0

# clone the repo here
% git clone https://git.resf.org/sig_core/rocky-kiwi-descriptions -b r9
% cd rocky-kiwi-descriptions
% ln -sf configs/rocky-live-xfce.xml config.xml
% kiwi-ng --debug --type="iso" \
  --profile="XFCE-Live" \
  --color-output system \
  build \
  --description="./" \
  --target-dir /builddir/lmc
```

If you wish to use EPEL instead...

```
% dnf install epel-release -y
% crb enable
% dnf install kiwi-cli git \
  dracut-kiwi-live \
  kiwi-systemdeps-{bootloaders,containers,core,disk-images,filesystems,image-validation,iso-media} \
  distribution-gpg-keys

% sudo setenforce 0
% git clone https://git.resf.org/sig_core/rocky-kiwi-descriptions -b r9
% cd rocky-kiwi-descriptions
% ln -sf configs/rocky-live-xfce.xml config.xml
% kiwi-ng --debug --type="iso" \
  --profile="XFCE-Live" \
  --color-output system \
  build \
  --description="./" \
  --target-dir /builddir/lmc
```

#### Live Image Example (EPEL) using mock

The below makes an XFCE live image using SIG/Core packages.

```
# Use SIG/Core
% git clone https://git.resf.org/sig_core/mock-rocky-configs
% bash deploy.sh
% mock -r rl-9-x86_64-core-infra --init
% mock -r rl-9-x86_64-core-infra --install kiwi-cli git \
  dracut-kiwi-live \
  kiwi-systemdeps-{bootloaders,containers,core,disk-images,filesystems,image-validation,iso-media} \
  epel-release \
  rocky-release-core

% sudo setenforce 0
% mock -r rl-9-x86_64-core-infra --shell --enable-network
% git clone https://git.resf.org/sig_core/rocky-kiwi-descriptions -b r9
% cd rocky-kiwi-descriptions
% ln -sf configs/rocky-live-xfce.xml config.xml
% kiwi-ng --debug --type="iso" \
  --profile="XFCE-Live" \
  --kiwi-file="rocky-live-epel.xml" \
  --color-output system \
  build \
  --description="./" \
  --target-dir /builddir/lmc
```

The below uses EPEL instead if you do not wish to use SIG/Core.

```
# Use EPEL
% mock -r rocky+epel-9-x86_64 --init
% mock -r rocky+epel-9-x86_64 --install kiwi-cli git \
  dracut-kiwi-live \
  kiwi-systemdeps-{bootloaders,containers,core,disk-images,filesystems,image-validation,iso-media} \
  distribution-gpg-keys \
  epel-release

% sudo setenforce 0
% mock -r rocky+epel-9-x86_64 --shell --enable-network
% git clone https://git.resf.org/sig_core/rocky-kiwi-descriptions -b r9
% cd rocky-kiwi-descriptions
% ln -sf configs/rocky-live-xfce.xml config.xml
% kiwi-ng --debug --type="iso" \
  --profile="XFCE-Live" \
  --kiwi-file="rocky-live-epel.xml" \
  --color-output system \
  build \
  --description="./" \
  --target-dir /builddir/lmc
```

On the other hand, you can run the live-build.sh script after setting up your
mock environment.

```
% bash live-build.sh --live-image XFCE --output-dir /builddir/xfce
```

