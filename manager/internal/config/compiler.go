package config

import (
	"fmt"
	"os"
	"strings"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/policy"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/profile"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/rules"
)

type Compiler struct {
	Settings  profile.Settings
	Protected map[string]any
}

type CompileInput struct {
	Source          []byte
	GlobalOverride  []byte
	ProfileOverride []byte
	CustomRules     []rules.Rule
	Bindings        policy.Bindings
	Settings        profile.Settings
	Protected       map[string]any
	// UntrustedSource is set for subscription documents. Local imports and
	// user overrides remain authoritative for fields this layer removes.
	UntrustedSource bool
}

func MergeLayers(source, global, override []byte) (map[string]any, error) {
	src, e := Parse(source)
	if e != nil {
		return nil, fmt.Errorf("parse source: %w", e)
	}
	g, e := ParseOptional(global)
	if e != nil {
		return nil, fmt.Errorf("parse global override: %w", e)
	}
	p, e := ParseOptional(override)
	if e != nil {
		return nil, fmt.Errorf("parse profile override: %w", e)
	}
	return DeepMerge(DeepMerge(src, g), p), nil
}

func (c Compiler) Compile(input CompileInput) ([]byte, error) {
	src, err := Parse(input.Source)
	if err != nil {
		return nil, fmt.Errorf("parse source: %w", err)
	}
	if input.UntrustedSource {
		sanitizeUntrustedSource(src)
	}
	global, err := ParseOptional(input.GlobalOverride)
	if err != nil {
		return nil, fmt.Errorf("parse global override: %w", err)
	}
	profileOverride, err := ParseOptional(input.ProfileOverride)
	if err != nil {
		return nil, fmt.Errorf("parse profile override: %w", err)
	}
	out := DeepMerge(DeepMerge(src, global), profileOverride)
	updated, err := rules.Inject(out, input.CustomRules, input.Bindings)
	if err != nil {
		return nil, fmt.Errorf("inject custom rules: %w", err)
	}
	settings := input.Settings
	if settings.DNSManagement == "" && settings.TUNManagement == "" {
		settings = c.Settings
		if input.Settings.Network.MixedPort > 0 {
			settings.Network = input.Settings.Network
		}
	}
	if settings.DNSManagement == "" && settings.TUNManagement == "" {
		defaults := profile.DefaultSettings()
		if settings.Network.MixedPort > 0 {
			defaults.Network = settings.Network
		}
		settings = defaults
	}
	if settings.Network.MixedPort <= 0 {
		// Keep direct compiler callers and pre-network settings files on the
		// same runtime contract as the manager's persisted defaults.
		settings.Network.MixedPort = profile.DefaultSettings().Network.MixedPort
	}
	updated = (Compiler{Settings: settings}).managed(updated)
	protected := input.Protected
	if protected == nil && c.Protected != nil {
		protected = c.Protected
	}
	updated = (Compiler{Protected: protected}).protected(updated)
	return Marshal(updated)
}

// normalizeManagedMixedPortListeners applies the manager-owned mixed-port
// contract after source/global/profile layers have been merged.
//
// Mihomo's mixed-port already accepts both HTTP and SOCKS traffic. Therefore,
// a source-level port or socks-port using the exact same port is redundant and
// must be removed before listener-conflict validation.
//
// Transparent proxy listeners are intentionally not normalized here:
// redir-port and tproxy-port have different semantics from mixed-port and a
// collision with them must remain a validation error.
func normalizeManagedMixedPortListeners(m map[string]any, mixedPort int) {
	if mixedPort <= 0 {
		return
	}

	if configPort(m["port"]) == mixedPort {
		delete(m, "port")
	}

	if configPort(m["socks-port"]) == mixedPort {
		delete(m, "socks-port")
	}

	// Apply the manager-owned value last so source/global/profile overrides
	// cannot silently move the System Proxy endpoint.
	m["mixed-port"] = mixedPort
}

func (c Compiler) managed(m map[string]any) map[string]any {
	out := clone(m).(map[string]any)

	if c.Settings.Network.MixedPort > 0 {
		normalizeManagedMixedPortListeners(out, c.Settings.Network.MixedPort)
	}
	if c.Settings.DNSManagement == "managed" {
		d := map[string]any{"enable": c.Settings.DNS.Enable, "ipv6": c.Settings.DNS.IPv6, "enhanced-mode": c.Settings.DNS.EnhancedMode, "fake-ip-range": c.Settings.DNS.FakeIPRange, "default-nameserver": toAny(c.Settings.DNS.DefaultNameserver), "nameserver": toAny(c.Settings.DNS.Nameserver), "proxy-server-nameserver": toAny(c.Settings.DNS.ProxyServerNameserver), "fake-ip-filter": toAny(c.Settings.DNS.FakeIPFilter)}
		// Managed settings own only the fields exposed by the manager. Keep
		// source/profile fields that Mihomo supports but this version does not
		// model (for example nameserver-policy and fallback).
		out = DeepMerge(out, map[string]any{"dns": d})
	}
	if c.Settings.TUNManagement == "managed" {
		t := map[string]any{
			"enable":                c.Settings.TUN.Enable,
			"stack":                 profile.NormalizeTUNStack(c.Settings.TUN.Stack),
			"auto-route":            c.Settings.TUN.AutoRoute,
			"auto-detect-interface": c.Settings.TUN.AutoDetectInterface,
			"strict-route":          c.Settings.TUN.StrictRoute,
			"dns-hijack":            toAny(c.Settings.TUN.DNSHijack),
			// auto-redirect installs host firewall rules. Managed mode keeps
			// that off; a subscription cannot turn it on by surviving the merge.
			"auto-redirect": false,
		}
		// TUN has the same forward-compatibility requirement: preserve fields
		// such as mtu, auto-redirect, and route include/exclude settings.
		out = DeepMerge(out, map[string]any{"tun": t})
	}
	return out
}
func (c Compiler) protected(m map[string]any) map[string]any {
	out := clone(m).(map[string]any)
	// A nil map means that no running core was available (for example while
	// adding a profile before mihomo starts). Preserve source fields until the
	// manager has a real controller snapshot to enforce.
	if c.Protected == nil {
		return out
	}
	for _, k := range []string{"external-controller", "external-controller-unix", "secret", "external-ui"} {
		delete(out, k)
		if v, ok := c.Protected[k]; ok {
			out[k] = clone(v)
		}
	}
	return out
}
func toAny(s []string) []any {
	a := make([]any, len(s))
	for i, v := range s {
		a[i] = v
	}
	return a
}

// sanitizeUntrustedSource removes control-plane fields from a downloaded
// subscription before user overrides are merged. The stored source document
// is left unchanged.
func sanitizeUntrustedSource(m map[string]any) {
	for _, key := range []string{
		"allow-lan",
		"bind-address",
		"lan-allowed-ips",
		"lan-disallowed-ips",
		"authentication",
		"skip-auth-prefixes",
		"external-controller",
		"external-controller-unix",
		"external-controller-pipe",
		"external-controller-tls",
		"external-controller-cors",
		"secret",
		"external-ui",
		"external-ui-name",
		"external-ui-url",
	} {
		delete(m, key)
	}
	if tun, ok := m["tun"].(map[string]any); ok {
		delete(tun, "auto-redirect")
	}
	sanitizeListeners(m)
}

func sanitizeListeners(m map[string]any) {
	raw, ok := m["listeners"].([]any)
	if !ok {
		return
	}
	for _, item := range raw {
		listener, ok := item.(map[string]any)
		if !ok {
			continue
		}
		listen, ok := listener["listen"].(string)
		if !ok || strings.TrimSpace(listen) == "" || loopbackListen(listen) {
			continue
		}
		listener["listen"] = "127.0.0.1"
	}
}

func loopbackListen(value string) bool {
	switch strings.ToLower(strings.Trim(strings.TrimSpace(value), "[]")) {
	case "127.0.0.1", "localhost", "::1":
		return true
	default:
		return false
	}
}

func ReadProtected(path string) (map[string]any, error) {
	if path == "" {
		return map[string]any{}, nil
	}
	b, e := os.ReadFile(path)
	if e != nil {
		return map[string]any{}, e
	}
	m, e := Parse(b)
	if e != nil {
		return nil, e
	}
	out := map[string]any{}
	for _, k := range []string{"external-controller", "external-controller-unix", "secret", "external-ui"} {
		if v, ok := m[k]; ok {
			out[k] = v
		}
	}
	return out, nil
}
