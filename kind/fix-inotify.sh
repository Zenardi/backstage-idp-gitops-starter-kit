#!/usr/bin/env bash
# fix-inotify.sh — raise inotify limits on the host for KIND + Crossplane
#
# Run this ONCE on any host/WSL session before or after cluster creation.
# Without these limits, Crossplane controller pods crash with:
#   "cannot start controller manager: too many open files"
#
# Usage:
#   chmod +x kind/fix-inotify.sh
#   ./kind/fix-inotify.sh

set -euo pipefail

echo "Current inotify limits:"
echo "  max_user_instances : $(cat /proc/sys/fs/inotify/max_user_instances)"
echo "  max_user_watches   : $(cat /proc/sys/fs/inotify/max_user_watches)"
echo ""

echo "Applying new limits..."
sudo sysctl -w fs.inotify.max_user_instances=1280
sudo sysctl -w fs.inotify.max_user_watches=655360

echo ""
echo "Making permanent in /etc/sysctl.d/99-kind.conf ..."
if ! grep -q "max_user_instances=1280" /etc/sysctl.d/99-kind.conf 2>/dev/null; then
  echo "fs.inotify.max_user_instances=1280" | sudo tee -a /etc/sysctl.d/99-kind.conf
  echo "fs.inotify.max_user_watches=655360" | sudo tee -a /etc/sysctl.d/99-kind.conf
  echo "Written to /etc/sysctl.d/99-kind.conf"
else
  echo "/etc/sysctl.d/99-kind.conf already has the settings — skipping"
fi

echo ""
echo "New limits:"
echo "  max_user_instances : $(cat /proc/sys/fs/inotify/max_user_instances)"
echo "  max_user_watches   : $(cat /proc/sys/fs/inotify/max_user_watches)"
echo ""
echo "Done! Crossplane pods will self-heal on next backoff restart."
echo "Watch: kubectl get pods -n crossplane-system -w"
