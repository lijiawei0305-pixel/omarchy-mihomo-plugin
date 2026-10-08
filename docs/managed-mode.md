# Managed mode

This document describes the managed profile and configuration layer in the
Omarchy Mihomo plugin. It is an architecture reference for maintainers and
contributors; it describes the shipped behavior rather than an implementation
prompt.

## Goals and compatibility

The plugin supports two workflows:

* **Raw Config mode** talks to an already-running Mihomo core. The user owns
  the core process and the hand-written YAML. This remains the default
  compatibility path and does not require the manager binary.
* **Managed mode** adds profiles, subscriptions, generated runtime YAML,
  overrides, custom rules, managed-core setup, and diagnostics. It is opt-in.

The manager is a control plane for configuration semantics. `mihomo-ctl`
continues to own controller discovery and runtime REST operations.
`mihomo-setup` performs explicit bootstrap and capability actions; it does not
silently install a core or change firewall policy.

```text
Omarchy shell
    │
 Service.qml
 ┌──┼──────────────┐
 │  │              │
ctl manager      setup
 │    │            │
 ▼    ├─ profiles │
core  ├─ compiler │
      ├─ rules    │
      └─ doctor   │
           │      │
           └──────┴── Mihomo core
```

The QML service treats a missing manager as a managed-mode setup state. It
must not prevent the plugin from loading or disable raw controller pages.

## Storage

The manager stores private state below the user's configuration/data roots.
The profile store has a private directory and validates profile IDs before
using them as path components. Directories are created with mode `0700` and
files with mode `0600`.

Each profile has a source configuration and metadata. A subscription profile
also records its URL, conditional-fetch metadata such as ETag, and the last
successful update. The URL is not used as a filename. Active-profile state,
managed settings, overrides, and custom rules are separate state from the
source document.

Writes follow this pattern:

1. acquire the store lock;
2. create a temporary file in the destination directory;
3. write and `fsync` the contents;
4. apply the private mode;
5. rename the temporary file atomically;
6. `fsync` the parent directory;
7. release the lock.

Partial files and unvalidated path names are never treated as profiles.

## Source, runtime, and overrides

Source YAML is preserved as imported or edited. The manager never uses the
active runtime file as the source of truth. Generated runtime configuration is
written to its own path, and overrides remain independently editable:

```text
profile source
      │
      ├── global override
      ├── profile override
      └── custom rules
              │
              ▼
       generated runtime
```

This separation lets a user update a subscription without losing local
settings and lets the UI show source, runtime, and override state separately.

## Compile pipeline

The compiler produces a candidate document in a deterministic order:

```text
Source YAML
   ↓
Global override
   ↓
Profile override
   ↓
Custom rules
   ↓
Manager-owned settings
   ↓
Runtime YAML candidate
```

Later layers intentionally own only their documented fields. Existing source
values that are not managed remain intact. Managed listener normalization
removes a source `port` or `socks-port` when it duplicates the managed
`mixed-port`; different ports remain explicit, and `redir-port`/`tproxy-port`
are not implicitly changed.

Managed TUN defaults to `enable: false` and `stack: gvisor`. The compiler does
not enable TUN as a side effect of importing a profile. Managed mode also forces
`tun.auto-redirect: false`, so enabling TUN does not install host firewall
redirect rules. A downloaded subscription cannot set `allow-lan`, `bind-address`,
the external controller, or a non-loopback inbound `listen` address. User
overrides can still set `allow-lan`. The stored subscription source is not
rewritten.

## Apply transaction

Changing the active profile or applying an override is transactional:

```text
compile
  ↓
validate candidate with mihomo -t
  ↓
backup active runtime and state
  ↓
write candidate atomically
  ↓
apply/reload through the controller
  ↓
verify controller response and effective state
  ↓
commit active-profile metadata
```

The existing active runtime is not replaced when compilation or validation
fails. If a later step fails, the manager restores the runtime, metadata, and
profile binding from the transaction snapshot. The same rollback contract
applies to controller validation failure, state-write failure, an active
subscription update, and binding failure.

## Subscription fetching and security

Subscription fetching is deliberately constrained:

* only `http` and `https` URLs are accepted;
* URL userinfo is rejected;
* localhost, `.localhost`, `.local`, loopback, RFC1918/private, link-local,
  and unspecified addresses are rejected;
* DNS results are checked before connecting;
* every redirect destination is checked and redirect count is bounded;
* shared, documentation, benchmarking, and transition addresses that embed a blocked IPv4 address are rejected, along with the metadata hostname;
* the test-only loopback switch does not permit LAN or link-local destinations;
* requests have a 30-second timeout and a 16 MiB response limit;
* ETag/conditional requests may avoid downloading an unchanged subscription;
* errors redact subscription URLs and their tokens before returning or logging
  them.

These checks apply to subscription URLs and redirect destinations, including
DNS-resolved addresses. The manager does not provide a private-network
allowlist override through the UI.

## TUN, firewall, and privileges

Diagnostics reports whether TUN prerequisites are available. If UFW or
firewalld is active, `system` and `mixed` TUN stacks produce a compatibility
warning or preflight failure. The plugin never disables or stops a user's
firewall.

When a plugin-managed core needs capabilities, setup resolves the executable
from the running Mihomo PID, verifies it, locates `pkexec` and `setcap`, and
requests only:

```text
pkexec setcap cap_net_admin,cap_net_raw=+ep <mihomo-binary>
```

The command is followed by `getcap` verification. A service restart is allowed
only after confirming that the service is plugin-managed. Setup never invokes
a root shell and never changes an externally managed core.

## Raw mode and managed mode in the UI

Raw mode keeps the existing Home, Proxies, Config, Connections, and Rules
pages usable with the discovered controller. Node selection, delay checks,
connection close actions, provider refresh, system proxy, and raw-config TUN
continue to operate through `mihomo-ctl`.

Managed mode adds Profiles and Diagnostics. Profile switching, subscription
updates, overrides, custom rules, generated configuration, and managed-core
actions go through `mihomo-manager` or the explicit setup helper. A manager
installation error is shown as setup state, not as a reason to hide raw-mode
features.

## Manager distribution

The manager is distributed as release assets from this repository:

```text
GitHub Release
  ├─ omarchy-mihomo-manager-linux-amd64
  ├─ omarchy-mihomo-manager-linux-arm64
  └─ SHA256SUMS
```

`bin/install-manager` selects the architecture, downloads the selected release,
verifies its checksum, and installs it with mode `0700`. The
`OMARCHY_MIHOMO_MANAGER_REPO` environment variable remains available for
development and testing. A release containing the manager assets must exist
before managed setup is advertised after a merge.
