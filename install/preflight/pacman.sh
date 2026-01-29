if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  # Install build tools
  sudo pacman -S --needed --noconfirm base-devel

  # Configure pacman
  if [[ ${OMARCHY_MIRROR:-} == "edge" ]] ; then
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman-edge.conf /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-edge /etc/pacman.d/mirrorlist
  else
    sudo cp -f ~/.local/share/omarchy/default/pacman/pacman-stable.conf /etc/pacman.conf
    sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-stable /etc/pacman.d/mirrorlist
  fi

  sudo pacman-key --recv-keys 40DFB630FF42BCFFB047046CF0134EE680CAC571 --keyserver keys.openpgp.org
  sudo pacman-key --lsign-key 40DFB630FF42BCFFB047046CF0134EE680CAC571

  sudo pacman -Sy
  sudo pacman -S --noconfirm --needed omarchy-keyring

  # Refresh package databases
  sudo pacman -Syy --noconfirm

  # Refuse to proceed if mirrors/repos would downgrade the kernel.
  # This is a strong signal of stale mirrors or repo mismatch and frequently leads
  # to linux/linux-headers drift + DKMS failures during install.
  if sudo pacman -Syu --print 2>/dev/null | grep -qE '^:: .*downgrading linux '; then
    echo "[omarchy] Refusing to proceed: pacman wants to downgrade 'linux'."
    echo "[omarchy] Fix your mirrorlist/repo config (stale mirrors), then rerun."
    echo "[omarchy] If you *really* want to allow this, set OMARCHY_ALLOW_KERNEL_DOWNGRADE=1."
    if [[ "${OMARCHY_ALLOW_KERNEL_DOWNGRADE:-0}" != "1" ]]; then
      exit 1
    fi
  fi

  # Full upgrade
  sudo pacman -Syu --noconfirm

  # Ensure we can mount the EFI System Partition (vfat) reliably
  sudo pacman -S --noconfirm --needed dosfstools
fi
