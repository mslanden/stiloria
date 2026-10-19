<p align="center"><img src="branding/stiloria-logo.svg" alt="Stiloria logo: a line-art Corinthian helmet" width="160"></p>

# Stiloria

A Linux for gaming and AI, built on [Bazzite](https://bazzite.gg) with the KDE Plasma desktop. Stiloria is the home of **Achilles**, a local voice assistant for controlling the PC.

Stiloria is an image-based (bootc) system: this repo is the recipe, and GitHub Actions builds it on top of the latest Bazzite stable whenever the image's files here change, and whenever Bazzite does (checked daily). Installed machines update to new builds automatically, and the previous version can be picked from the boot menu if an update misbehaves.

## Install

Pick the edition for your graphics card:

| GPU | Installer ISO | Stiloria image | Bazzite edition, to switch from |
| --- | --- | --- | --- |
| AMD or Intel | `stiloria-amd64.iso` | `ghcr.io/mslanden/stiloria` | Bazzite, KDE |
| NVIDIA RTX, or GTX 16-series | `stiloria-nvidia-amd64.iso` | `ghcr.io/mslanden/stiloria-nvidia` | Bazzite, KDE, NVIDIA |

Older NVIDIA cards (GTX 10-series and earlier) aren't supported yet. Switching an NVIDIA machine to the AMD/Intel image would remove its NVIDIA driver, so match the edition to the card.

### From a USB stick

1. Download the ISO for your card from the latest successful run of [Build installer ISOs](https://github.com/mslanden/stiloria/actions/workflows/build-disk.yml): open the run and scroll to **Artifacts** (downloading needs a GitHub account). The run's summary lists each ISO's SHA-256.
2. Write it to a USB stick of 16 GB or more with [Fedora Media Writer](https://github.com/FedoraQt/MediaWriter/releases) or [balenaEtcher](https://etcher.balena.io/), or with Rufus in "DD Image" mode. This erases the stick.
3. Start the PC from the stick, in UEFI mode; Secure Boot can stay on. The installer opens on a live Plasma desktop (closed, it's on the desktop as **Install to Hard Drive**): pick the language, the disk and your account. Everything is installed from the stick, so no network is needed.
4. On the first restart, a blue *Perform MOK management* screen appears once. Choose **Enroll MOK**, **Continue**, **Yes**, type the password `universalblue`, then **Reboot**. This lets Secure Boot start Bazzite's kernel, which Universal Blue signs.

### From Bazzite

1. Install [Bazzite](https://bazzite.gg) for your GPU, as in the table.
2. Switch to Stiloria and reboot (NVIDIA: use `stiloria-nvidia`):

   ```bash
   sudo bootc switch ghcr.io/mslanden/stiloria:latest
   systemctl reboot
   ```

## Signed updates

Every build is signed with this repo's key (`cosign.pub` is its public half). Stiloria carries a container policy that accepts a `stiloria` or `stiloria-nvidia` image only with that signature, so once a machine runs Stiloria, every update it downloads is verified and anything else is rejected. The installer ISOs are built only from images with a valid signature, and a machine installed from one tracks the signed image (`ostree-image-signed:docker://ghcr.io/mslanden/stiloria:latest`, or `stiloria-nvidia`) from its first boot. The first switch from Bazzite can't check this, because Bazzite doesn't know the key. On its first boot Stiloria therefore switches itself to signed tracking of the same image (`stiloria-signed-tracking.service`), which applies at the next reboot; from then on every update is verified, and `fastfetch` shows a closed lock. It waits if an update is already staged, and leaves images other than Stiloria's alone. Builds start only from a Bazzite image signed by Universal Blue (`.github/ublue-os.pub`, the key Bazzite itself checks), by the exact digest that was checked.

## What Stiloria adds to Bazzite

- **Achilles**, the voice assistant: hold <kbd>Super</kbd>+<kbd>`</kbd> to talk to it. It starts hidden at login, so push-to-talk works right away; open its window from the app launcher, or run `achilles` (or `stiloria`) in a terminal. See [Achilles](#achilles) for how it gets into the image.
- **Name and logo**: "Stiloria" in the boot menu, system info and Settings → About this System, with the helmet logo, drawn in one color as Porcelain asks (ink on light, ivory on dark); the start button is a solid helmet in the text color, so it turns ivory at night, and a new install is named `stiloria` until you rename it (an existing install keeps its name; `sudo hostnamectl hostname stiloria` changes it).
- **Terminal**: `fastfetch` shows the helmet and the image this machine runs (`stiloria:latest` or `stiloria-nvidia:latest`), with Bazzite's lock icon, closed once updates are verified.
- **Wallpapers**: the default wallpaper, on the desktop, lock screen and login screen, is Stiloria Helmet: a bronze Corinthian helmet on a marble plinth against a dark wall, the same by day and night. Eight more are in the wallpaper picker (Stiloria, a Greek sky city with a matching night version that Plasma shows while the night colors are on; Sky Isles, Marble Terrace, Temple at Night, Aegean Dawn, Marble Mind, Troy at Dusk and Stiloria Minimal), made with Qwen Image 2.1 on a local GPU except Stiloria Minimal, which is drawn from the vector logo. Accounts still on the sky city, the default for a while, move to the helmet once at their next login; a wallpaper picked in the picker otherwise stays.
- **Look: Porcelain, by day and night**: Stiloria follows the Porcelain design: ivory and stone with near-black "ink" text, one cool slate accent, solid panels and menus, quiet sunk hovers, ink focus rings, pill fields and buttons, and Instrument Sans for the interface with Instrument Serif for display text (both SIL OFL, from Google Fonts, shipped in `/usr/share/fonts` since Fedora doesn't package them). Folders are stone rather than slate: the Stiloria and Stiloria-Dark icon themes are Breeze and Breeze Dark with their accent-filled folders recolored, made from the image's own Breeze during the build (`build_files/make_folder_icons.py`). Stiloria Day is the light version and Stiloria Night the dark one (warm black, ivory text), switched automatically at sunrise and sunset by Plasma's own day/night setting (System Settings → Global Theme). New accounts start with them; existing accounts move over once at their next login (`/usr/libexec/stiloria-user-setup`), keeping their panel's apps. Accounts that moved over before October 2026 had the automatic switching turned off by mistake; it comes back on once at their next login. Konsole has a matching warm-black profile. The color schemes and the Plasma style are generated by `tools/make_colors.py` (which checks every text color for WCAG AA contrast) and `tools/make_plasma_style.py`.
- **Desktop greeting**: the Stiloria Greeting widget at the top left of the desktop shows the date and time, greets you by name in Instrument Serif ("Good evening, *Marcelino.*"), and shows how to talk to Achilles. Its Text setting (right-click → Configure Stiloria Greeting) either follows the colors, ink by day and ivory at night, or stays ivory or ink at all hours; on the helmet wallpaper, which is dark all day, it is set to ivory. New desktops get it, and existing ones once at their next login; it can be moved or removed like any widget.
- **Recommended apps** from Flathub, on top of Bazzite's own (Firefox, Gwenview, Okular, Haruna, …): Discord, Photos (a gallery like the Windows Photos app), Heroic for Epic/GOG/Amazon games, OBS Studio, Bottles and Virtual Machine Manager (virt-manager). They install on the first boot with a network connection, each on its own, so one that fails doesn't hold up the rest: a failed app is tried again every 5 minutes for about an hour, then at the next boot, and an ID Flathub doesn't have is skipped. Each app is offered once per machine, so one you remove stays removed; adding an ID to `system_files/usr/share/stiloria/flatpaks` installs it everywhere on the next boot.
- **Vivaldi**, the web browser, as Vivaldi's own RPM rather than a Flatpak, so password managers and other apps that talk to the browser work as they would on any Fedora. Each daily build installs the latest release, so it updates with the image; it lives in `/usr/lib/opt/vivaldi`, linked to `/opt/vivaldi` at boot, because bootc fills `/opt` (which is `/var/opt`) from the image only once. Its media codecs download into your home the first time it starts.
- **Virtual machines**: QEMU/KVM and libvirt are part of the image, so Virtual Machine Manager runs VMs on the system's libvirt (the "QEMU/KVM" connection, `qemu:///system`) rather than inside its Flatpak, as `ujust setup-virtualization` would set it up. That brings virtio networking on libvirt's NAT network "default", UEFI with Secure Boot and a TPM for Windows 11 (`edk2-ovmf`, `swtpm`), shared folders (`virtiofsd`), and USB and PCI devices passed through to a VM; no `ujust` step is needed. Administrators (the wheel group) manage VMs without a password, and `virsh -c qemu:///system` works from a terminal. The daemons start when something connects, so nothing runs until you open a VM. KVM ignores the model-specific registers it doesn't emulate instead of crashing Windows guests over them. VMs made earlier inside the Flatpak (its "QEMU User session" connection) keep running there; they move to the system connection by recreating them with the same disk.
- **Local AI for Achilles**: the services behind Achilles' voice and chat, all running on this PC: two Ternary Bonsai language models on PrismML's llama.cpp (Vulkan, for AMD and NVIDIA), Whisper speech recognition through `voxtype`, and Kokoro text to speech on the CPU. Achilles starts them when it needs them (`stiloria-voice-model`, `stiloria-bonsai` and `kokoro-tts` user services); nothing runs at login. They listen only on 127.0.0.1, and the language models run without llama.cpp's web UI and slot monitor and answer only requests that carry your API key (all but `/health`), so websites open in a browser can't use them. The key is made the first time they start, in `~/.local/state/stiloria/llama-api-key`, readable only by you; Achilles sends it, and so must anything else that calls them, e.g. `curl -H "Authorization: Bearer $(< ~/.local/state/stiloria/llama-api-key)" http://127.0.0.1:8085/props`. The models, about 10 GiB, download into your home folder with `stiloria-models install all`, and `stiloria-models status` shows what is there. Kokoro's Python runtime is made for the image's Python: after an update moves to a new Python, `stiloria-models install tts` sets it up again.

## Achilles

Achilles' source lives in a private repo, `mslanden/achilles`; Stiloria ships only the compiled app. The `achilles` job in `.github/workflows/build.yml` checks out the commit named in `achilles.ref` with a read-only deploy key (the `ACHILLES_DEPLOY_KEY` secret), builds it once in a container of Bazzite stable's Fedora release (read from Bazzite's version label, so it follows Bazzite to each new Fedora), where its libraries match the image's, and hands just the binary and its icon to both editions. `build_files/build.sh` installs it as `/usr/bin/achilles` (and `stiloria`) with a launcher entry, its icon, and an autostart entry that runs `achilles --hidden`, then fails the build unless every library it links is in the image and `achilles voice start` runs.

**The binary is public; the source is not.** Anyone can pull a Stiloria image, or download the `achilles` artifact of a workflow run (kept 7 days), and get the compiled app with its built-in web frontend. To keep the source private:

- The build logs are public, so the job builds quietly, and the compiler's output, which quotes source lines, goes to a file that is never printed or uploaded. A failed build shows only the error headlines; build the pinned commit on that Fedora release to see the rest.
- Only the binary and icon leave the job. The binary has no symbol table, and the job fails if the frontend build makes source maps, since those would carry its source into the binary.
- The caches hold only third-party crates and npm downloads, since pull requests can read them.

Pull requests from forks and from Dependabot can't read the deploy key, so their images are built without Achilles and the run shows a warning. Pushes to `main`, the daily build and manual runs fail without it.

**To update Achilles**, put the commit to ship in `achilles.ref` and open a pull request; its CI builds that commit into both editions.

```bash
git -C path/to/achilles rev-parse HEAD > achilles.ref
```

**To build the image locally**, put the binary and icon in `achilles/` (git ignores it), from the latest build on `main`:

```bash
run=$(gh run list -R mslanden/stiloria -w build.yml -b main -s success -L 1 --json databaseId -q '.[0].databaseId')
gh run download "$run" -R mslanden/stiloria -n achilles -D achilles
```

or build without it: `mkdir -p achilles && echo "local build" > achilles/skipped`.

## Repo layout

| Path | What it does |
| --- | --- |
| `Containerfile` | Starts from Bazzite and runs the build script |
| `build_files/build.sh` | Installs packages and enables services |
| `system_files/` | Copied as-is into the OS (configs, services) |
| `image-template.env` | Image name and metadata |
| `achilles.ref` | The Achilles commit built into the image |
| `.github/workflows/build.yml` | Daily build, publish, and signing of both editions |
| `installer/` | The live system on the installer ISO: Stiloria plus Anaconda and the edition it installs |
| `.github/workflows/build-disk.yml` | Builds both installer ISOs with [Titanoboa](https://github.com/ublue-os/titanoboa), on demand and for releases |

Built from the [Universal Blue image template](https://github.com/ublue-os/image-template).
