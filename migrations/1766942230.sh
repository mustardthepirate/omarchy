echo "Migrate legacy NVIDIA GPUs to nvidia-580xx driver (if needed)"

# Only apply to legacy NVIDIA GPUs that require 580xx branch.
# If we can't positively identify that, do nothing.
if ! lspci | grep -qi "NVIDIA"; then
  exit 0
fi

# Crude but safe: only proceed if user explicitly opts in
if [ "${OMARCHY_NVIDIA_LEGACY_580XX:-0}" != "1" ]; then
  echo "[omarchy] Skipping 580xx legacy NVIDIA migration (set OMARCHY_NVIDIA_LEGACY_580XX=1 to enable)."
  exit 0
fi


# Only migrate GTX 9xx or 10xx (Pascal/Maxwell)
NVIDIA="$(lspci | grep -i 'nvidia')"
if echo "$NVIDIA" | grep -qE "GTX 9|GTX 10"; then
  if ! pacman -Qq | grep -qE '^linux(-[a-z0-9]+)?-headers$'; then
    echo "Error: no linux headers package installed (required for DKMS drivers). Please install the appropriate headers and re-run this migration."
    exit 1
  fi

  # Piping yes to override existing packages
  yes | sudo pacman -S nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils

  # Verify packages were installed
  if ! pacman -Qq nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils &>/dev/null; then
    echo "Error: NVIDIA 580xx driver packages failed to install"
    exit 1
  fi
fi
