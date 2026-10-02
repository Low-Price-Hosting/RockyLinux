#!/bin/bash

set -euxo pipefail

#======================================
# Functions...
#--------------------------------------
test -f /.kconfig && . /.kconfig
test -f /.profile && . /.profile

#======================================
# Greeting...
#--------------------------------------
echo "Configure image: [$kiwi_iname]-[$kiwi_profiles]..."

################################################################################
# ALL OF OUR FUNCTIONS
function common_live_steps() {
  # this isn't needed in our testing, but we'll put it here just in case
  systemctl set-default graphical.target
  systemctl enable livesys.service livesys-late.service
  systemctl enable tmp.mount
  cat >> /etc/fstab << EOF
vartmp   /var/tmp    tmpfs   defaults   0  0
EOF
  rm -f /var/lib/rpm/__db*
  majorver=$(rpm --eval '%{rhel}')
  rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${majorver}"
  rm -f /var/lib/rpm/__db*
  /usr/bin/mandb
  rm -f /core*
  rm -f /boot/*-rescue*
}

function live_gnome_steps() {
  sed -i 's/^livesys_session=.*/livesys_session="gnome"/' /etc/sysconfig/livesys
}

function live_kde_steps() {
  sed -i 's/^livesys_session=.*/livesys_session="kde"/' /etc/sysconfig/livesys
  cat > /root/.gtkrc-2.0 << EOF
include "/usr/share/themes/Adwaita/gtk-2.0/gtkrc"
include "/etc/gtk-2.0/gtkrc"
gtk-theme-name="Adwaita"
EOF
  mkdir -p /root/.config/gtk-3.0
cat > /root/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-theme-name = Adwaita
EOF

  rm -f /usr/share/wallpapers/Fedora
  ln -s rocky-abstract-2 /usr/share/wallpapers/Fedora

  systemctl enable --force sddm.service

  cat > /etc/sddm.conf.d/theme.conf <<THEMEEOF
[Theme]
Current=breeze
THEMEEOF
}

function live_cinnamon_steps() {
  sed -i 's/^livesys_session=.*/livesys_session="cinnamon"/' /etc/sysconfig/livesys
  cat > /etc/sysconfig/desktop <<EOF
PREFERRED=/usr/bin/cinnamon-session
DISPLAYMANAGER=/usr/sbin/lightdm
EOF
  systemctl enable --force lightdm.service
}

function live_mate_steps() {
  sed -i 's/^livesys_session=.*/livesys_session="mate"/' /etc/sysconfig/livesys
  systemctl enable --force lightdm.service
}

function live_xfce_steps() {
  sed -i 's/^livesys_session=.*/livesys_session="xfce"/' /etc/sysconfig/livesys
  systemctl enable --force lightdm.service
  cat > /etc/sysconfig/desktop <<EOF
PREFERRED=/usr/bin/startxfce4
DISPLAYMANAGER=/usr/sbin/lightdm
EOF

    # set default background
  cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<XFCEEOF
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="color-style" type="int" value="0"/>
        <property name="image-style" type="int" value="5"/>
        <property name="last-image" type="string" value="/usr/share/backgrounds/rocky-default-9-abstract-2-day.png"/>
        <property name="last-single-image" type="string" value="/usr/share/backgrounds/rocky-default-9-abstract-2-day.png"/>
        <property name="image-path" type="string" value="/usr/share/backgrounds/rocky-default-9-abstract-2-day.png"/>
      </property>
    </property>
  </property>
</channel>
XFCEEOF
}

function epel_de_steps() {
  dnf config-manager --set-enabled crb
}

# live fixes if we need them
function live_fixes() {
  sed -i "s/org.fedoraproject.AnacondaInstaller/anaconda/" /usr/share/applications/liveinst.desktop
}

function common_cloud_steps() {
  # This can be done via systemctl set-default, but sometimes it doesn't work.
  # systemctl set-default multi-user.target
  rm -f /etc/systemd/system/default.target
  ln -s /lib/systemd/system/multi-user.target /etc/systemd/system/default.target

  # chrony should already be enabled, let's make sure
  systemctl enable chronyd
  # make a persistent journal
  mkdir -p /var/log/journal

  dnf -C -y remove linux-firmware avahi\*
  dnf -C -y remove firewalld --setopt="clean_requirements_on_remove=1"
  dnf -C -y remove langpacks-*
  sed -i '/^#NAutoVTs=.*/ a\
NAutoVTs=0' /etc/systemd/logind.conf
  truncate -s 0 /etc/resolv.conf
  if [ -f /etc/tuned/active_profile ]; then
    echo "virtual-guest" > /etc/tuned/active_profile
  fi
  rm -f /etc/udev/rules.d/70*
  ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules
  cat > /etc/sysconfig/network << EOF
NETWORKING=yes
NOZEROCONF=yes
EOF
  cat > /etc/hosts << EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

EOF

  echo "RUN_FIRSTBOOT=NO" > /etc/sysconfig/firstboot

  echo -e 'rocky\tALL=(ALL)\tNOPASSWD: ALL' >> /etc/sudoers
  sed -i '1i # Modified for cloud image' /etc/cloud/cloud.cfg
  sed -i 's/name: cloud-user/name: rocky/g' /etc/cloud/cloud.cfg
}

################################################################################
# Azure
function azure_cloud_steps() {
  echo 'azure' > /etc/dnf/vars/infra
  cat << EOF | tee -a /etc/NetworkManager/conf.d/dhcp-timeout.conf
# Configure dhcp timeout to 300s by default
[connection]
ipv4.dhcp-timeout=300
EOF
  systemctl enable waagent
  sed -i 's/Provisioning.UseCloudInit=n/Provisioning.UseCloudInit=y/g' /etc/waagent.conf
  sed -i 's/Provisioning.Enabled=y/Provisioning.Enabled=n/g' /etc/waagent.conf
  cat << EOF | tee -a /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules
# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"
EOF

  cat << EOF | tee -a /etc/udev/rules.d/98-hyperv-ptp.rules
## See: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/time-sync#check-for-ptp-clock-source
SUBSYSTEM=="ptp", ATTR{clock_name}=="hyperv", SYMLINK += "ptp_hyperv"
EOF

  cat << EOF | tee -a /etc/chrony.conf
# Setup hyperv PTP device as refclock
refclock PHC /dev/ptp_hyperv poll 3 dpoll -2 offset 0 stratum 2
EOF

  cat << EOF | tee -a /etc/modprobe.d/azure-blacklist.conf
blacklist amdgpu
blacklist nouveau
blacklist radeon
EOF

  cat << EOF | tee /etc/cloud/cloud.cfg.d/10-azure-kvp.cfg
# Enable logging to the Hyper-V kvp in Azure
reporting:
  logging:
    type: log
  telemetry:
    type: hyperv
EOF

  cat << EOF | tee -a /etc/dracut.conf.d/80-azure.conf
add_drivers+=" hv_vmbus hv_netvsc hv_storvsc "
EOF

  #dracut -f -v
}

################################################################################
# EC2
function ec2_cloud_steps() {
  echo 'ec2' > /etc/dnf/vars/infra
  cat  >> /etc/dhcp/dhclient.conf << EOF
timeout 300;
retry 60;
EOF

  if [ -f /boot/grub2/grub.conf ]; then
    sed -i -e 's/ rhgb quiet//' /boot/grub2/grub.conf
  fi
    sed -i -e 's/ rhgb quiet//' /etc/default/grub
  cat > /etc/modprobe.d/blacklist-nouveau.conf << EOL
blacklist nouveau
EOL

  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="dhcp"
TYPE="Ethernet"
USERCTL="no"
PEERDNS="yes"
IPV6INIT="no"
PERSISTENT_DHCLIENT="1"
EOF

  echo 'install_items+=" sgdisk "' > /etc/dracut.conf.d/sgdisk.conf
  echo 'add_drivers+=" xen-netfront xen-blkfront "' > /etc/dracut.conf.d/xen.conf
  #KERNEL_VERSION=$(rpm -q kernel --qf '%{V}-%{R}.%{arch}\n')
  #dracut -f /boot/initramfs-$KERNEL_VERSION.img $KERNEL_VERSION

  cat >> /etc/chrony.conf << EOF
# Amazon Time Sync Service
server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4
EOF
}

################################################################################
# Generic Cloud (genclo)
function genclo_cloud_steps() {
  echo 'genclo' > /etc/dnf/vars/infra
  cat  >> /etc/dhcp/dhclient.conf << EOF
timeout 300;
retry 60;
EOF

  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="dhcp"
BOOTPROTOV6="dhcp"
TYPE="Ethernet"
USERCTL="no"
PEERDNS="yes"
IPV6INIT="yes"
PERSISTENT_DHCLIENT="1"
EOF
}

################################################################################
# OCP
function ocp_cloud_steps() {
  cat  >> /etc/dhcp/dhclient.conf << EOF
timeout 300;
retry 60;
EOF

  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
ONBOOT="yes"
BOOTPROTO="dhcp"
TYPE="Ethernet"
USERCTL="no"
PEERDNS="yes"
IPV6INIT="no"
PERSISTENT_DHCLIENT="1"
EOF

  # OCI - Import repo GPG key
  cat <<EOF > /tmp/key
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
4QrtLe//99hXPcFVanIxgkdslnyYf4fjdbdlmNY=
=xpaH
-----END PGP PUBLIC KEY BLOCK-----
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
RgwnCPfIai7lLNx95bdwB8U2NpY11OXsoTLZAA==
=UWTf
-----END PGP PUBLIC KEY BLOCK-----
EOF

  rpm --import /tmp/key

  # Import EPEL Key
  cat <<EOF > /tmp/key
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGE3mOsBEACsU+XwJWDJVkItBaugXhXIIkb9oe+7aadELuVo0kBmc3HXt/Yp
CJW9hHEiGZ6z2jwgPqyJjZhCvcAWvgzKcvqE+9i0NItV1rzfxrBe2BtUtZmVcuE6
2b+SPfxQ2Hr8llaawRjt8BCFX/ZzM4/1Qk+EzlfTcEcpkMf6wdO7kD6ulBk/tbsW
DHX2lNcxszTf+XP9HXHWJlA2xBfP+Dk4gl4DnO2Y1xR0OSywE/QtvEbN5cY94ieu
n7CBy29AleMhmbnx9pw3NyxcFIAsEZHJoU4ZW9ulAJ/ogttSyAWeacW7eJGW31/Z
39cS+I4KXJgeGRI20RmpqfH0tuT+X5Da59YpjYxkbhSK3HYBVnNPhoJFUc2j5iKy
XLgkapu1xRnEJhw05kr4LCbud0NTvfecqSqa+59kuVc+zWmfTnGTYc0PXZ6Oa3rK
44UOmE6eAT5zd/ToleDO0VesN+EO7CXfRsm7HWGpABF5wNK3vIEF2uRr2VJMvgqS
9eNwhJyOzoca4xFSwCkc6dACGGkV+CqhufdFBhmcAsUotSxe3zmrBjqA0B/nxIvH
DVgOAMnVCe+Lmv8T0mFgqZSJdIUdKjnOLu/GRFhjDKIak4jeMBMTYpVnU+HhMHLq
uDiZkNEvEEGhBQmZuI8J55F/a6UURnxUwT3piyi3Pmr2IFD7ahBxPzOBCQARAQAB
tCdGZWRvcmEgKGVwZWw5KSA8ZXBlbEBmZWRvcmFwcm9qZWN0Lm9yZz6JAk4EEwEI
ADgWIQT/itE0RZcQbs6BO5GKOHK/MihGfAUCYTeY6wIbDwULCQgHAgYVCgkICwIE
FgIDAQIeAQIXgAAKCRCKOHK/MihGfFX/EACBPWv20+ttYu1A5WvtHJPzwbj0U4yF
3zTQpBglQ2UfkRpYdipTlT3Ih6j5h2VmgRPtINCc/ZE28adrWpBoeFIS2YAKOCLC
nZYtHl2nCoLq1U7FSttUGsZ/t8uGCBgnugTfnIYcmlP1jKKA6RJAclK89evDQX5n
R9ZD+Cq3CBMlttvSTCht0qQVlwycedH8iWyYgP/mF0W35BIn7NuuZwWhgR00n/VG
4nbKPOzTWbsP45awcmivdrS74P6mL84WfkghipdmcoyVb1B8ZP4Y/Ke0RXOnLhNe
CfrXXvuW+Pvg2RTfwRDtehGQPAgXbmLmz2ZkV69RGIr54HJv84NDbqZovRTMr7gL
9k3ciCzXCiYQgM8yAyGHV0KEhFSQ1HV7gMnt9UmxbxBE2pGU7vu3CwjYga5DpwU7
w5wu1TmM5KgZtZvuWOTDnqDLf0cKoIbW8FeeCOn24elcj32bnQDuF9DPey1mqcvT
/yEo/Ushyz6CVYxN8DGgcy2M9JOsnmjDx02h6qgWGWDuKgb9jZrvRedpAQCeemEd
fhEs6ihqVxRFl16HxC4EVijybhAL76SsM2nbtIqW1apBQJQpXWtQwwdvgTVpdEtE
r4ArVJYX5LrswnWEQMOelugUG6S3ZjMfcyOa/O0364iY73vyVgaYK+2XtT2usMux
VL469Kj5m13T6w==
=Mjs/
-----END PGP PUBLIC KEY BLOCK-----
EOF

  rpm --import /tmp/key
  # remove these for debugging
  if [ -f /boot/grub2/grub.conf ]; then
    sed -i -e 's/ rhgb quiet//' /boot/grub2/grub.conf
  fi
  sed -i -e 's/ rhgb quiet//' /etc/default/grub

  # enable resizing on copied AMIs
  echo 'install_items+=" sgdisk "' > /etc/dracut.conf.d/sgdisk.conf

  # OCI - Need iscsi as a dracut module
  echo 'add_dracutmodules+=" iscsi "' > /etc/dracut.conf.d/iscsi.conf

  # OCI - Virtio drivers
  echo 'add_drivers+=" virtio virtio_blk virtio_net virtio_pci virtio_ring virtio_scsi virtio_console "' > /etc/dracut.conf.d/virtio.conf

  # OCI - YOLO
  mkdir -p /usr/lib/dracut/modules.d/95oci
  OCIDRACUT="H4sIAGtFHmMAA+2WWW/bOBCA/Vr+illZzQXoluPUhgMURYrmpS02fevuGpJIWYQVUiWpJoHr/15S
crLZZBs3QA8U5QfYosQ5NUNSrRRBTfMAi6xoVXDOcVsT6ePg2YgXNBh8C0LNeDTqrpq7124cpfF4
nIzT8fhwEEaj+HA8gNE38b6FVqpMAAwE5+ohuW3zvyjtw/UnLMtr4lFZSOrlV00mpS+rR/rYUv84
StJBlIx10ZNREscD/SRNkwGE3yXjO/zm9R/+EeSUBbJCQ/AOPNANQCYgK1LXniwEbdQUKMOEKU9l
ufT6eUbrqRby8kzSwuNlKYmaQDo1JrQhcjkBJWdHIC9mKUg9TIEoKGlN1FVDZtobGr7NVFFB11nm
3YLikNU1v4A8ozXwVgEtQVUEullM5RKKjGkZQTJ8BTmBkrcMo6Eg5QTeiCxvFxMYJmESxWGYImRc
wYLo8i7gOMDkY8Dauob4eCeCT5/Ah1uN7+mhbmx0+vrs5M93s10kZo67Mp6Hec2L5WTtIB1Oby3n
vIYQBPa76P1+XcDODrwHj4DjCgf+nprYGSDQlFwA69KgDNy93ooERpR5uD8FzDs5w3utv+qEnz6d
HKwdmIHTudE2TdgFZ4qyltwodGk2mZBk3snNO0dfTlh7vc722sQ9bcftInCMmiCqFQyiG+lN2HPC
ipm7J5WYC9LUWUH+VXMC/fsrLp39TgtzRuAe3RQpKr5JcAJnS9o0lC3AveXD930HjnfiR4lDl/7y
XC5uqUkjT7CZdgJ13gSdHbP+FcHebSNOr3VJFYSopGgXfWX1S21ZmgV109c3rYCuwzgxe6oJ+/Ts
xdkpbPR5oyhn15l+leR/kuw13L6BdeFAEgwehd3gn7fP372a+QdusBK9ilSYmniq9RTc1eU0MBKB
HnwI11P9n6x3/ycP3QsXme4E56VeoNr4g9GZt/az9zbLdrac//29p7f3tnn8wb9h2/dfchjdOf/D
OIns+f8j2Jz/+iD/4V8ARUWK5d4+rNCTzRkTojVCmDSEYXl/gjJdqrruJ8zNvOJ8CY0gXqt3NTg6
0vufjg5T8YXvVkeb+dkv3GKxWCwWi8VisVgsFovFYrFYLBaLxWL5jnwGdMMrBgAoAAA="

  base64 -d <<<"$OCIDRACUT" | tar -xz

  OCICLOUDCFG="IyBPQ0kgY2xvdWQtaW5pdCBjb25maWd1cmF0aW9uCmRhdGFzb3VyY2VfbGlzdDogWydPcmFjbGUn
LCAnT3BlblN0YWNrJ10KZGF0YXNvdXJjZToKICBPcGVuU3RhY2s6CiAgICBtZXRhZGF0YV91cmxz
OiBbJ2h0dHA6Ly8xNjkuMjU0LjE2OS4yNTQnXQogICAgdGltZW91dDogMTAKICAgIG1heF93YWl0
OiAyMAoKIyBzd2FwIGZpbGUKc3dhcDoKICAgZmlsZW5hbWU6IC8uc3dhcGZpbGUKICAgc2l6ZTog
ImF1dG8iCgpjbG91ZF9pbml0X21vZHVsZXM6CiMgT0NJOiBkaXNrX3NldHVwIGlzIGRpc2FibGVk
CiMtIGRpc2tfc2V0dXAKIC0gbWlncmF0b3IKIC0gYm9vdGNtZAogLSB3cml0ZS1maWxlcwojIE9D
STogVGhlIGdyb3dwYXJ0IG1vZHVsZSBpcyBkaXNhYmxlZCBieSBkZWZhdWx0LiBUbyBlbmFibGUg
YXV0b21hdGljIGJvb3Qgdm9sdW1lIHJlc2l6aW5nLCB1bmNvbW1lbnQKIyB0aGUgYmVsb3cgZW50
cnkgZm9yICctIGdyb3dwYXJ0JyBhbmQgcmVib290LiBBbGwgdGhlIGRlcGVuZGVudCBwYWNrYWdl
cyBmb3IgdGhlIGdyb3dwYXJ0CiMgbW9kdWxlIHRvIHdvcmsgc3VjaCBhcyBjbG91ZC11dGlscy1n
cm93cGFydCBhbmQgZ2Rpc2sgYXJlIGFscmVhZHkgaW5jbHVkZWQgaW4gdGhlIGltYWdlLgojLSBn
cm93cGFydAogLSByZXNpemVmcwojIE9DSTogc2V0X2hvc3RuYW1lLCB1cGRhdGVfaG9zdG5hbWUs
IHVwZGF0ZV9ldGNfaG9zdHMgYXJlIGRpc2FibGVkCiMtIHNldF9ob3N0bmFtZQojLSB1cGRhdGVf
aG9zdG5hbWUKIy0gdXBkYXRlX2V0Y19ob3N0cwogLSByc3lzbG9nCiAtIHVzZXJzLWdyb3Vwcwog
LSBzc2gKCmNsb3VkX2NvbmZpZ19tb2R1bGVzOgogLSBtb3VudHMKIC0gbG9jYWxlCiAtIHNldC1w
YXNzd29yZHMKIyBPQ0k6IHJoX3N1YnNjcmlwdGlvbiBpcyBkaXNhYmxlZAojLSByaF9zdWJzY3Jp
cHRpb24KIC0geXVtLWFkZC1yZXBvCiAtIHBhY2thZ2UtdXBkYXRlLXVwZ3JhZGUtaW5zdGFsbAog
LSB0aW1lem9uZQogLSBudHAKIC0gcHVwcGV0CiAtIGNoZWYKIC0gc2FsdC1taW5pb24KIC0gbWNv
bGxlY3RpdmUKIC0gZGlzYWJsZS1lYzItbWV0YWRhdGEKIC0gcnVuY21kCgpjbG91ZF9maW5hbF9t
b2R1bGVzOgogLSByaWdodHNjYWxlX3VzZXJkYXRhCiAtIHNjcmlwdHMtcGVyLW9uY2UKIC0gc2Ny
aXB0cy1wZXItYm9vdAogLSBzY3JpcHRzLXBlci1pbnN0YW5jZQogLSBzY3JpcHRzLXVzZXIKIC0g
c3NoLWF1dGhrZXktZmluZ2VycHJpbnRzCiAtIGtleXMtdG8tY29uc29sZQogLSBwaG9uZS1ob21l
CiAtIGZpbmFsLW1lc3NhZ2UKIyBPQ0k6IHBvd2VyLXN0YXRlLWNoYW5nZSBpcyBkaXNhYmxlZAoj
LSBwb3dlci1zdGF0ZS1jaGFuZ2UKCg=="

  base64 -d <<<"$OCICLOUDCFG" >> /etc/cloud/cloud.cfg.d/99_oci.cfg

  # Remove system.devices because Oracle does things.
  rm -fv /etc/lvm/devices/system.devices

}

function cloud_cleanup_steps() {
  truncate -c -s 0 /var/log/dnf.log
  rm -rf /var/log/yum.log
  rm -rf /var/lib/yum/*
  rm -rf /root/install.log
  rm -rf /root/install.log.syslog
  rm -rf /root/anaconda-ks.cfg
  rm -rf /var/log/anaconda*

  rm -f /var/lib/systemd/random-seed

  touch /var/log/cron
  touch /var/log/boot.log
  mkdir -p /var/cache/yum

  # Azure Only
  if [[ "$kiwi_profiles" == *"Azure"* ]]; then
    rm -f /var/log/waagent.log
    cloud-init clean
    waagent -force -deprovision+user
  fi

  # Attempt to fix file permissions
  for x in $(rpm -qa); do rpm --setperms "${x}" ; done

  # Attempt to fix labeling
  /usr/sbin/fixfiles -R -a restore
}

function azure_cleanup_steps() {
  rm -f /var/log/waagent.log
  cloud-init clean
  waagent -force -deprovision+user
}

function common_container_steps() {
  /bin/date +%Y-%m-%d_%H:%M:%S > /etc/BUILDTIME
  echo 'container' > /etc/dnf/vars/infra
  LANG="en_US"
  echo "%_install_langs $LANG" > /etc/rpm/macros.image-language-conf
  echo 'LANG="C.UTF-8"' >  /etc/locale.conf
  releasever=$(rpm --eval '%{?rocky}')
  rpm --import "/etc/pki/rpm-gpg/RPM-GPG-KEY-Rocky-${releasever}"
  :> /etc/machine-id
  echo "# placeholder" > /etc/resolv.conf
  chmod 644 /etc/resolv.conf
  rm -rf /tmp/*
  printf "tsflags=nodocs\n" >>/etc/dnf/dnf.conf

  # rootfiles
  if [ -f /usr/share/rootfiles/.bashrc ] && [ ! -f /root/.bashrc ]; then
    cp /usr/share/rootfiles/.bashrc /root/.bashrc
  fi
  if [ -f /usr/share/rootfiles/.bash_logout ] && [ ! -f /root/.bash_logout ]; then
    cp /usr/share/rootfiles/.bash_logout /root/.bash_logout
  fi
  if [ -f /usr/share/rootfiles/.bash_profile ] && [ ! -f /root/.bash_profile ]; then
    cp /usr/share/rootfiles/.bash_profile /root/.bash_profile
  fi
  if [ -f /usr/share/rootfiles/.cshrc ] && [ ! -f /root/.cshrc ]; then
    cp /usr/share/rootfiles/.cshrc /root/.cshrc
  fi
  if [ -f /usr/share/rootfiles/.tcshrc ] && [ ! -f /root/.tcshrc ]; then
    cp /usr/share/rootfiles/.tcshrc /root/.tcshrc
  fi
}

function minimal_container_steps() {
  microdnf -y remove langpacks-en || true
  rm -fv /usr/share/gnupg/help*.txt
  rm /usr/lib/rpm/rpm.daily
  rm -rfv /usr/lib64/nss/unsupported-tools/
  rm -fv /usr/sbin/{glibc_post_upgrade.x86_64,sln}
  ln /usr/bin/ln usr/sbin/sln
  rm -rfv /var/lib/dnf
  rm -rfv /usr/share/icons/*
  rm -fv /usr/bin/pinky
  rm -rfv /usr/lib/systemd
}

function toolbox_container_steps() {
  rm -f /etc/rpm/macros.image-language-conf
  sed -i '/tsflags=nodocs/d' /etc/dnf/dnf.conf
}

################################################################################
# Vagrant
function common_vagrant_steps() {
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  echo "/swapfile none swap defaults 0 0" >> /etc/fstab

  cat > /etc/sudoers.d/vagrant << EOF
Defaults:vagrant !requiretty
%vagrant ALL=(ALL) NOPASSWD: ALL
EOF
  chmod 0440 /etc/sudoers.d/vagrant
  # This may have to be changed for 10
  sed -i 's/^\(PasswordAuthentication\) yes$/\1 no/' /etc/ssh/sshd_config
  sed -i 's/^#\(UseDNS\) yes$/\r\1 no/' /etc/ssh/sshd_config

  cat >>/etc/sysconfig/sshd <<EOF
# Decrease connection time by preventing reverse DNS lookups
# (see https://lists.centos.org/pipermail/centos-devel/2016-July/014981.html)
OPTIONS="-u0"
EOF

  # Setup insecure key by default
  mkdir -m 0700 -p /home/vagrant/.ssh
  echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" >> /home/vagrant/.ssh/authorized_keys
  chmod 600 /home/vagrant/.ssh/authorized_keys
  chown -R vagrant:vagrant /home/vagrant/.ssh

  echo 'vag' > /etc/yum/vars/infra
  echo blacklist floppy > /etc/modprobe.d/nofloppy.conf
  pushd /etc/dracut.conf.d
  # Enable VMware PVSCSI support for VMware Fusion guests.
  echo 'add_drivers+=" vmw_pvscsi "' > vmware-fusion-drivers.conf
  echo 'add_drivers+=" hv_netvsc hv_storvsc hv_utils hv_vmbus hid-hyperv "' > hyperv-drivers.conf
  # There's no floppy controller, but probing for it generates timeouts
  echo 'omit_drivers+=" floppy "' > nofloppy.conf
  popd
  #echo "Regenerating kernel"
  #KERNEL_VERSION=$(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n')
  #dracut -f -v
  rm -rf /etc/ssh/ssh_host_*

  # Might not be needed for 10
  ex -s /etc/pam.d/su <<'EOF'
/^account\s\+sufficient\s\+pam_succeed_if.so uid = 0 use_uid quiet$/
:append
account   [success=1 default=ignore] \\
        pam_succeed_if.so user = vagrant use_uid quiet
account   required  pam_succeed_if.so user notin root:vagrant
.
:update
:quit
EOF
}

function vbox_vagrant_steps() {
  # legacy stuff, we won't have this for 10
  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
PERSISTENT_DHCLIENT="yes"
EOF

  # Install VBoxGuestAdditions for installed kernel.
  # https://git.resf.org/sig_kernel/meta/issues/13
  #kver=$(rpm -q --queryformat="%{VERSION}-%{RELEASE}.%{ARCH}" kernel)
  #echo "stg/rocky" > /etc/dnf/vars/contentdir
  #sed -i 's/^#baseurl/baseurl/g;s/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/rocky*repo
  #dnf -y install kernel-headers-$kver kernel-devel gcc make perl elfutils-libelf-devel
  #sed -i 's/^baseurl/#baseurl/g;s/^#mirrorlist/mirrorlist/g' /etc/yum.repos.d/rocky*repo
  #echo "pub/rocky" > /etc/dnf/vars/contentdir
  #curl -L -o /tmp/vboxadditions.iso https://download.virtualbox.org/virtualbox/7.0.16/VBoxGuestAdditions_7.0.16.iso
  #mkdir -p /media/VBoxGuestAdditions
  #mount -o loop,ro /tmp/vboxadditions.iso /media/VBoxGuestAdditions
  #mkdir -p /tmp/VBoxGuestAdditions
  #sh /media/VBoxGuestAdditions/VBoxLinuxAdditions.run --nox11 --noexec --keep --target /tmp/VBoxGuestAdditions
  #pushd /tmp/VBoxGuestAdditions
  #./install.sh
  #/sbin/rcvboxadd quicksetup all
  #popd
  #ls "/lib/modules/${kver}/misc/"
  #modinfo "/lib/modules/${kver}/misc/vboxsf.ko"
  #rm -rf /tmp/VBoxGuestAdditions
  #umount /media/VBoxGuestAdditions
  #rm -f /tmp/vboxadditions.iso
  #rmdir /media/VBoxGuestAdditions
  #dnf -y remove kernel-devel gcc make perl elfutils-libelf-devel
}

function libvirt_vagrant_steps() {
  # legacy stuff, we won't have this for 10
  cat > /etc/sysconfig/network-scripts/ifcfg-eth0 << EOF
DEVICE="eth0"
BOOTPROTO="dhcp"
ONBOOT="yes"
TYPE="Ethernet"
PERSISTENT_DHCLIENT="yes"
EOF
}

################################################################################
# SBC
function common_sbc_steps() {
  :> /etc/machine-id
  rm -f /etc/sysconfig/network-scripts/ifcfg-link
  rm -f /etc/ssh/*_key*
  dnf clean all
  chown -R sssd:sssd /var/lib/sss/{db,pipes,mc,pubconf,gpo_cache}
  cat > /etc/sysconfig/cpupower << EOF
CPUPOWER_START_OPTS="frequency-set -g ondemand"
CPUPOWER_STOP_OPTS="frequency-set -g ondemand"
EOF
  cat >> /boot/efi/config.txt << EOF2

[pi5]
dtoverlay=vc4-kms-v3d
EOF2
}

function raspberrypi_sbc_steps() {
  mkdir -p /boot/efi
  cd /lib/firmware/brcm
  xz -d -k brcmfmac43430-sdio.raspberrypi,3-model-b.txt.xz
  cat > /boot/efi/cmdline.txt << EOF
console=ttyAMA0,115200 console=tty1 root=LABEL=RPIROOT rootfstype=ext4 rootwait
EOF

}
function genericarm_sbc_steps() {
  mkdir -p /boot/efi/EFI/BOOT
  if [ -d /boot/efi/EFI/rocky/ ] && [ -f /boot/efi/EFI/rocky/grubaa64.efi ];then
    for j in grub.cfg grubenv;do
      if [ -f "/boot/grub2/${j}" ]; then
        mv -f /boot/grub2/${j} /boot/efi/EFI/rocky/
        ln -s ../efi/EFI/rocky/${j} /boot/grub2/${j}
      fi
    done
    cp -f /boot/efi/EFI/rocky/grubaa64.efi /boot/efi/EFI/BOOT/BOOTAA64.EFI
  fi

  if [ -f /usr/share/uboot/rpi_3/u-boot.bin ]; then
    cp -f /usr/share/uboot/rpi_3/u-boot.bin /boot/efi/rpi3-u-boot.bin
  fi
  if [ -f /usr/share/uboot/rpi_4/u-boot.bin ]; then
    cp -f /usr/share/uboot/rpi_4/u-boot.bin /boot/efi/rpi4-u-boot.bin
  fi
  if [ -f /usr/share/uboot/rpi_arm64/u-boot.bin ]; then
    cp -f /usr/share/uboot/rpi_arm64/u-boot.bin /boot/efi/rpi-u-boot.bin
  fi

  rpm -e dracut-config-generic
  if [ -x /lib/kernel/install.d/10-devicetree.install ]; then
    /lib/kernel/install.d/10-devicetree.install remove
  fi

  cat << EOF > /etc/sysconfig/kernel
# Written by image installer
# UPDATEDEFAULT specifies if new-kernel-pkg should make new kernels the default
UPDATEDEFAULT=yes

# DEFAULTKERNEL specifies the default kernel package type
DEFAULTKERNEL=kernel-core
EOF
chmod 644 /etc/sysconfig/kernel

### Write grub defaults, turn off OS probing as it is always wrong for image creation
cat << EOF > /etc/default/grub
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_RECOVERY="true"
GRUB_DISABLE_OS_PROBER="true"
GRUB_ENABLE_BLSCFG="false"
EOF
  chmod 644 /etc/default/grub
  rm -f /boot/dtb

  cat >/usr/local/bin/rootfs-expand << EOF
#!/bin/bash
clear
program=\$(basename "\$0")
logfile="/var/log/\$program.log"

# Function to log messages
log() {
    echo "\$(date +'%Y-%m-%d %H:%M:%S') - \$1" | tee -a "\$logfile"
}

# Function to log variables for debugging
log_variables() {
    echo "--- Debugging Variables ---" >> "\$logfile"
    echo "program: \$program" >> "\$logfile"
    echo "logfile: \$logfile" >> "\$logfile"
    echo "part: \$part" >> "\$logfile"
    echo "dev: \$dev" >> "\$logfile"
    echo "num: \$num" >> "\$logfile"
    echo "last_part_num: \$last_part_num" >> "\$logfile"
    echo "--------------------------" >> "\$logfile"
}

# Check if the script is run as root
if [[ \$(id -u) -ne 0 ]]; then
    log "Error: This script must be run as root (UID 0)."
    exit 1
fi

log "Starting \$program"

for cmd in growpart resize2fs; do
    if ! command -v \$cmd &> /dev/null; then
        echo "The command '\$cmd' is not installed. Please install the necessary package."
        exit 1
    fi
done

# Detect root filesystem partition
part=\$(findmnt / -o source -n)
if [ -z "\$part" ]; then
    log "Error detecting root filesystem. Exiting."
    exit 1
fi

dev="/dev/\$(lsblk -no pkname "\$part")"
num=\$(echo "\$part" | grep -o "[[:digit:]]*\$")

last_part_num=\$(parted "\$dev" -ms unit s p | tail -n 1 | cut -f 1 -d:)
if [[ "\$last_part_num" -ne "\$num" ]]; then
    log "Error: \$part is not the last partition. Unable to expand."
    exit 2
fi

# Log all variables for debugging
log_variables

# Extend partition
log "Extending partition \$num on device \$dev to maximum size..."
growpart "\$dev" "\$num" 2>&1 | tee -a "\$logfile" || { log "Error: growpart failed."; exit 3; }

# Resize filesystem
log "Resizing filesystem on \$partition..."
resize2fs "\$part" 2>&1 | tee -a "\$logfile" || { log "Error: resize2fs failed."; exit 4; }

log "Done."
df -h | grep "\$part" | tee -a "\$logfile"
EOF
  chmod +x /usr/local/bin/rootfs-expand
}

#
################################################################################

################################################################################
# WSL
function common_wsl_steps() {
  echo 'LC_MESSAGES=en_US.UTF-8' >>  /etc/locale.conf
}

#
################################################################################

cat /dev/null > /etc/machine-id

# Gets around grub-bls issue
echo "GRUB_DEFAULT=saved" >> /etc/default/grub

# All cloud and live
if [[ "$kiwi_profiles" == *"Cloud"* ]] || [[ "$kiwi_profiles" == *"Live"* ]] || [[ "$kiwi_profiles" == *"WSL"* ]]; then
  passwd -d root
  passwd -l root
fi

################################################################################
# Just about all the cloud images should do these things.
if [[ "$kiwi_profiles" == *"Cloud"* ]]; then
  common_cloud_steps
fi

################################################################################
# Azure specific settings
if [[ "$kiwi_profiles" == *"Azure"* ]]; then
  azure_cloud_steps
fi

################################################################################
# EC2 specific settings
if [[ "$kiwi_profiles" == *"EC2"* ]]; then
  ec2_cloud_steps
fi

################################################################################
# GenClo specific settings
if [[ "$kiwi_profiles" == *"GenericCloud"* ]]; then
  genclo_cloud_steps
fi

################################################################################
# OCP specific settings
if [[ "$kiwi_profiles" == *"OCP"* ]]; then
  ocp_cloud_steps
fi

# cloud clean up
if [[ "$kiwi_profiles" == *"Cloud"* ]]; then
  echo "cleanup time"
  cloud_cleanup_steps

  # Azure Only
  if [[ "$kiwi_profiles" == *"Azure"* ]]; then
    azure_cleanup_steps
  fi

  rm -f ~/.bash_history
  export HISTSIZE=0
fi

# Live Images Only
if [[ "$kiwi_profiles" == *"Live"* ]]; then
  common_live_steps
  if [[ "$kiwi_profiles" == *"Workstation"* ]]; then
    live_gnome_steps
  fi
  if [[ "$kiwi_profiles" == *"KDE"* ]]; then
    live_kde_steps
    epel_de_steps
  fi
  if [[ "$kiwi_profiles" == *"Cinnamon"* ]]; then
    live_cinnamon_steps
    epel_de_steps
  fi
  if [[ "$kiwi_profiles" == *"MATE"* ]]; then
    live_mate_steps
    epel_de_steps
  fi
  if [[ "$kiwi_profiles" == *"XFCE"* ]]; then
    live_xfce_steps
    epel_de_steps
  fi
fi

# Containers only
if [[ "$kiwi_profiles" == *"Container"* ]]; then
  common_container_steps
  if [[ "$kiwi_profiles" == *"Container-Minimal"* ]]; then
    minimal_container_steps
  fi
  if [[ "$kiwi_profiles" == *"Container-Toolbox"* ]]; then
    toolbox_container_steps
  fi
fi

# Vagrant only
if [[ "$kiwi_profiles" == *"Vagrant"* ]]; then
  common_vagrant_steps
  if [[ "$kiwi_profiles" == *"Vagrant-Libvirt"* ]]; then
    libvirt_vagrant_steps
  fi
  if [[ "$kiwi_profiles" == *"Vagrant-Vbox"* ]]; then
    vbox_vagrant_steps
  fi
fi

# SBC Only
if [[ "$kiwi_profiles" == *"SBC"* ]]; then
  common_sbc_steps
  if [[ "$kiwi_profiles" == *"SBC-RaspberryPi"* ]]; then
    raspberrypi_sbc_steps
  fi
  if [[ "$kiwi_profiles" == *"SBC-GenericArm"* ]]; then
    genericarm_sbc_steps
  fi
fi

# WSL Only

if [[ "$kiwi_profiles" == *"WSL"* ]]; then
  common_wsl_steps
fi
