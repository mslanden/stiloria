# Appended to Anaconda's interactive-defaults.ks by build.sh, which fills in
# @INSTALL_IMAGE@ (ghcr.io/mslanden/stiloria or -nvidia, :latest). The person
# installing still picks the disk, language and account in the installer.
# Adapted from Bazzite's installer (installer/titanoboa_hook_postrootfs.sh).

# bootupd puts the bootloader in EFI/fedora (efi_dir in the Anaconda profile)
# and fails if an earlier Fedora-based install left one on a reused EFI
# partition.
%pre-install --erroronfail
rm -rf /mnt/sysroot/boot/efi/EFI/fedora
%end

# Install the copy on the stick, so no download is needed. Its signature was
# checked when the ISO was built; a local copy has no signature to check.
ostreecontainer --url=@INSTALL_IMAGE@ --transport=containers-storage --no-signature-verification

# Track the image on GHCR, signed: `bootc upgrade` then downloads updates from
# there and rejects any that Stiloria's key didn't sign. stiloria-signed-tracking
# finds this already done on the first boot.
%post --erroronfail --log=/root/stiloria-signed-tracking.log
bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry @INSTALL_IMAGE@
%end

# Bazzite replaces the Fedora flatpak remote with Flathub.
%post --log=/root/stiloria-flatpak-remote.log
systemctl disable flatpak-add-fedora-repos.service || :
%end

# Copy the apps installed on the stick (installer/flatpaks) to the new system.
# Anaconda mounts the new system's /var over the deployment's var directory.
%post --erroronfail --nochroot --log=/tmp/stiloria-flatpaks.log
deployment="$(ostree rev-parse --repo=/mnt/sysimage/ostree/repo ostree/0/1/0)"
target="/mnt/sysimage/ostree/deploy/default/deploy/$deployment.0/var/lib/"
mkdir -p "$target"
rsync -aAXUHKP --open-noatime /var/lib/flatpak "$target"
sync "$target"
%end

# The copies above keep the live system's SELinux labels; give them the
# installed system's.
%post --erroronfail --log=/root/stiloria-selinux-labels.log
setenforce 0 || :
restorecon -R /etc/selinux
restorecon -R /var/lib/flatpak
%end

# Bazzite's kernel is signed with Universal Blue's key, which the firmware
# doesn't trust, so with Secure Boot on it wouldn't start. Queue the key for
# shim to enroll: on the next boot a blue "MOK management" screen asks to
# enroll it, with the password "universalblue".
%post --nochroot --log=/tmp/stiloria-secureboot.log
[[ -d /sys/firmware/efi ]] || exit 0
mokutil --timeout -1 || :
printf 'universalblue\nuniversalblue\n' | mokutil --import /etc/pki/akmods/certs/akmods-ublue.der || :
%end

# Tell the person installing what that blue screen is, before they restart.
%post --nochroot --log=/tmp/stiloria-secureboot-notice.log
LC_ALL=C mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der | grep -q "already in the enrollment request" || exit 0
run0 --user=liveuser yad --on-top --timeout=0 --button=OK:0 --title="Secure Boot" \
    --text="<b>One more step after restarting</b>

A blue screen titled <i>Perform MOK management</i> appears once.
Choose <b>Enroll MOK</b>, then <b>Continue</b> and <b>Yes</b>,
type the password <b>universalblue</b>, then choose <b>Reboot</b>.

This lets Secure Boot start Stiloria." || :
%end
