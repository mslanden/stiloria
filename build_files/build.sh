#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Updates must be signed with Stiloria's key
# Bazzite requires signatures only for its own ghcr.io/ublue-os images and takes
# anything else unsigned, Stiloria included. These rules make bootc (and podman)
# reject a Stiloria image unless cosign.key signed it; cosign.pub in this repo
# is its public half. Each edition is named exactly, so other images under the
# same GitHub account are not affected.
install -Dm644 /ctx/cosign.pub /etc/pki/containers/stiloria.pub
rule='[{"type": "sigstoreSigned", "keyPath": "/etc/pki/containers/stiloria.pub", "signedIdentity": {"type": "matchRepository"}}]'
jq --argjson rule "$rule" \
    '.transports.docker += {"ghcr.io/mslanden/stiloria": $rule, "ghcr.io/mslanden/stiloria-nvidia": $rule}' \
    /etc/containers/policy.json > /tmp/policy.json
install -m644 /tmp/policy.json /etc/containers/policy.json
printf '%s\n' 'docker:' \
    '  ghcr.io/mslanden/stiloria:' '    use-sigstore-attachments: true' \
    '  ghcr.io/mslanden/stiloria-nvidia:' '    use-sigstore-attachments: true' \
    > /etc/containers/registries.d/stiloria.yaml

### Branding
# The name shown in the boot menu, fastfetch and system info. Bazzite's NAME and
# ID stay, as does /usr/share/ublue-os/image-info.json: Bazzite's updater,
# hardware setup and other tools read those. The About page is
# system_files/etc/xdg/kcm-about-distrorc.
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Stiloria"/' /usr/lib/os-release

# New accounts get Stiloria's wallpaper through the Steam-style Plasma themes
# Bazzite uses, and the lock screen shows it too; existing accounts get it once
# from stiloria-user-setup. If Bazzite moves these, fail the build rather than
# quietly keep its wallpaper.
wallpaper=/usr/share/wallpapers/Stiloria/contents/images/3840x2160.jpg
test -f "$wallpaper"
for file in /usr/share/plasma/look-and-feel/com.valve.{vapor,vgui}.desktop/contents/plasmoidsetupscripts/org.kde.plasma.folder.js \
    /etc/xdg/kscreenlockerrc; do
    sed -i "s|/usr/share/wallpapers/convergence.jxl|$wallpaper|g" "$file"
    grep -q "$wallpaper" "$file"
done

### Recommended apps: system_files/usr/share/stiloria/flatpaks
systemctl enable stiloria-flatpak-manager.service

### Signed tracking: after the first switch from Bazzite, move to verified updates
systemctl enable stiloria-signed-tracking.service

### fastfetch: Stiloria's helmet and image line in Bazzite's layout. The logo is
# true-color half blocks, so it is printed raw and its size given explicitly.
fastfetch_config=/usr/share/ublue-os/bazzite/fastfetch.jsonc
sed -i \
    -e 's|"type": "file",|"type": "file-raw",|' \
    -e 's|"source": "/usr/share/ublue-os/bazzite/logo.txt",|"source": "/usr/share/stiloria/fastfetch-logo.txt", "width": 33, "height": 18,|' \
    -e 's|/usr/libexec/bazzite-fetch-image|/usr/libexec/stiloria-fetch-image|' \
    "$fastfetch_config"
grep -q '"file-raw"' "$fastfetch_config"
grep -q stiloria/fastfetch-logo.txt "$fastfetch_config"
grep -q stiloria-fetch-image "$fastfetch_config"

### From boot to desktop: the Plasma themes Bazzite uses for new accounts
for theme in /usr/share/plasma/look-and-feel/com.valve.{vapor,vgui}.desktop/contents; do
    # The loading screen after login: the helmet on its black background.
    gzip -9 -n -c /usr/share/stiloria/stiloria-logo-light.svg > "$theme/splash/images/bazzite_logo.svgz"
    # The start-menu button; existing accounts get it from stiloria-user-setup.
    sed -i 's|"distributor-logo-steamdeck"|"stiloria-start"|' "$theme/plasmoidsetupscripts/org.kde.plasma.kickoff.js"
    grep -q stiloria-start "$theme/plasmoidsetupscripts/org.kde.plasma.kickoff.js"
done
# The login screen's background.
sed -i "s|file:///usr/share/backgrounds/default.jxl|file://$wallpaper|g" /usr/lib/plasmalogin/defaults.conf
grep -q "$wallpaper" /usr/lib/plasmalogin/defaults.conf

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket
