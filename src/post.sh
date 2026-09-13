#!/usr/bin/env bash
# Stop the tunnel and remove its config. Never fails the job.
set -uo pipefail

WG_INTERFACE="${INPUT_INTERFACE:-wg-github}"
WG_CONF_PATH="/etc/wireguard/${WG_INTERFACE}.conf"

echo "=== Stopping $WG_INTERFACE ==="

# An invalid name means the main step never got as far as writing a config, so
# there is nothing here to undo. Bail out before rm sees the untrusted path.
if ! [[ $WG_INTERFACE =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]]; then
  echo "invalid interface name, nothing to clean up"
  exit 0
fi

# Whenever the main step failed before `wg-quick up`, the interface was never
# created and `wg-quick down` fails as the normal outcome, so check it exists
# first rather than warning on every already-failing run. `wg show` resolves the
# name for both kernel and userspace interfaces, which `ip link show` does not.
if ! command -v wg-quick > /dev/null; then
  echo "wireguard-tools is not installed, nothing to stop"
elif ! sudo wg show "$WG_INTERFACE" > /dev/null 2>&1; then
  echo "$WG_INTERFACE is not up, nothing to stop"
elif ! sudo wg-quick down "$WG_INTERFACE"; then
  echo "::warning::could not bring down $WG_INTERFACE, it may still be up with its routes in place"
fi

# Worth a warning even though the job carries on: on a self-hosted runner this
# file outlives the job with the private key from this run still in it.
if ! sudo rm -f "$WG_CONF_PATH"; then
  echo "::warning::could not remove $WG_CONF_PATH, it still holds this run's private key"
fi

echo "Wireguard cleanup finished."

exit 0
