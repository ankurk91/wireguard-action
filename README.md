<p align="center">
  <img src=".github/banner.jpg" alt="WireGuard GitHub Action" width="100%">
</p>

# WireGuard VPN Action

[![test](https://github.com/ankurk91/wireguard-action/actions/workflows/test.yaml/badge.svg)](https://github.com/ankurk91/wireguard-action/actions)
[![lint](https://github.com/ankurk91/wireguard-action/actions/workflows/lint.yaml/badge.svg)](https://github.com/ankurk91/wireguard-action/actions)

A GitHub Action that installs the WireGuard client on an Ubuntu runner and brings up a VPN tunnel from a config you
supply. The tunnel is torn down automatically when the job ends.

## Setup

1. Get a WireGuard client config from your VPN server — the whole `wg0.conf` file:

```ini
[Interface]
PrivateKey = <client private key>
Address = 10.0.0.2/32

[Peer]
PublicKey = <server public key>
AllowedIPs = 0.0.0.0/0
Endpoint = vpn.example.com:51820
PersistentKeepalive = 25
```

2. Add it as a repository secret. Name it `WIREGUARD_CONFIG` and paste the entire file contents.

> [!WARNING]
> Never commit the config or pass it as a plain string — it contains your private key.

## Usage

```yaml
name: Test WireGuard

on:
  workflow_dispatch:

jobs:
  wireguard:
    runs-on: ubuntu-latest

    steps:
      - name: Connect to WireGuard VPN
        uses: ankurk91/wireguard-action@v1
        with:
          config: ${{ secrets.WIREGUARD_CONFIG }}

      # Everything from here on is routed through the VPN.
      - name: Do work behind the VPN
        run: curl -4 -s https://api.ipify.org
```

There is no disconnect step to add.

## Inputs

| Input         | Required | Default     | Description                                                                 |
|---------------|----------|-------------|-----------------------------------------------------------------------------|
| `config`      | **yes**  | —           | Full contents of the WireGuard config file. Always pass this from a secret. |
| `interface`   | no       | `wg-github` | Interface name. Config is written to `/etc/wireguard/<interface>.conf`.     |
| `diagnostics` | no       | `false`     | Print the tunnel state to the job log. See [Diagnostics](#diagnostics).     |

## Requirements

An Ubuntu runner (`ubuntu-latest`, `ubuntu-24.04`, `ubuntu-26.04`, or self-hosted Ubuntu).

**Your config must be IPv4 only.** GitHub-hosted runners have no IPv6 connectivity, so any IPv6 settings will make the
tunnel fail to start. Remove them before adding the secret:

- `Address` — drop the IPv6 address, keep only the IPv4 one (e.g. `Address = 10.0.0.2/32`)
- `AllowedIPs` — drop `::/0`, keep only `0.0.0.0/0`
- `DNS` — drop any IPv6 resolvers
- `Endpoint` — must be an IPv4 address, or a hostname that resolves to one

## Notes

If your config routes all traffic (`AllowedIPs = 0.0.0.0/0`), the action also confirms the tunnel actually reached the
peer and fails the step if it did not — so a dead VPN stops the job here instead of breaking a later step for no
apparent reason. Split tunnels are left unchecked, since there is no way to tell what they were meant to reach.

## Diagnostics

With `diagnostics: true` the action adds a collapsed **WireGuard diagnostics** group to the job log holding the public
IP before and after connecting, `wg show`, the interface addresses and the routing table.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## License

[MIT](LICENSE)
