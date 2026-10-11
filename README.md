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

- **Achilles**, the voice assistant: hold <kbd>Super</kbd>+<kbd>`</kbd> to talk to it. It starts hidden at login, so push-to-talk works right away; open its window from the app launcher, or run `achilles` (or `stiloria`) in a terminal. See [Achilles](#achilles) for how it gets into the image.
- **Name and logo**: "Stiloria" in the boot menu, system info and Settings → About this System, with the helmet logo.
- **Terminal**: `fastfetch` shows the helmet and the image this machine runs (`stiloria:latest` or `stiloria-nvidia:latest`), with Bazzite's lock icon, closed once updates are verified.
- **Wallpapers**: six Stiloria wallpapers in the wallpaper picker (Stiloria, Temple at Night, Aegean Dawn, Marble Mind, Troy at Dusk and Stiloria Minimal), made with Qwen Image 2.1 on a local GPU except Stiloria Minimal, which is drawn from the vector logo. New accounts start with the default one, and existing accounts get it once at their first login on Stiloria (`/usr/libexec/stiloria-user-setup`); a wallpaper picked afterwards is never overwritten.
- **Colors**: the Stiloria color scheme, navy and gold from the logo and wallpapers, for apps, window title bars, the panel and menus, with a matching Konsole profile. New accounts start with it, and existing accounts get it once at their next login, like the wallpaper; another scheme picked afterwards in System Settings → Colors & Themes stays.
- **Recommended apps** from Flathub, on top of Bazzite's own (Firefox, Gwenview, Okular, Haruna, …): Discord, Photos (a gallery like the Windows Photos app), Heroic for Epic/GOG/Amazon games, OBS Studio and Bottles. They install on the first boot with a network connection. Each app is offered once per machine, so one you remove stays removed; adding an ID to `system_files/usr/share/stiloria/flatpaks` installs it everywhere on the next boot.
- **Local AI for Achilles**: the services behind Achilles' voice and chat, all running on this PC: two Ternary Bonsai language models on PrismML's llama.cpp (Vulkan, for AMD and NVIDIA), Whisper speech recognition through `voxtype`, and Kokoro text to speech on the CPU. Achilles starts them when it needs them (`stiloria-voice-model`, `stiloria-bonsai` and `kokoro-tts` user services); nothing runs at login. The models, about 10 GiB, download into your home folder with `stiloria-models install all`, and `stiloria-models status` shows what is there.

## Achilles

Achilles' source lives in a private repo, `mslanden/achilles`; Stiloria ships only the compiled app. The `achilles` job in `.github/workflows/build.yml` checks out the commit named in `achilles.ref` with a read-only deploy key (the `ACHILLES_DEPLOY_KEY` secret), builds it once in a Fedora 44 container, Bazzite's Fedora, so its libraries match the image's, and hands just the binary and its icon to both editions. `build_files/build.sh` installs it as `/usr/bin/achilles` (and `stiloria`) with a launcher entry, its icon, and an autostart entry that runs `achilles --hidden`, then fails the build unless every library it links is in the image and `achilles voice start` runs.

**The binary is public; the source is not.** Anyone can pull a Stiloria image, or download the `achilles` artifact of a workflow run (kept 7 days), and get the compiled app with its built-in web frontend. To keep the source private:

- The build logs are public, so the job builds quietly, and the compiler's output, which quotes source lines, goes to a file that is never printed or uploaded. A failed build shows only the error headlines; build the pinned commit on Fedora 44 to see the rest.
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

Built from the [Universal Blue image template](https://github.com/ublue-os/image-template).
