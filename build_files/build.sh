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
# The computer's name until someone sets one (shown in the terminal prompt as
# user@stiloria). A system that already has a name keeps it.
sed -i 's/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME="stiloria"/' /usr/lib/os-release
grep -qx 'DEFAULT_HOSTNAME="stiloria"' /usr/lib/os-release

# New accounts get Stiloria's wallpaper, the bronze helmet, through the
# Steam-style Plasma themes Bazzite uses, and the lock and login screens show
# it too; existing accounts get it once from stiloria-user-setup. If Bazzite
# moves these, fail the build rather than quietly keep its wallpaper.
wallpaper=/usr/share/wallpapers/Stiloria-Helmet/contents/images/3840x2160.jpg
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

### Colors: Stiloria's scheme for Bazzite's own global themes (Stiloria.colors)
# A new account gets the colors its global theme, Bazzite's Vapor, names: at
# the first login startplasma copies the theme's defaults into
# ~/.config/kdedefaults, which overrides /etc/xdg/kdeglobals, and applies that
# ColorScheme. Window title bars follow the scheme's Header colors. Vapor's
# Plasma style has fixed colors of its own, so the panel and menus get Breeze's
# ("default"), which is otherwise the same and follows the scheme. Existing
# accounts get both once from stiloria-user-setup. VGUI, Valve's retro theme,
# keeps its own colors.
lnf_defaults=/usr/share/plasma/look-and-feel/com.valve.vapor.desktop/contents/defaults
test -f /usr/share/color-schemes/Stiloria.colors
test -f /usr/share/plasma/desktoptheme/default/metadata.json
sed -i -e 's/^ColorScheme=Vapor$/ColorScheme=Stiloria/' -e 's/^name=Vapor$/name=default/' "$lnf_defaults"
grep -qx ColorScheme=Stiloria "$lnf_defaults"
grep -qx name=default "$lnf_defaults"
# Konsole's matching profile. Bazzite names the default profile in
# /etc/xdg/kdeglobals, which konsolerc falls back to, so it applies to every
# account that hasn't picked one; a DefaultProfile in /etc/xdg/konsolerc would
# hide it.
test -f /usr/share/konsole/Stiloria.profile
sed -i 's/^DefaultProfile=Vapor.profile$/DefaultProfile=Stiloria.profile/' /etc/xdg/kdeglobals
grep -qx DefaultProfile=Stiloria.profile /etc/xdg/kdeglobals
test -z "$(grep -s '^DefaultProfile=' /etc/xdg/konsolerc)"

### Stiloria Day and Night: the Porcelain look, following the time of day
# Two global themes (look-and-feel/com.stiloria.{day,night}.desktop) in the
# Porcelain design: ivory and stone with ink text by day, warm black with ivory
# text at night, one slate accent. Both use the Stiloria Plasma style (solid
# panel and menus, sunk hovers, ink focus rings) with the color schemes
# StiloriaDay and Stiloria; tools/make_plasma_style.py and tools/make_colors.py
# generate them. Plasma's own switcher (the
# lookandfeelautoswitcher kded module) changes between them at sunrise and
# sunset. Their wallpaper is the Stiloria Helmet, dark by day and night alike,
# so their layout sets the desktop greeting to ivory text at all hours. (The
# Stiloria sky city in the picker has a night image, contents/images_dark,
# that Plasma shows with the night colors.) New accounts start in Stiloria Day
# with a floating panel and the switcher on; existing accounts move over once
# in stiloria-user-setup.
for file in /usr/share/color-schemes/StiloriaDay.colors /usr/share/color-schemes/Stiloria.colors \
    /usr/share/plasma/desktoptheme/stiloria/metadata.json \
    /usr/share/plasma/look-and-feel/com.stiloria.{day,night}.desktop/metadata.json \
    /usr/share/plasma/look-and-feel/com.stiloria.{day,night}.desktop/contents/layouts/org.kde.plasma.desktop-layout.js \
    /usr/share/wallpapers/Stiloria/contents/images{,_dark}/3840x2160.jpg; do
    test -f "$file"
done
sed -i 's/^LookAndFeelPackage=com.valve.vapor.desktop$/LookAndFeelPackage=com.stiloria.day.desktop/' /etc/xdg/kdeglobals
sed -i '/^LookAndFeelPackage=com.stiloria.day.desktop$/a AutomaticLookAndFeel=true\nDefaultLightLookAndFeel=com.stiloria.day.desktop\nDefaultDarkLookAndFeel=com.stiloria.night.desktop' /etc/xdg/kdeglobals
for line in LookAndFeelPackage=com.stiloria.day.desktop AutomaticLookAndFeel=true \
    DefaultLightLookAndFeel=com.stiloria.day.desktop DefaultDarkLookAndFeel=com.stiloria.night.desktop; do
    test "$(grep -cx "$line" /etc/xdg/kdeglobals)" = 1
done
# The lock screen names the wallpaper package, as the desktop does, rather
# than its image file.
sed -i "s|=$wallpaper\$|=/usr/share/wallpapers/Stiloria-Helmet/|" /etc/xdg/kscreenlockerrc
test "$(grep -c '=/usr/share/wallpapers/Stiloria-Helmet/$' /etc/xdg/kscreenlockerrc)" = 2
# Folders in Porcelain's stone instead of the slate accent: two icon themes,
# Stiloria and Stiloria-Dark, that inherit Breeze and Breeze Dark and replace
# only the accent-filled folder icons, made here from the image's own Breeze
# (make_folder_icons.py). Stiloria Day and Night name them.
python3 /ctx/make_folder_icons.py
for theme in Stiloria Stiloria-Dark; do
    for size in 32 48 64 96; do
        grep -q 'style="fill:#' "/usr/share/icons/$theme/places/$size/folder.svg"
        test -z "$(grep -l 'class="ColorScheme-Accent"' "/usr/share/icons/$theme/places/$size/folder.svg")"
    done
    test -L "/usr/share/icons/$theme/mimetypes/64/inode-directory.svg"
    test -f "/usr/share/icons/$theme/icon-theme.cache"
done
grep -qx Theme=Stiloria /usr/share/plasma/look-and-feel/com.stiloria.day.desktop/contents/defaults
grep -qx Theme=Stiloria-Dark /usr/share/plasma/look-and-feel/com.stiloria.night.desktop/contents/defaults
# Porcelain's typefaces, Instrument Sans for the interface and Instrument Serif
# for display text (the greeting, the boot wordmark). Fedora doesn't package
# them, so they ship in system_files/usr/share/fonts (from github.com/google/fonts,
# SIL Open Font License, OFL.txt beside each). Instrument Sans replaces Noto Sans
# in Bazzite's default fonts; Fira Code stays the fixed-width font.
fc-cache -f /usr/share/fonts/instrument-sans /usr/share/fonts/instrument-serif
test "$(fc-match -f '%{family}' 'Instrument Sans')" = "Instrument Sans"
test "$(fc-match -f '%{family}' 'Instrument Serif')" = "Instrument Serif"
sed -i 's/^\(font\|menuFont\|smallestReadableFont\|toolBarFont\)=Noto Sans,/\1=Instrument Sans,/' /etc/xdg/kdeglobals
test "$(grep -c '^\(font\|menuFont\|smallestReadableFont\|toolBarFont\)=Instrument Sans,' /etc/xdg/kdeglobals)" = 4

### Boot screen: Stiloria's watermark under the firmware logo (Plymouth's bgrt
# theme draws spinner/watermark.png). Plymouth runs from the initramfs, so
# rebuild it with Bazzite's own dracut settings (/usr/lib/dracut/dracut.conf.d:
# generic, reproducible, zstd) and fail the build unless it still carries
# exactly the same dracut modules, ostree among them.
install -m644 /usr/share/stiloria/plymouth-watermark.png /usr/share/plymouth/themes/spinner/watermark.png
kernel=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
test "$(wc -l <<< "$kernel")" = 1
initramfs=/usr/lib/modules/$kernel/initramfs.img
modules() { lsinitrd -m "$1" | sed -n '/dracut modules:/,$p' | tail -n +2 | sort; }
modules "$initramfs" > /tmp/initramfs-modules.before
# /root links to /var/roothome, which only exists once booted; the original
# initramfs has it, so give dracut something to copy, then remove it again.
mkdir -p /var/roothome
dracut --no-hostonly --kver "$kernel" --add ostree --force "$initramfs"
rmdir /var/roothome
chmod 0600 "$initramfs"
modules "$initramfs" | diff /tmp/initramfs-modules.before -
lsinitrd -f usr/share/plymouth/themes/spinner/watermark.png "$initramfs" | cmp - /usr/share/stiloria/plymouth-watermark.png

### Local AI services
# Achilles, the voice assistant, talks to these over HTTP on 127.0.0.1 and
# starts them on demand with `systemctl --user start` (the units are in
# system_files/usr/lib/systemd/user and none is enabled, so nothing runs at
# login). The programs are part of the image; the models are gigabytes, so each
# user downloads them into their home with `stiloria-models install`.
#
# Both language models run on llama-server from PrismML's llama.cpp fork, since
# upstream llama.cpp can't load their PQ2_0 format. The Vulkan build runs on
# AMD (Mesa) and NVIDIA cards alike. Use prism-b10772 or newer: in the Vulkan
# build of prism-b10683, PQ2_0 weights stay on the CPU (fixed by PrismML's
# PR #238), at a few tokens a second.
llama_release=prism-b10772-e8fd209
llama_sha256=bf0849e2ad6ca39aed5338ab6072ea10f83c9ab28e30e1f34b553b87550af16e
curl -fsSL --retry 3 -o /tmp/llama.tar.gz \
    "https://github.com/PrismML-Eng/llama.cpp/releases/download/$llama_release/llama-$llama_release-bin-ubuntu-vulkan-x64.tar.gz"
echo "$llama_sha256  /tmp/llama.tar.gz" | sha256sum -c -
install -d -m755 /usr/lib/stiloria/llama.cpp
tar -xzf /tmp/llama.tar.gz -C /usr/lib/stiloria/llama.cpp --strip-components=1 --no-same-owner
rm /tmp/llama.tar.gz
# The programs run as the user: check them as nobody, not root.
as_user() { setpriv --reuid=nobody --regid=nobody --clear-groups "$@"; }
# It is built for Ubuntu: fail here if Fedora lacks a library it needs.
test -z "$(ldd /usr/lib/stiloria/llama.cpp/llama-server /usr/lib/stiloria/llama.cpp/lib*.so | grep 'not found')"
llama_version=$(as_user /usr/lib/stiloria/llama.cpp/llama-server --version 2>&1)
grep -q "commit ${llama_release##*-}" <<< "$llama_version"

# Speech to text: voxtype's release builds for x86-64 CPUs with AVX2, and a
# baseline build for older ones; /usr/bin/voxtype picks one. (Its RPM bundles
# every GPU variant as well and is 375 MB.)
voxtype_version=1.1.0
install -d -m755 /usr/lib/voxtype
for build in avx2:e7d5de68cc8fc610c3c961c47f879451db9bee4a2df152e9a66f1078072e7f28 \
    baseline:1c9d78b4f6805e4f12ba3670949d3c22788269bdbc54215afffa42cafd0b4a7a; do
    binary=/usr/lib/voxtype/voxtype-${build%%:*}
    curl -fsSL --retry 3 -o "$binary" \
        "https://github.com/peteonrails/voxtype/releases/download/v$voxtype_version/voxtype-$voxtype_version-linux-x86_64-${build%%:*}"
    echo "${build#*:}  $binary" | sha256sum -c -
    chmod 755 "$binary"
    test -z "$(ldd "$binary" | grep 'not found')"
    test "$(as_user "$binary" --version)" = "voxtype $voxtype_version"
done
test "$(as_user voxtype --version)" = "voxtype $voxtype_version"

# Text to speech: Kokoro on the CPU, so the GPU stays with games and the
# language models. Its server (system_files/usr/lib/stiloria/kokoro) turns text
# into phonemes with espeak-ng, and stiloria-models installs the onnxruntime
# and numpy wheels pinned in requirements.txt. Each wheel is built for one
# Python, so install them here the way stiloria-models does, and import them:
# when Bazzite moves to a new Python, the build fails until requirements.txt
# has its wheels, rather than shipping text to speech that can't install.
rpm -q espeak-ng || dnf5 install -y espeak-ng
test -e /usr/lib64/libespeak-ng.so.1
kokoro_check=$(mktemp -d)
chown nobody: "$kokoro_check"
as_user env HOME="$kokoro_check" python3 -m venv "$kokoro_check/venv"
if ! as_user env HOME="$kokoro_check" "$kokoro_check/venv/bin/pip" install --disable-pip-version-check --no-input --no-cache-dir \
    --no-deps --only-binary=:all: --require-hashes -r /usr/lib/stiloria/kokoro/requirements.txt; then
    echo "pip couldn't install Kokoro's requirements.txt (above). If it lacks wheels for this image's $(python3 --version), add them (see the file)." >&2
    exit 1
fi
as_user env ORT_DISABLE_TELEMETRY=1 "$kokoro_check/venv/bin/python" -c 'import numpy, onnxruntime'
rm -rf "$kokoro_check"
as_user stiloria-models --help > /dev/null

### Desktop greeting
# The greeting sets the date in Instrument Sans and "Good evening, Marcelino."
# in Instrument Serif, which ship with the Porcelain look above; fail if
# fontconfig picks another font for a face it uses.
test "$(fc-match -f '%{file}' 'Instrument Serif')" = /usr/share/fonts/instrument-serif/InstrumentSerif-Regular.ttf
test "$(fc-match -f '%{file}' 'Instrument Serif:italic')" = /usr/share/fonts/instrument-serif/InstrumentSerif-Italic.ttf
test "$(fc-match -f '%{family}' 'Instrument Sans:semibold')" = "Instrument Sans"

# The greeting at the top left of the desktop is a Plasma widget, Stiloria
# Greeting (system_files/usr/share/plasma/plasmoids/com.stiloria.greeting).
# Stiloria Day and Night's desktop layout adds it, and stiloria-user-setup adds
# it once to existing desktops.
applet=/usr/share/plasma/plasmoids/com.stiloria.greeting
jq -e '.KPlugin.Id == "com.stiloria.greeting"' "$applet/metadata.json" > /dev/null
out=$(kpackagetool6 --type Plasma/Applet --show com.stiloria.greeting)
grep -q "Path *: $applet/" <<< "$out"
# And Plasma must load it. plasmawindowed runs it off screen, as nobody, for 10
# seconds: any message about its files (an import Plasma dropped, a property
# it renamed) fails the build, as does plasmawindowed quitting early.
home=$(mktemp -d)
chown nobody: "$home"
status=0
as_user env HOME="$home" XDG_RUNTIME_DIR="$home" LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    dbus-run-session -- timeout 10 plasmawindowed com.stiloria.greeting > /tmp/greeting.log 2>&1 || status=$?
# Services D-Bus started for it outlive the session.
pkill -u nobody || true
if [[ $status != 124 ]] || grep -E "plasmoids/com.stiloria.greeting|error when loading applet" /tmp/greeting.log; then
    cat /tmp/greeting.log
    echo "Stiloria Greeting didn't load (plasmawindowed: $status, 124 means it ran)" >&2
    exit 1
fi

### Existing accounts: stiloria-user-setup
# It talks to Plasma with Qt 6's qdbus-qt6. Plain qdbus is Qt 4's (Fedora's
# qt package), which Bazzite could drop at any time; fail if a step uses it.
command -v qdbus-qt6
test -z "$(grep -nE '(^|[[:space:]])qdbus[[:space:]]' /usr/libexec/stiloria-user-setup)"
# Each account remembers only the last step it ran, so a missing number would
# be skipped for good by every account past it: the steps must be 1, 2, 3, …
steps=$(grep -oP '^if \(\(done_steps < \K[0-9]+(?=\)\); then$)' /usr/libexec/stiloria-user-setup)
if [[ $steps != "$(seq "$(wc -l <<< "$steps")")" ]]; then
    echo "stiloria-user-setup's steps aren't numbered 1, 2, 3, … with none missing: ${steps//$'\n'/, }" >&2
    exit 1
fi

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

### Achilles, Stiloria's desktop assistant (see "Achilles" in the README)
# The workflow's achilles job builds it from the private mslanden/achilles, at
# the commit in achilles.ref, on the Fedora release Bazzite is built on, and
# hands over only the binary and its icon. Pull requests that can't read the
# deploy key (from forks, or Dependabot) build without it, and
# achilles/skipped says so.
if [[ -f /ctx/achilles/skipped ]]; then
    echo "Building without Achilles: $(< /ctx/achilles/skipped)"
elif [[ ! -f /ctx/achilles/achilles ]]; then
    echo "achilles/ has no Achilles binary: see \"Achilles\" in the README" >&2
    exit 1
else
    install -Dm755 /ctx/achilles/achilles /usr/bin/achilles
    ln -s achilles /usr/bin/stiloria
    # Its icon, the Shield of Achilles: in full from 48px up, and simpler at
    # 16-32px, where the full shield's waves blur.
    install -Dm644 /ctx/achilles/com.stiloria.desktop.png /usr/share/icons/hicolor/256x256/apps/com.stiloria.desktop.png
    install -Dm644 /ctx/achilles/com.stiloria.desktop.svg /usr/share/icons/hicolor/scalable/apps/com.stiloria.desktop.svg
    for size in 16 22 24 32; do
        install -Dm644 "/ctx/achilles/com.stiloria.desktop-$size.png" "/usr/share/icons/hicolor/${size}x${size}/apps/com.stiloria.desktop.png"
    done
    # GTK trusts hicolor's icon cache unless it is older than the theme folder,
    # and on an installed system every file has the same timestamp, so the
    # cache must list the icon. RPM triggers refresh it; nothing does here.
    gtk-update-icon-cache -f /usr/share/icons/hicolor
    grep -q com.stiloria.desktop /usr/share/icons/hicolor/icon-theme.cache

    cat > /usr/share/applications/com.stiloria.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Achilles
Comment=Achilles desktop assistant
Exec=achilles
Icon=com.stiloria.desktop
Terminal=false
Categories=Utility;
StartupWMClass=achilles
EOF
    # Start at login without a window, so push-to-talk works right away. Builds
    # of Achilles from before --hidden ignore it and open their window. Only in
    # Plasma: in Game Mode a window would cover Steam.
    cat > /etc/xdg/autostart/achilles.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Achilles
Comment=Starts Achilles in the background, for push-to-talk
Exec=achilles --hidden
Icon=com.stiloria.desktop
Terminal=false
OnlyShowIn=KDE;
EOF
    desktop-file-validate /usr/share/applications/com.stiloria.desktop /etc/xdg/autostart/achilles.desktop

    # Achilles was linked against plain Fedora's libraries, not this image's:
    # fail if Bazzite lacks one, or has an older one than it needs.
    ldd /usr/bin/achilles > /tmp/achilles-libs 2>&1
    if grep 'not found' /tmp/achilles-libs; then
        echo "Achilles needs libraries this image lacks (above)" >&2
        exit 1
    fi
    # And it must run. With no Achilles running, a push-to-talk press says so
    # and exits 1; that loads every library it links, without a display.
    status=0
    out=$(XDG_RUNTIME_DIR="$(mktemp -d)" timeout 60 achilles voice start 2>&1) || status=$?
    echo "$out"
    test "$status" = 1
    grep -q "Achilles isn't running" <<< "$out"
fi
