NVIDIA="$(lspci | grep -i 'nvidia')"

if [ -n "$NVIDIA" ]; then
  # Opt-out
  if [ "${OMARCHY_SKIP_NVIDIA:-0}" = "1" ]; then
    echo "[omarchy] OMARCHY_SKIP_NVIDIA=1 set; skipping NVIDIA."
    exit 0
  fi

  # Determine installed kernel -> headers (do not guess on custom kernels)
  KERNEL_HEADERS=""
  if pacman -Qq linux >/dev/null 2>&1; then
    KERNEL_HEADERS="linux-headers"
  elif pacman -Qq linux-lts >/dev/null 2>&1; then
    KERNEL_HEADERS="linux-lts-headers"
  elif pacman -Qq linux-zen >/dev/null 2>&1; then
    KERNEL_HEADERS="linux-zen-headers"
  elif pacman -Qq linux-hardened >/dev/null 2>&1; then
    KERNEL_HEADERS="linux-hardened-headers"
  else
    echo "[omarchy] Could not infer kernel headers package from installed kernels."
    echo "[omarchy] uname -r: $(uname -r)"
    echo "[omarchy] Skipping NVIDIA to avoid DKMS/mkinitcpio failures."
    exit 0
  fi

  FLAVOR="${OMARCHY_NVIDIA_FLAVOR:-proprietary}"

  # Default: proprietary DKMS (most compatible across kernels)
  DRIVER_PKG="nvidia-dkms"
  UTILS_PKG="nvidia-utils"
  LIB32_UTILS_PKG="lib32-nvidia-utils"
  EXTRA_PKGS=(libva-nvidia-driver)

  # Optional: open kernel modules only if explicitly requested
  if [ "${FLAVOR}" = "open" ]; then
    DRIVER_PKG="nvidia-open-dkms"
  fi

  # Legacy 580xx branch is opt-in only (and may require AUR on many systems)
  if [ "${OMARCHY_NVIDIA_LEGACY_580XX:-0}" = "1" ]; then
    DRIVER_PKG="nvidia-580xx-dkms"
    UTILS_PKG="nvidia-580xx-utils"
    LIB32_UTILS_PKG="lib32-nvidia-580xx-utils"
    EXTRA_PKGS=()
  fi

  PACKAGES=("${DRIVER_PKG}" "${UTILS_PKG}" "${LIB32_UTILS_PKG}" "${EXTRA_PKGS[@]}")

  # Clean up any stale mkinitcpio NVIDIA drop-in from a previous failed/partial install.
  # If it exists while modules aren't built yet, mkinitcpio will fail with "module not found".
  sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf 2>/dev/null || true

  # If we're installing proprietary DKMS, try to remove the open module stack to avoid confusion.
  if [ "$DRIVER_PKG" = "nvidia-dkms" ]; then
    sudo pacman -Rns --noconfirm nvidia-open-dkms nvidia-open 2>/dev/null || true
  fi

  # Avoid linux/linux-headers drift (common after interrupted installs/upgrades).
  # If they differ, install both together so pacman aligns versions (may upgrade or downgrade).
  LINUX_VER="$(pacman -Q linux 2>/dev/null | awk '{print $2}')"
  LINUX_HEADERS_VER="$(pacman -Q linux-headers 2>/dev/null | awk '{print $2}')"
  if [ -n "$LINUX_VER" ] && [ -n "$LINUX_HEADERS_VER" ] && [ "$LINUX_VER" != "$LINUX_HEADERS_VER" ]; then
    echo "[omarchy] linux ($LINUX_VER) and linux-headers ($LINUX_HEADERS_VER) are out of sync; aligning."
    omarchy-pkg-add linux linux-headers || true
  fi

  # Install headers + DKMS + driver stack
  omarchy-pkg-add dkms "${KERNEL_HEADERS}" "${PACKAGES[@]}"

  # Configure modprobe for early KMS
  sudo tee /etc/modprobe.d/nvidia.conf <<EOF >/dev/null
options nvidia_drm modeset=1
EOF

  # Build NVIDIA modules for the newest installed kernel.
  # During an install or full system upgrade, pacman can remove the *running*
  # kernel's /usr/lib/modules/<uname -r>/ tree, which makes DKMS fail with:
  #   "Missing <kver> kernel modules tree for module nvidia/..."
  # So we target the latest modules directory instead of relying on uname -r.
  LATEST_KVER="$(ls -1 /usr/lib/modules 2>/dev/null | sort -V | tail -1)"
  if [ -n "$LATEST_KVER" ]; then
    # Ensure headers are present for the target kernel.
    # When linux/linux-headers get out of sync (common after interrupted upgrades),
    # DKMS will succeed for *no* kernel and mkinitcpio will complain about missing modules.
    if [ ! -e "/usr/lib/modules/$LATEST_KVER/build" ]; then
      echo "[omarchy] Missing kernel headers for $LATEST_KVER (no /usr/lib/modules/$LATEST_KVER/build)."
      echo "[omarchy] Attempting to install headers: $KERNEL_HEADERS"
      omarchy-pkg-add "$KERNEL_HEADERS" || true
    fi

    echo "[omarchy] DKMS autoinstall for kernel: $LATEST_KVER"
    sudo dkms autoinstall -k "$LATEST_KVER" || true
  else
    echo "[omarchy] Warning: could not determine latest kernel version from /usr/lib/modules"
  fi

  # Only force early-loading modules in mkinitcpio if they actually exist.
  # Otherwise mkinitcpio fails with "module not found: nvidia".
  if [ -n "$LATEST_KVER" ] && /usr/bin/modinfo -k "$LATEST_KVER" nvidia >/dev/null 2>&1; then
    sudo tee /etc/mkinitcpio.conf.d/nvidia.conf <<EOF >/dev/null
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
  else
    echo "[omarchy] NVIDIA kernel module not present for $LATEST_KVER yet; not adding mkinitcpio MODULES drop-in."
    sudo rm -f /etc/mkinitcpio.conf.d/nvidia.conf 2>/dev/null || true
  fi

  # Rebuild initramfs after installing / configuring NVIDIA
  sudo mkinitcpio -P

  # Add NVIDIA environment variables (idempotent-ish: append once)
  mkdir -p "$HOME/.config/hypr"
  touch "$HOME/.config/hypr/envs.conf"
  if ! grep -q "^# NVIDIA" "$HOME/.config/hypr/envs.conf"; then
    cat >>"$HOME/.config/hypr/envs.conf" <<'EOF'

# NVIDIA
env = NVD_BACKEND,direct
env = LIBVA_DRIVER_NAME,nvidia
env = __GLX_VENDOR_LIBRARY_NAME,nvidia
EOF
  fi
fi

