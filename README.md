# Stiloria

A Linux for gaming and AI, built on [Bazzite](https://bazzite.gg) with the KDE Plasma desktop. Stiloria is the home of **Achilles**, a local voice assistant for controlling the PC.

Stiloria is an image-based (bootc) system: this repo is the recipe, and GitHub Actions builds it daily into `ghcr.io/mslanden/stiloria`. Installed machines update to new builds automatically, and the previous version can be picked from the boot menu if an update misbehaves.

## Install

> Only the AMD/Intel edition exists so far. On an NVIDIA machine, wait for the NVIDIA edition: switching to this image would remove the NVIDIA driver.

1. Install [Bazzite](https://bazzite.gg) (KDE edition).
2. Switch to Stiloria and reboot:

   ```bash
   sudo bootc switch ghcr.io/mslanden/stiloria:latest
   systemctl reboot
   ```

## Repo layout

| Path | What it does |
| --- | --- |
| `Containerfile` | Starts from Bazzite and runs the build script |
| `build_files/build.sh` | Installs packages and enables services |
| `system_files/` | Copied as-is into the OS (configs, services) |
| `image-template.env` | Image name and metadata |
| `.github/workflows/build.yml` | Daily build, publish, and signing |

Built from the [Universal Blue image template](https://github.com/ublue-os/image-template).
