# Troubleshooting

Most of these are quicker to diagnose with the action's diagnostics turned on, which prints `wg show`, the interface
addresses, the routes and the public IP before and after connecting:

```yaml
- uses: ankurk91/wireguard-action@v1
  with:
    config: ${{ secrets.WIREGUARD_CONFIG }}
    diagnostics: true
```

It is off by default — see [Diagnostics](README.md#diagnostics) — so turn it back off once the tunnel works.

## resolvconf: command not found

Your config has a `DNS =` line, and `wg-quick` needs a `resolvconf` implementation to apply it.

On Ubuntu 24.04 and 26.04 the `systemd-resolved` package ships a `resolvconf` compatibility shim at
`/usr/sbin/resolvconf`, so this only comes up where `systemd-resolved` is absent — typically a self-hosted runner or a
container. Either drop the `DNS =` line, or install a provider before connecting:

```yaml
- run: sudo apt-get install -y openresolv
```

## Cannot find device "wg-github"` / `RTNETLINK answers: Operation not supported

The runner's kernel has no WireGuard module. GitHub-hosted Ubuntu runners do; if you hit this on a self-hosted runner or
inside a container, install the `wireguard` kernel module package on the host.

## Public IP didn't change

Your config's `AllowedIPs` doesn't cover the traffic. Use `AllowedIPs = 0.0.0.0/0` to route everything through the
tunnel; a narrower range only routes those destinations. Turn on `diagnostics` to see the IP before and after.

## The job hangs after connecting

`AllowedIPs = 0.0.0.0/0` also routes the runner's connection to GitHub through the VPN. If your VPN blocks that, narrow
`AllowedIPs` to just the hosts you need to reach.

## The tunnel is up but never handshaked with the peer

The interface came up but no packet ever made it to the peer and back, so the tunnel is not carrying traffic. `wg-quick`
cannot detect this on its own — it reports success as soon as the interface exists. Check that:

- `Endpoint` is correct and its UDP port is reachable from the runner
- the server has this client's public key in its peer list
- `PresharedKey` matches on both sides, if you use one

This check only runs for full tunnels (`AllowedIPs = 0.0.0.0/0`).

## Handshake never completes (`latest handshake` stays empty)

Check `Endpoint` is reachable from the runner and that the port is UDP-open, and that the server has this client's
public key in its peer list.

## Error: `IPv6 is disabled` / `Address family not supported by protocol`

Your config has IPv6 settings and the runner has no IPv6 connectivity. Remove the IPv6
`Address`, `AllowedIPs` (`::/0`), and `DNS` entries — see the requirements in the README.

