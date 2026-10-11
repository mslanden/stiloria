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

Every build is signed with this repo's key (`cosign.pub` is its public half). Stiloria carries a container policy that accepts a `stiloria` or `stiloria-nvidia` image only with that signature, so once a machine runs Stiloria, every update it downloads is verified and anything else is rejected. The first switch from Bazzite can't check this yet, because Bazzite doesn't know the key; everything after it is checked.

## Repo layout

| Path | What it does |
| --- | --- |
| `Containerfile` | Starts from Bazzite and runs the build script |
| `build_files/build.sh` | Installs packages and enables services |
| `system_files/` | Copied as-is into the OS (configs, services) |
| `image-template.env` | Image name and metadata |
| `.github/workflows/build.yml` | Daily build, publish, and signing of both editions |

Built from the [Universal Blue image template](https://github.com/ublue-os/image-template).
