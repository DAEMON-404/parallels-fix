#!/bin/bash
# Fix + install Parallels Tools 26.4 on Kali 2026 (arm64)
# Root cause: Kali (Debian forky base) removed libfuse2; Parallels' prl_fsd
# shared-folder daemon still links against libfuse.so.2, so the installer's
# mandatory-package check fails and shared folders cannot work.
set -u
SCRATCH="$(cd "$(dirname "$0")" && pwd)"
LOG=/var/log/fix-parallels.log
say() { echo -e "\n==> $*"; }

[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }

say "Step 1/5: Installing libfuse2 (libfuse2t64 from Debian archive)"
if ldconfig -p | grep -Fq 'libfuse.so.2 '; then
    echo "libfuse.so.2 already present, skipping."
else
    dpkg -i "$SCRATCH/libfuse2t64.deb" || { echo "FAILED to install libfuse2t64"; exit 1; }
fi
ldconfig -p | grep -F 'libfuse.so.2' || { echo "libfuse.so.2 still missing"; exit 1; }

say "Step 2/5: Installing binfmt-support (optional dep the installer wants)"
apt-get install -y binfmt-support || echo "WARN: binfmt-support install failed (non-fatal), continuing"

say "Step 3/5: Mounting Parallels Tools CD"
mkdir -p /media/cdrom
if ! mountpoint -q /media/cdrom; then
    mount -o ro /dev/sr0 /media/cdrom || { echo "FAILED to mount /dev/sr0 — in the Parallels menu click Actions > Reinstall Parallels Tools, then rerun this script"; exit 1; }
fi
[ -x /media/cdrom/install ] || [ -f /media/cdrom/install ] || { echo "No install script on CD"; exit 1; }

say "Step 4/5: Running Parallels Tools installer (logging to $LOG)"
bash /media/cdrom/install --install --progress --verbose >"$LOG" 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "Installer exited with code $rc. Last 40 log lines:"
    tail -40 "$LOG"
    exit $rc
fi
tail -5 "$LOG"

say "Step 5/5: Verifying"
systemctl daemon-reload
systemctl enable --now prltoolsd 2>/dev/null || true
sleep 2
systemctl is-active prltoolsd && echo "prltoolsd service: OK" || echo "prltoolsd not active yet (normal before reboot)"
command -v prl_fsd >/dev/null && ldd "$(command -v prl_fsd)" | grep libfuse
echo
echo "DONE. Reboot the VM (sudo reboot) — shared folders will appear under /media/psf/"
echo "Make sure sharing is enabled in Parallels: VM Configuration > Options > Sharing."
