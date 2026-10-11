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
