#!/usr/bin/bash
# Turns the Stiloria image into the live system on the installer USB stick
# (see Containerfile): it boots into Plasma, and Anaconda installs
# $INSTALL_IMAGE from the copy on the stick, then tracks it signed
# (stiloria.ks). Bazzite builds its own ISOs the same way, with Titanoboa
# (github.com/ublue-os/bazzite, installer/); this keeps what a PC install
# needs from it and leaves out its Steam Deck, GNOME and support dialogs.
set -euxo pipefail

INSTALL_IMAGE=${INSTALL_IMAGE:?}
case $INSTALL_IMAGE in
    ghcr.io/mslanden/stiloria:*) label=Stiloria name=Stiloria ;;
    ghcr.io/mslanden/stiloria-nvidia:*) label=Stiloria-NVIDIA name="Stiloria for NVIDIA" ;;
    *)
        echo "Not a Stiloria image: $INSTALL_IMAGE" >&2
        exit 1
        ;;
esac

# The Anaconda profile (system_files/etc/anaconda/profile.d) matches this ID.
grep -qx ID=bazzite /usr/lib/os-release
# stiloria.ks enrolls this key for Bazzite's kernel with mokutil.
test -f /etc/pki/akmods/certs/akmods-ublue.der
command -v mokutil

# /root links to /var/roothome, which only exists once booted.
mkdir -p "$(realpath /root)"

### The edition to install. This runs inside Stiloria, whose policy.json takes
# ghcr.io/mslanden/stiloria(-nvidia) only when signed with Stiloria's key, so
# the pull fails rather than put an unsigned image on the stick. The workflow
# passes the digest it verified, so the stick gets exactly that build.
if [[ -n ${INSTALL_DIGEST:-} ]]; then
    podman pull "${INSTALL_IMAGE%:*}@$INSTALL_DIGEST"
    podman tag "${INSTALL_IMAGE%:*}@$INSTALL_DIGEST" "$INSTALL_IMAGE"
else
    podman pull "$INSTALL_IMAGE"
fi

### Bazzite's apps (installer/flatpaks), copied to the new system by stiloria.ks
# flatpak's bwrap writes /proc/sys/user/max_user_namespaces, read-only here.
mount -o remount,rw /proc/sys
curl --retry 3 -fLo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo
grep -v '^#' /src/flatpaks | xargs flatpak install -y --noninteractive

### Fedora's kernel, signed with Fedora's key, so the stick starts with Secure
# Boot on. Bazzite's kernel is signed with Universal Blue's key, which the
# installed system enrolls (stiloria.ks).
kernel_pkgs=(kernel kernel-core kernel-devel kernel-devel-matched kernel-modules kernel-modules-core kernel-modules-extra)
dnf -y versionlock delete "${kernel_pkgs[@]}"
dnf -y --setopt=protect_running_kernel=False remove "${kernel_pkgs[@]}"
rm -rf /usr/lib/modules/*
dnf -y --repo=fedora,updates --setopt=tsflags=noscripts install kernel kernel-core
kernel=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
test "$(wc -l <<< "$kernel")" = 1
depmod "$kernel"
# Firmware for nouveau, so NVIDIA cards (the RTX 50 series too) show a picture.
dnf -y install nvidia-gpu-firmware

### Booting from the stick: an initramfs that finds the ISO's squashfs, and
# livesys, which logs into Plasma as "liveuser" with the installer on the
# desktop and in Plasma Welcome.
dnf -y install dracut-live livesys-scripts
DRACUT_NO_XATTR=1 dracut --force --zstd --reproducible --no-hostonly \
    --add "dmsquash-live dmsquash-live-autooverlay" \
    "/usr/lib/modules/$kernel/initramfs.img" "$kernel"
sed -i 's/^livesys_session=.*/livesys_session=kde/' /etc/sysconfig/livesys
grep -qx livesys_session=kde /etc/sysconfig/livesys
systemctl enable livesys.service livesys-late.service

### Anaconda and its web interface, which runs in Firefox
# Bazzite pins some package versions that the installer's dependencies move.
dnf -y versionlock clear
dnf -y install --enable-repo=fedora-cisco-openh264 --allowerasing \
    anaconda-live firefox libblockdev-btrfs libblockdev-lvm libblockdev-dm yad
mkdir -p /var/lib/rpm-state
# Not cp -a: the files belong to root, not to whoever checked out the repo.
cp -rv /src/system_files/. /
sed "s|@INSTALL_IMAGE@|$INSTALL_IMAGE|g" /src/stiloria.ks >> /usr/share/anaconda/interactive-defaults.ks
grep -q "^ostreecontainer --url=$INSTALL_IMAGE " /usr/share/anaconda/interactive-defaults.ks
# The installer takes its title from here ("Stiloria installation") and its
# welcome from os-release's NAME ("Let's install Stiloria now"), which the
# installed system keeps as Bazzite's.
echo "Stiloria release $(rpm -E %fedora)" > /etc/system-release
sed -i 's/^NAME=.*/NAME="Stiloria"/' /usr/lib/os-release
grep -qx 'NAME="Stiloria"' /usr/lib/os-release
# ostree needs room in /var/tmp; the apps on the stick stay as installed.
rm -rf /var/tmp
mkdir /var/tmp
systemctl enable var-tmp.mount var-lib-flatpak.mount

### The live session is for installing. Updates, hardware setup, app installs
# and Steam belong to the installed system: Stiloria's services, and
# Bazzite's where it still has them.
systemctl disable stiloria-flatpak-manager.service stiloria-signed-tracking.service
for unit in rpm-ostreed-automatic.timer rpm-ostree-countme.service uupd.timer \
    bootloader-update.service bazzite-hardware-setup.service brew-setup.service \
    bazzite-flatpak-manager.service; do
    if [[ -n $(systemctl list-unit-files --no-legend "$unit") ]]; then
        systemctl disable "$unit"
    fi
done
# At login the installer opens (system_files/etc/xdg/autostart), instead of
# Steam and Bazzite's portal for setting up an installed system.
rm -f /etc/skel/.config/autostart/steam.desktop /etc/skel/.config/autostart/bazzite-portal.desktop

### The stick's bootloader, laid out as on Fedora's own ISOs: shim
# (EFI/BOOT/BOOTX64.EFI) starts GRUB's CD build as EFI/BOOT/grubx64.efi, which
# reads the grub.cfg Titanoboa writes next to it. shim's fallback (fbx64.efi)
# is left out: it would add a boot entry for the stick to the firmware.
dnf -y install grub2-efi-x64-cdboot
mkdir -p /boot/efi
cp -av /usr/lib/efi/*/*/EFI /boot/efi/
cp -v /boot/efi/EFI/fedora/gcdx64.efi /boot/efi/EFI/BOOT/grubx64.efi
rm -v /boot/efi/EFI/BOOT/fb*.efi
test -f /boot/efi/EFI/BOOT/BOOTX64.EFI

# Titanoboa's settings for the ISO: its label, which the kernel uses to find
# the squashfs, and the boot menu.
mkdir -p /usr/lib/bootc-image-builder
cat > /usr/lib/bootc-image-builder/iso.yaml << EOF
label: "$label"
grub2:
  timeout: 5
  entries:
    - name: "Install $name"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=$label enforcing=0 rd.live.image"
      initrd: "/images/pxeboot/initrd.img"
    - name: "Install $name (basic graphics mode)"
      linux: "/images/pxeboot/vmlinuz quiet rhgb root=live:CDLABEL=$label enforcing=0 rd.live.image nomodeset"
      initrd: "/images/pxeboot/initrd.img"
EOF

dnf clean all
