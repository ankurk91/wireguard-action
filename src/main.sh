#!/usr/bin/env bash
# Install WireGuard and bring up the tunnel.
set -euo pipefail

WG_INTERFACE="${INPUT_INTERFACE:-wg-github}"
WG_CONF_PATH="/etc/wireguard/${WG_INTERFACE}.conf"
WG_DIAGNOSTICS="${INPUT_DIAGNOSTICS:-false}"

# The same pattern wg-quick accepts. Checking it here too keeps the name from
# escaping /etc/wireguard when the config path is built from it above.
if ! [[ $WG_INTERFACE =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]]; then
  echo "::error::input 'interface' is not a valid interface name: '$WG_INTERFACE'"
  exit 1
fi

if [ -z "${INPUT_CONFIG:-}" ]; then
  echo "::error::input 'config' is empty"
  exit 1
fi

case "$WG_DIAGNOSTICS" in
  true | false) ;;
  *)
    echo "::error::input 'diagnostics' must be 'true' or 'false', got '$WG_DIAGNOSTICS'"
    exit 1
    ;;
esac

diagnostics_enabled() {
  [ "$WG_DIAGNOSTICS" = 'true' ]
}

public_ip() {
  curl -4 -s --connect-timeout 5 --max-time 10 https://icanhazip.com || echo 'unavailable'
}

# Everything here describes the network the runner is now on: the peer's
# endpoint and public key, the tunnel's addresses, the full routing table. On a
# self-hosted runner that is internal detail, and a job log is readable by more
# people than the config is, so it is printed only when asked for.
print_diagnostics() {
  echo '::group::WireGuard diagnostics'

  echo "Public IP before VPN: ${public_ip_before:-unavailable}"
  echo "Public IP after VPN: $(public_ip)"

  echo
  echo "--- wg show $WG_INTERFACE ---"
  sudo wg show "$WG_INTERFACE"

  echo
  echo "--- $WG_INTERFACE IP address ---"
  ip -4 addr show "$WG_INTERFACE"

  echo
  echo '--- Routes ---'
  ip route

  echo '::endgroup::'
}

# `wg show <interface> dump` prints the interface on the first line and each peer
# on the lines after it, tab separated. For the first peer, field 4 is its
# allowed-ips and field 5 the time of its last handshake, or 0 for never.
peer_allowed_ips() {
  sudo wg show "$WG_INTERFACE" dump | sed -n '2p' | cut -f4
}

peer_last_handshake() {
  sudo wg show "$WG_INTERFACE" dump | sed -n '2p' | cut -f5
}

# Read here, where it still means something, and held until the group below can
# print it next to the address the tunnel ends up giving us.
if diagnostics_enabled; then
  public_ip_before="$(public_ip)"
fi

# apt is not the only thing on the runner that wants the dpkg lock - the image
# boots with unattended-upgrades - so wait for it rather than treating a busy
# lock as a failed install.
install_wireguard_tools() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    --no-install-recommends \
    -o Dpkg::Use-Pty=0 \
    -o Dpkg::Lock::Timeout=60 \
    -o Dpkg::Options::=--force-unsafe-io \
    wireguard-tools
}

echo "=== Installing wireguard-tools ==="
if command -v wg-quick > /dev/null; then
  echo "already installed, skipping"
else
  # Install straight from the indexes already on the image, so the usual run
  # skips the several seconds an `apt-get update` costs. Those indexes are a
  # snapshot from the image build, so the version they name can already be gone
  # from the archive - and nothing local can tell: the index stays perfectly
  # valid and apt only 404s once it asks the archive for the file. So the check
  # is the attempt itself, and the refresh happens only when one was needed.
  if ! install_wireguard_tools; then
    echo 'install failed, refreshing the apt indexes and retrying'
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      -o Dpkg::Use-Pty=0 \
      -o Dpkg::Lock::Timeout=60

    if ! install_wireguard_tools; then
      echo "::error::cannot install wireguard-tools, even with refreshed apt indexes"
      exit 1
    fi
  fi
fi

echo "=== Writing $WG_CONF_PATH ==="
sudo mkdir -p /etc/wireguard

# Create the file empty and already private, then write into it. `tee` would
# create it under root's umask instead - 0644 on the runner images - leaving the
# private key world-readable at a documented path until the mode was corrected.
sudo install -m 600 /dev/null "$WG_CONF_PATH"
printf '%s\n' "$INPUT_CONFIG" | sudo tee "$WG_CONF_PATH" > /dev/null

echo "=== Starting $WG_INTERFACE ==="
sudo wg-quick up "$WG_INTERFACE"

if diagnostics_enabled; then
  print_diagnostics
fi

# `wg-quick up` succeeds even when the peer is unreachable, and WireGuard stays
# silent until it has traffic to send, so an unhealthy tunnel looks fine here.
# Sending something through it is what settles the question - and only a peer
# routing the whole internet gives us somewhere to send it. A split tunnel
# carries nothing in particular, so there is nothing to conclude from it.
case "$(peer_allowed_ips)" in
  *0.0.0.0/0*)
    echo
    echo "=== Verifying the handshake ==="

    # Addressed to TEST-NET-1, which is reserved and routed nowhere: with the
    # whole internet inside the tunnel the packet still leaves through the
    # interface and starts the handshake, while no third party takes part in a
    # check that runs on every job. Nothing answers, so the failure is expected.
    curl -s --max-time 2 -o /dev/null http://192.0.2.1 || true

    # Read the field as a number rather than comparing it to '0'. It comes back
    # empty when the query itself failed - `wg show` erroring, the interface
    # gone - and an empty string is not '0', so a failed query would otherwise
    # be taken for a handshake and the check would pass the very tunnel it is
    # there to catch.
    for _ in $(seq 5); do
      last_handshake="$(peer_last_handshake)"

      if [[ $last_handshake =~ ^[0-9]+$ ]] && [ "$last_handshake" -gt 0 ]; then
        handshaked=1
        break
      fi

      sleep 1
    done

    if [ -z "${handshaked:-}" ]; then
      echo "::error::the tunnel is up but never handshaked with the peer. Check Endpoint, the keys, and that the peer's UDP port is reachable."
      exit 1
    fi

    echo "handshake confirmed, the tunnel is carrying traffic"
    ;;
  *)
    echo
    echo "=== Split tunnel, skipping the handshake check ==="
    ;;
esac
