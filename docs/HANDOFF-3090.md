# HANDOFF — 3090 Omarchy install hardening

Date: 2026-01-29

This document captures what we changed in the Omarchy installer fork and what remains to do.

## Repo
- Fork: `mustardthepirate/omarchy`
- Branch: `master`

Install one-liner:

```bash
OMARCHY_REPO=mustardthepirate/omarchy OMARCHY_REF=master \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/mustardthepirate/omarchy/master/boot.sh)"
```

## Primary problems we hit (3090 desktop)
1) **NVIDIA / DKMS / mkinitcpio failures**
   - Common symptoms:
     - `==> ERROR: module not found: 'nvidia' ... 'nvidia_uvm'`
     - `mkinitcpio failed for kernel ... skipping`
   - Root causes seen:
     - `linux` and `linux-headers` out of sync (e.g. kernel 6.18.7, headers 6.18.3).
     - Stale `/etc/mkinitcpio.conf.d/nvidia.conf` forcing early-load modules when they don’t exist yet.
     - DKMS building for the wrong kernel version during an install/upgrade.

2) **Limine config conflicts + boot menu duplication**
   - Symptom:
     - Limine hook warns `Detected conflicting config: /boot/limine/limine.conf`
     - Multiple EFI Boot#### entries with label `Limine` (or multiple Omarchy/Arch entries), only one works.
   - Root cause:
     - Multiple Limine config locations; Limine search order loads an unexpected config.
     - Repeated Limine installs/updates creating duplicate NVRAM entries.

3) **/boot fails to mount (`unknown filesystem type 'vfat'`)**
   - Root cause: missing `dosfstools` (mount.vfat helper), often after interrupted/partial install.

4) **TTE screensaver Python mismatch**
   - Symptom: `/usr/bin/tte` fails `ModuleNotFoundError: No module named 'terminaltexteffects'` after Python bump.

## What we changed (hardening)
### Preflight
- Ensure `dosfstools` installed during online preflight (`install/preflight/pacman.sh`).
- Added guard: **refuse install if `pacman -Syu --print` wants to downgrade `linux`** (stale mirrors). Override via `OMARCHY_ALLOW_KERNEL_DOWNGRADE=1`.

### NVIDIA install logic (`install/config/hardware/nvidia.sh`)
- Default to **kernel-agnostic DKMS** approach.
- Added opt-outs:
  - `OMARCHY_SKIP_NVIDIA=1` to skip.
  - `OMARCHY_NVIDIA_FLAVOR=open` to use open modules explicitly.
  - `OMARCHY_NVIDIA_LEGACY_580XX=1` to opt into legacy.
- Hardened DKMS behavior:
  - Build against newest installed kernel in `/usr/lib/modules/*`.
  - Verify headers are present for that kernel (`/usr/lib/modules/<kver>/build`), attempt to install headers.
  - Only write mkinitcpio NVIDIA MODULES drop-in if `modinfo -k <kver> nvidia` succeeds.
  - Remove stale `/etc/mkinitcpio.conf.d/nvidia.conf` at start.
  - Best-effort remove `nvidia-open(-dkms)` when using proprietary `nvidia-dkms`.
  - Attempt to align `linux` + `linux-headers` when mismatched.

### Limine config handling
- Preserve `/boot/limine/limine.conf` as a **symlink** to `/boot/limine.conf` (non-destructive).
- In `install/login/limine-snapper.sh`, remove conflicting config locations:
  - ensure `/boot/limine/limine.conf` isn’t a real file
  - remove `/boot/EFI/limine/limine.conf` and `/boot/EFI/BOOT/limine.conf` (best-effort)

### Post-install validation (new)
- Added `install/post-install/validate.sh` and wired it into `install/post-install/all.sh`.
- Validation fails if:
  - `linux` and `linux-headers` are out of sync
  - `/boot/limine.conf` missing
  - `/boot/limine/limine.conf` is a real file (conflict)
  - `limine-update` missing or reports conflicting configs
  - `mkinitcpio -P` produces errors or `mkinitcpio failed`

### Screensaver / TTE
- `bin/omarchy-launch-screensaver` now checks `python -c 'import terminaltexteffects'` and exits cleanly with a notification if broken.

### Install from fork
- `boot.sh` supports `OMARCHY_REPO` + `OMARCHY_REF`.

### Clawdbot local tooling
- Added `install/post-install/clawdbot.sh` to install `clawdbot` via mise+node and npm.
- Updated to use `mise exec node@<ver> -- npm install -g clawdbot` so npm is available in non-interactive shells.

## Known gaps / TODO
1) **Boot menu cleanup**
   - Need to automatically de-duplicate EFI NVRAM boot entries (Boot####) labeled `Limine` and set BootOrder deterministically.
   - Need to ensure Limine menu shows exactly:
     - Omarchy entry
     - a Linux entry
     - snapshot entries when snapper snapshots exist

2) **Limine tooling availability**
   - On some installs `limine-update` is missing even if Limine boots; Omarchy should ensure the package providing `limine-update` is installed and available.

3) **Ensure the installed system actually ran the fork**
   - Some installs ended up with old `~/.local/share/omarchy` HEAD. Always verify `git rev-parse --short HEAD` after clone.

## Operational notes
- Always ensure `/boot` is mounted as vfat ESP and writable before running the installer.
- Always ensure `linux-headers` is installed and matches `linux` before NVIDIA DKMS.
- If the system lands in emergency mode due to `/boot` mount failure, install `dosfstools` (from cache or ISO chroot) then rerun `limine-update` + `mkinitcpio -P`.
