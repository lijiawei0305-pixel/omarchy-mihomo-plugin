# Mihomo

Omarchy bar plugin: a control panel for the mihomo core. Left nav rail plus a
right-hand page, covering **Home / Proxies / Config / Connections / Rules**.

Talks to mihomo's external controller (REST API) directly. It does **not**
depend on Clash Verge or any other GUI client. The core alone is enough.

The UI defaults to **English**. Switch to Chinese with the EN / 中文 buttons
in the sidebar or on the Config page.

## Pages

| Page | What it shows | APIs |
|------|----------------|------|
| Home | Current node (group / node, latency, chain), read-only network settings, proxy mode, traffic | `/version` `/configs` `/proxies` `/traffic` `/memory` |
| Proxies | Proxy groups, expand nodes, switch, group or single-node latency tests | `/proxies` `/proxies/{name}` `/group/{name}/delay` |
| Config | Hand-written yaml path / stats, reload the core, open the editor; rule providers can be refreshed | `configinfo` `PUT /configs` `/providers/rules` |
| Connections | Active connections, up/down, chain and matched rule; filter, close one, close all | `/connections` |
| Rules | Every rule from the config; filter by domain / type / target | `/rules` |

Writes (switch node, switch mode, latency test, close connections, update a
provider) go to the running core. Other front-ends see the same state.

## Language

Default is English. The EN / 中文 switch is in the sidebar footer and on the
Config page. The choice is stored in `~/.config/omarchy-mihomo/ui` and survives
restarts:

```
language = en
```

Use `zh` for Chinese.

## Endpoint discovery

The panel never hardcodes an address. Every `bin/mihomo-ctl` call probes in
order and uses the first hit:

1. `~/.config/omarchy-mihomo/config` — manual override
2. Flags on the running core — `-ext-ctl` / `-ext-ctl-unix` / `-secret`
3. The yaml that core was started with — `external-controller` / `external-controller-unix` / `secret`
4. `127.0.0.1:9090`, no secret — mihomo's default

So it finds the core whether it listens on a TCP port or a Unix socket, with or
without a secret. Switching to a standalone mihomo unit needs no plugin config.

To pin the endpoint yourself, create `~/.config/omarchy-mihomo/config`:

```
endpoint = 127.0.0.1:9090
# or a unix socket:
# socket = /run/mihomo/mihomo.sock
secret = your-secret
```

Check what was resolved:

```bash
~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo/bin/mihomo-ctl endpoint
```

## Keyboard

With the panel open (`Esc` closes, `Tab` moves to the next panel):

| Key | Action |
|-----|--------|
| `1` – `5` | Jump to Home / Proxies / Config / Connections / Rules |
| `←` `→` `h` `l` | Previous / next page |
| `↑` `↓` `j` `k` | Scroll the current page |
| `/` | Focus the filter (Connections, Rules) |
| `r` | Refresh the current page |

On the Proxies page, left-click a node to switch, right-click to test that
node's latency.

## Install

```bash
git clone https://github.com/lijiawei0305-pixel/omarchy-mihomo-plugin.git
cd omarchy-mihomo-plugin
./deploy
omarchy plugin enable io.github.leeyiwei0305.mihomo
omarchy bar move io.github.leeyiwei0305.mihomo --section right
```

`./deploy` validates the manifest, syncs to
`~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo/`, and restarts the
shell. Hot reload is unreliable; a restart is the sure way.

## Uninstall

```bash
omarchy plugin disable io.github.leeyiwei0305.mihomo
rm -rf ~/.config/omarchy/plugins/io.github.leeyiwei0305.mihomo
```

## Dependencies

`curl`, `bash`. The core needs its external controller enabled (it is on by
default).

## Notes

- Network settings (ports, TUN, LAN, IPv6) are **read-only**. Change the yaml
  and reload the core; they are not meant to be flipped from a bar panel.
- Only `Selector` groups accept a manual node. `URLTest` / `Fallback` /
  `LoadBalance` are chosen by the core, and the API rejects a forced pick.
- The Config page is that handwritten yaml. Nodes live under `proxies:`; there
  is no subscription fetch. Rule providers can still be refreshed by hand.
  After you save the file, use **Reload config** — no service restart needed.
- While the panel is closed it only does a light poll every 30 seconds. Opening
  it starts the `/traffic` and `/memory` streams and fetches whatever the
  current page needs.
