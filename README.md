<p align="center"><img src="branding/stiloria-logo.svg" alt="Stiloria logo: a navy line-art Corinthian helmet with a gold accent" width="160"></p>

# Stiloria

A Linux for gaming and AI, built on [Bazzite](https://bazzite.gg) with the KDE Plasma desktop. Stiloria is the home of **Achilles**, a local voice assistant for controlling the PC.

Stiloria is an image-based (bootc) system: this repo is the recipe, and GitHub Actions builds it daily on top of the latest Bazzite stable. Installed machines update to new builds automatically, and the previous version can be picked from the boot menu if an update misbehaves.

## Install

Pick the edition for your graphics card:

| GPU | Bazzite edition to install | Stiloria image |
| --- | --- | --- |
| AMD or Intel | Bazzite, KDE | `ghcr.io/mslanden/stiloria` |
| NVIDIA RTX, or GTX 16-series | Bazzite, KDE, NVIDIA | `ghcr.io/mslanden/stiloria-nvidia` |

Older NVIDIA cards (GTX 10-series and earlier) aren't supported yet. Switching an NVIDIA machine to the AMD/Intel image would remove its NVIDIA driver, so match the edition to the card.

1. Install [Bazzite](https://bazzite.gg) for your GPU, as in the table.
2. Switch to Stiloria and reboot (NVIDIA: use `stiloria-nvidia`):

   ```bash
   sudo bootc switch ghcr.io/mslanden/stiloria:latest
   systemctl reboot
   ```

## Signed updates

Every build is signed with this repo's key (`cosign.pub` is its public half). Stiloria carries a container policy that accepts a `stiloria` or `stiloria-nvidia` image only with that signature, so once a machine runs Stiloria, every update it downloads is verified and anything else is rejected. The first switch from Bazzite can't check this, because Bazzite doesn't know the key. On its first boot Stiloria therefore switches itself to signed tracking of the same image (`stiloria-signed-tracking.service`), which applies at the next reboot; from then on every update is verified, and `fastfetch` shows a closed lock. It waits if an update is already staged, and leaves images other than Stiloria's alone.

## What Stiloria adds to Bazzite

- **Name and logo**: "Stiloria" in the boot menu, system info and Settings → About this System, with the helmet logo.
- **Terminal**: `fastfetch` shows the helmet and the image this machine runs (`stiloria:latest` or `stiloria-nvidia:latest`), with Bazzite's lock icon, closed once updates are verified.
- **Wallpapers**: six Stiloria wallpapers in the wallpaper picker (Stiloria, Temple at Night, Aegean Dawn, Marble Mind, Troy at Dusk and Stiloria Minimal), made with Qwen Image 2.1 on a local GPU except Stiloria Minimal, which is drawn from the vector logo. New accounts start with the default one, and existing accounts get it once at their first login on Stiloria (`/usr/libexec/stiloria-user-setup`); a wallpaper picked afterwards is never overwritten.
- **Recommended apps** from Flathub, on top of Bazzite's own (Firefox, Gwenview, Okular, Haruna, …): Discord, Photos (a gallery like the Windows Photos app), Heroic for Epic/GOG/Amazon games, OBS Studio and Bottles. They install on the first boot with a network connection. Each app is offered once per machine, so one you remove stays removed; adding an ID to `system_files/usr/share/stiloria/flatpaks` installs it everywhere on the next boot.

## Repo layout

| Path | What it does |
| --- | --- |
| `Containerfile` | Starts from Bazzite and runs the build script |
| `build_files/build.sh` | Installs packages and enables services |
| `system_files/` | Copied as-is into the OS (configs, services) |
| `image-template.env` | Image name and metadata |
| `.github/workflows/build.yml` | Daily build, publish, and signing of both editions |

Built from the [Universal Blue image template](https://github.com/ublue-os/image-template).
