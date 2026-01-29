# Post-install validation: fail fast if key boot artifacts are broken.

set -euo pipefail

echo "Validating install health..."

# Basic kernel/header sanity (common DKMS breakage cause)
LINUX_VER="$(pacman -Q linux 2>/dev/null | awk '{print $2}')"
LINUX_HEADERS_VER="$(pacman -Q linux-headers 2>/dev/null | awk '{print $2}')"
if [[ -n "$LINUX_VER" && -n "$LINUX_HEADERS_VER" && "$LINUX_VER" != "$LINUX_HEADERS_VER" ]]; then
  echo "[omarchy] ERROR: linux ($LINUX_VER) and linux-headers ($LINUX_HEADERS_VER) are out of sync."
  echo "[omarchy] Fix with: sudo pacman -S linux linux-headers"
  exit 1
fi

# Ensure /boot has a limine.conf
if [[ ! -f /boot/limine.conf ]]; then
  echo "[omarchy] ERROR: /boot/limine.conf missing"
  exit 1
fi

# Ensure compat symlink exists and is not a conflicting real file
sudo mkdir -p /boot/limine
if [[ -e /boot/limine/limine.conf && ! -L /boot/limine/limine.conf ]]; then
  echo "[omarchy] ERROR: /boot/limine/limine.conf exists as a real file (conflicts with /boot/limine.conf)."
  echo "[omarchy] Remove it or make it a symlink to /boot/limine.conf."
  exit 1
fi
sudo ln -sf /boot/limine.conf /boot/limine/limine.conf

# Remove known conflicting legacy config locations (best effort)
sudo rm -f /boot/EFI/limine/limine.conf /boot/EFI/BOOT/limine.conf 2>/dev/null || true

# Ensure limine-update succeeds and doesn't warn about conflicting configs
if command -v limine-update >/dev/null 2>&1; then
  LIMINE_OUT="$(sudo limine-update 2>&1)" || {
    echo "[omarchy] ERROR: limine-update failed"
    echo "$LIMINE_OUT"
    exit 1
  }
  if echo "$LIMINE_OUT" | grep -q "Detected conflicting config"; then
    echo "[omarchy] ERROR: limine-update detected conflicting configs"
    echo "$LIMINE_OUT"
    exit 1
  fi
else
  echo "[omarchy] ERROR: limine-update not found"
  exit 1
fi

# Ensure mkinitcpio succeeds. We treat mkinitcpio failures as fatal because they lead to non-bootable UKIs.
MKINIT_OUT="$(sudo mkinitcpio -P 2>&1)" || {
  echo "[omarchy] ERROR: mkinitcpio -P failed"
  echo "$MKINIT_OUT"
  exit 1
}
if echo "$MKINIT_OUT" | grep -qE "==> ERROR:|mkinitcpio failed"; then
  echo "[omarchy] ERROR: mkinitcpio reported errors"
  echo "$MKINIT_OUT"
  exit 1
fi

echo "Validation: OK"
