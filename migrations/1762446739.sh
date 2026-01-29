echo "Remove alternative limine.conf files"

if omarchy-cmd-present limine; then
  # Only remove /boot/limine/limine.conf if it's a real file (not our symlink)
  if [ -e /boot/limine/limine.conf ] && [ ! -L /boot/limine/limine.conf ]; then
    sudo rm -f /boot/limine/limine.conf
  fi


  sudo rm -f /boot/EFI/limine/limine.conf
  sudo rm -f /boot/EFI/BOOT/limine.conf

  # Only remove /boot/limine/limine.conf if it's a real file (not our symlink)
  if [ -e /boot/limine/limine.conf ] && [ ! -L /boot/limine/limine.conf ]; then
    sudo rm -f /boot/limine/limine.conf
  fi
fi
