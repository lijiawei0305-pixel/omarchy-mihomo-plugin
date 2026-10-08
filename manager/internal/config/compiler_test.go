package config

import (
	"fmt"
	"strings"
	"testing"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/policy"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/profile"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/rules"
)

func TestManagedDNSAndTUNAndProtectedFields(t *testing.T) {
	c := Compiler{Settings: profile.DefaultSettings(), Protected: map[string]any{"external-controller": "127.0.0.1:9090", "secret": "keep"}}
	out, e := c.Compile(CompileInput{Source: []byte("mode: rule\nexternal-controller: evil:1\ndns:\n  enable: false\n"), ProfileOverride: []byte("{}\n")})
	if e != nil {
		t.Fatal(e)
	}
	s := string(out)
	for _, want := range []string{"mixed-port: 7890", "dns:", "tun:", "stack: gvisor", "external-controller: 127.0.0.1:9090", "secret: keep"} {
		if !strings.Contains(s, want) {
			t.Fatalf("compiled config lacks %q: %s", want, s)
		}
	}
}

func TestManagedMixedPortWinsOverSourceAndOverrides(t *testing.T) {
	settings := profile.DefaultSettings()
	settings.Network.MixedPort = 7890
	out, err := (Compiler{Settings: settings}).Compile(CompileInput{
		Source:          []byte("mixed-port: 9999\nport: 7891\n"),
		GlobalOverride:  []byte("mixed-port: 8899\n"),
		ProfileOverride: []byte("mixed-port: 7788\n"),
	})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if got := compiled["mixed-port"]; got != 7890 {
		t.Fatalf("compiled mixed-port = %#v, want 7890", got)
	}
	if got := compiled["port"]; got != 7891 {
		t.Fatalf("source HTTP port changed: %#v", got)
	}
}

func TestManagedMixedPortNormalizesEquivalentHTTPAndSOCKSListeners(t *testing.T) {
	tests := []struct {
		name        string
		source      string
		wantPresent map[string]int
		wantAbsent  []string
	}{
		{
			name: "remove matching HTTP port",
			source: `
port: 7890
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
			},
			wantAbsent: []string{
				"port",
			},
		},
		{
			name: "remove matching SOCKS port",
			source: `
socks-port: 7890
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
			},
			wantAbsent: []string{
				"socks-port",
			},
		},
		{
			name: "remove matching HTTP and SOCKS ports",
			source: `
port: 7890
socks-port: 7890
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
			},
			wantAbsent: []string{
				"port",
				"socks-port",
			},
		},
		{
			name: "preserve different HTTP port",
			source: `
port: 7891
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
				"port":       7891,
			},
		},
		{
			name: "preserve different SOCKS port",
			source: `
socks-port: 7891
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
				"socks-port": 7891,
			},
		},
		{
			name: "remove matching HTTP but preserve different SOCKS port",
			source: `
port: 7890
socks-port: 7891
`,
			wantPresent: map[string]int{
				"mixed-port": 7890,
				"socks-port": 7891,
			},
			wantAbsent: []string{
				"port",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := profile.DefaultSettings()
			settings.Network.MixedPort = 7890

			out, err := (Compiler{Settings: settings}).Compile(CompileInput{
				Source: []byte(tt.source),
			})
			if err != nil {
				t.Fatal(err)
			}

			compiled, err := Parse(out)
			if err != nil {
				t.Fatal(err)
			}

			for key, want := range tt.wantPresent {
				got := configPort(compiled[key])
				if got != want {
					t.Fatalf(
						"%s = %d, want %d; compiled config: %s",
						key,
						got,
						want,
						out,
					)
				}
			}

			for _, key := range tt.wantAbsent {
				if _, exists := compiled[key]; exists {
					t.Fatalf(
						"%s should have been removed; compiled config: %s",
						key,
						out,
					)
				}
			}

			if err := ValidateListenerConflicts(compiled); err != nil {
				t.Fatalf(
					"normalized config still has listener conflict: %v\n%s",
					err,
					out,
				)
			}
		})
	}
}

func TestManagedMixedPortDoesNotNormalizeTransparentProxyListeners(t *testing.T) {
	tests := []struct {
		name string
		key  string
	}{
		{
			name: "redir port conflict",
			key:  "redir-port",
		},
		{
			name: "tproxy port conflict",
			key:  "tproxy-port",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			settings := profile.DefaultSettings()
			settings.Network.MixedPort = 7890

			source := []byte(fmt.Sprintf("%s: 7890\n", tt.key))

			out, err := (Compiler{Settings: settings}).Compile(CompileInput{
				Source: source,
			})
			if err != nil {
				t.Fatal(err)
			}

			compiled, err := Parse(out)
			if err != nil {
				t.Fatal(err)
			}

			if got := configPort(compiled["mixed-port"]); got != 7890 {
				t.Fatalf("mixed-port = %d, want 7890", got)
			}

			if got := configPort(compiled[tt.key]); got != 7890 {
				t.Fatalf(
					"%s was unexpectedly removed or changed: %#v",
					tt.key,
					compiled[tt.key],
				)
			}

			err = ValidateListenerConflicts(compiled)
			if err == nil {
				t.Fatalf(
					"expected %s to conflict with managed mixed-port",
					tt.key,
				)
			}

			if !strings.Contains(err.Error(), tt.key) {
				t.Fatalf(
					"conflict error does not mention %s: %v",
					tt.key,
					err,
				)
			}
		})
	}
}

func TestManagedMixedPortNormalizesEquivalentListenerFromOverrides(t *testing.T) {
	settings := profile.DefaultSettings()
	settings.Network.MixedPort = 7890

	tests := []struct {
		name            string
		source          string
		globalOverride  string
		profileOverride string
		key             string
	}{
		{
			name:           "global override HTTP port",
			source:         "mode: rule\n",
			globalOverride: "port: 7890\n",
			key:            "port",
		},
		{
			name:            "profile override HTTP port",
			source:          "mode: rule\n",
			profileOverride: "port: 7890\n",
			key:             "port",
		},
		{
			name:           "global override SOCKS port",
			source:         "mode: rule\n",
			globalOverride: "socks-port: 7890\n",
			key:            "socks-port",
		},
		{
			name:            "profile override SOCKS port",
			source:          "mode: rule\n",
			profileOverride: "socks-port: 7890\n",
			key:             "socks-port",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			out, err := (Compiler{Settings: settings}).Compile(CompileInput{
				Source:          []byte(tt.source),
				GlobalOverride:  []byte(tt.globalOverride),
				ProfileOverride: []byte(tt.profileOverride),
			})
			if err != nil {
				t.Fatal(err)
			}

			compiled, err := Parse(out)
			if err != nil {
				t.Fatal(err)
			}

			if got := configPort(compiled["mixed-port"]); got != 7890 {
				t.Fatalf("mixed-port = %d, want 7890", got)
			}

			if _, exists := compiled[tt.key]; exists {
				t.Fatalf(
					"%s should have been normalized away: %s",
					tt.key,
					out,
				)
			}

			if err := ValidateListenerConflicts(compiled); err != nil {
				t.Fatalf("unexpected listener conflict: %v", err)
			}
		})
	}
}

func TestSubscriptionHTTPPort7890WorksWithManagedMixedPort7890(t *testing.T) {
	settings := profile.DefaultSettings()
	settings.Network.MixedPort = 7890

	source := []byte(`
port: 7890
mode: rule
proxies:
  - name: test
    type: http
    server: 127.0.0.1
    port: 8080
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - test
rules:
  - MATCH,Proxy
`)

	out, err := (Compiler{Settings: settings}).Compile(CompileInput{
		Source: source,
	})
	if err != nil {
		t.Fatal(err)
	}

	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}

	if _, exists := compiled["port"]; exists {
		t.Fatalf(
			"redundant source HTTP listener was not removed: %s",
			out,
		)
	}

	if got := configPort(compiled["mixed-port"]); got != 7890 {
		t.Fatalf("mixed-port = %d, want 7890", got)
	}

	if err := ValidateListenerConflicts(compiled); err != nil {
		t.Fatalf(
			"subscription with port:7890 should compile successfully: %v\n%s",
			err,
			out,
		)
	}

	proxies, ok := compiled["proxies"].([]any)
	if !ok || len(proxies) != 1 {
		t.Fatalf("proxy definitions were modified: %#v", compiled["proxies"])
	}

	proxy, ok := proxies[0].(map[string]any)
	if !ok {
		t.Fatalf("proxy entry is invalid: %#v", proxies[0])
	}

	if got := configPort(proxy["port"]); got != 8080 {
		t.Fatalf(
			"nested proxy server port was modified: got %d, want 8080",
			got,
		)
	}
}

func TestCompilerPreservesNetworkSettingWhenOtherSettingsUseDefaults(t *testing.T) {
	settings := profile.Settings{Network: profile.NetworkSettings{MixedPort: 8890}}
	out, err := (Compiler{Settings: settings}).Compile(CompileInput{Source: []byte("mode: rule\n")})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if got := compiled["mixed-port"]; got != 8890 {
		t.Fatalf("compiled mixed-port = %#v, want 8890", got)
	}
}

func TestValidateListenerConflicts(t *testing.T) {
	if err := ValidateListenerConflicts(map[string]any{"mixed-port": 7890, "port": 7891}); err != nil {
		t.Fatal(err)
	}
	err := ValidateListenerConflicts(map[string]any{"mixed-port": 7890, "port": 7890})
	if err == nil || !strings.Contains(err.Error(), "Port 7890 is already used by mixed-port") {
		t.Fatalf("expected friendly listener conflict, got %v", err)
	}
}
func TestManagedDNSAndTUNPreserveUnknownFields(t *testing.T) {
	s := profile.DefaultSettings()
	s.DNS.FakeIPFilter = []string{"*.lan"}
	s.TUN.DNSHijack = []string{"any:53"}
	source := []byte(`mode: rule
dns:
  respect-rules: true
  nameserver-policy:
    "geosite:cn":
      - 223.5.5.5
  fallback:
    - https://1.1.1.1/dns-query
  fake-ip-filter-mode: blacklist
tun:
  mtu: 1500
  auto-redirect: true
  route:
    strict-route: true
    include-interface:
      - eth0
`)
	out, err := (Compiler{Settings: s}).Compile(CompileInput{Source: source})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	dns, ok := compiled["dns"].(map[string]any)
	if !ok {
		t.Fatalf("dns is not a map: %#v", compiled["dns"])
	}
	if dns["respect-rules"] != true || dns["fake-ip-filter-mode"] != "blacklist" {
		t.Fatalf("managed DNS removed unknown fields: %#v", dns)
	}
	if _, ok := dns["nameserver-policy"].(map[string]any); !ok {
		t.Fatalf("managed DNS removed nameserver-policy: %#v", dns)
	}
	if _, ok := dns["fallback"].([]any); !ok {
		t.Fatalf("managed DNS removed fallback: %#v", dns)
	}
	if dns["enhanced-mode"] != s.DNS.EnhancedMode {
		t.Fatalf("managed DNS field was not applied: %#v", dns)
	}

	tun, ok := compiled["tun"].(map[string]any)
	if !ok {
		t.Fatalf("tun is not a map: %#v", compiled["tun"])
	}
	if tun["mtu"] != 1500 {
		t.Fatalf("managed TUN removed unknown fields: %#v", tun)
	}
	if tun["auto-redirect"] != false {
		t.Fatalf("managed TUN kept subscription auto-redirect: %#v", tun)
	}
	route, ok := tun["route"].(map[string]any)
	if !ok || route["strict-route"] != true {
		t.Fatalf("managed TUN removed route fields: %#v", tun)
	}
	if tun["stack"] != profile.DefaultTUNStack {
		t.Fatalf("managed TUN field was not applied: %#v", tun)
	}
}

func TestManagedTUNStackPreservesExplicitMixed(t *testing.T) {
	s := profile.DefaultSettings()
	s.TUN.Stack = "mixed"
	out, err := (Compiler{Settings: s}).Compile(CompileInput{Source: []byte("mode: rule\n")})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), "stack: mixed") {
		t.Fatalf("explicit mixed stack was not preserved: %s", out)
	}
}

func TestInheritLeavesNetworkConfig(t *testing.T) {
	s := profile.DefaultSettings()
	s.DNSManagement = "inherit"
	s.TUNManagement = "inherit"
	out, e := (Compiler{Settings: s}).Compile(CompileInput{Source: []byte("dns:\n  enable: false\ntun:\n  enable: false\n")})
	if e != nil {
		t.Fatal(e)
	}
	text := string(out)
	if !strings.Contains(text, "enable: false") {
		t.Fatal(text)
	}
	if strings.Contains(text, "198.18.0.1/16") {
		t.Fatal("managed DNS leaked into inherit mode")
	}
}

func TestCompileLayersCustomRulesWithoutReplacingSourceRules(t *testing.T) {
	source := []byte(`mode: rule
proxy-groups:
  - name: Select
    type: select
rules:
  - GEOIP,CN,DIRECT
  - MATCH,Select
`)
	global := []byte("log-level: warning\n")
	profileOverride := []byte("allow-lan: true\n")
	custom := []rules.Rule{
		{Enabled: true, Match: rules.Match{Type: rules.DomainSuffix, Value: "openai.com"}, Policy: rules.Direct},
		{Enabled: true, Match: rules.Match{Type: rules.Domain, Value: "example.com"}, Policy: rules.Proxy},
	}
	out, err := (Compiler{}).Compile(CompileInput{
		Source: source, GlobalOverride: global, ProfileOverride: profileOverride,
		CustomRules: custom, Bindings: policy.Bindings{policy.Proxy: "Select"},
		Settings: profile.Settings{DNSManagement: "inherit", TUNManagement: "inherit"},
	})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if compiled["log-level"] != "warning" || compiled["allow-lan"] != true {
		t.Fatalf("override layers were not applied: %#v", compiled)
	}
	gotRules, ok := compiled["rules"].([]any)
	if !ok {
		t.Fatalf("compiled rules are not an array: %#v", compiled["rules"])
	}
	want := []any{
		"DOMAIN-SUFFIX,openai.com,DIRECT",
		"DOMAIN,example.com,Select",
		"GEOIP,CN,DIRECT",
		"MATCH,Select",
	}
	if len(gotRules) != len(want) {
		t.Fatalf("compiled rules length = %d, want %d: %#v", len(gotRules), len(want), gotRules)
	}
	for i := range want {
		if gotRules[i] != want[i] {
			t.Fatalf("compiled rule %d = %#v, want %#v", i, gotRules[i], want[i])
		}
	}
}

func TestUntrustedSubscriptionCannotExposeControllerOrLAN(t *testing.T) {
	source := []byte(`mode: rule
allow-lan: true
bind-address: '*'
secret: attacker-secret
external-controller: 0.0.0.0:9090
tun:
  enable: true
  auto-redirect: true
  mtu: 1400
listeners:
  - name: mixed-in
    type: mixed
    port: 7892
    listen: 0.0.0.0
`)
	out, err := (Compiler{Settings: profile.DefaultSettings(), Protected: map[string]any{
		"external-controller": "127.0.0.1:9090",
		"secret":              "keep",
	}}).Compile(CompileInput{Source: source, UntrustedSource: true})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := compiled["allow-lan"]; ok {
		t.Fatalf("subscription allow-lan survived: %#v", compiled["allow-lan"])
	}
	if _, ok := compiled["bind-address"]; ok {
		t.Fatalf("subscription bind-address survived: %#v", compiled["bind-address"])
	}
	if compiled["secret"] != "keep" || compiled["external-controller"] != "127.0.0.1:9090" {
		t.Fatalf("controller fields = secret %#v controller %#v", compiled["secret"], compiled["external-controller"])
	}
	tun, ok := compiled["tun"].(map[string]any)
	if !ok || tun["auto-redirect"] != false || tun["enable"] != false || tun["mtu"] != 1400 {
		t.Fatalf("tun = %#v", compiled["tun"])
	}
	listeners, ok := compiled["listeners"].([]any)
	if !ok || len(listeners) != 1 {
		t.Fatalf("listeners = %#v", compiled["listeners"])
	}
	listener, ok := listeners[0].(map[string]any)
	if !ok || listener["listen"] != "127.0.0.1" {
		t.Fatalf("listener = %#v", listeners[0])
	}
}

func TestManagedTUNRejectsAutoRedirectFromSourceAndOverride(t *testing.T) {
	out, err := (Compiler{Settings: profile.DefaultSettings()}).Compile(CompileInput{
		Source:          []byte("mode: rule\ntun:\n  auto-redirect: true\n"),
		ProfileOverride: []byte("tun:\n  auto-redirect: true\n"),
		UntrustedSource: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	tun, ok := compiled["tun"].(map[string]any)
	if !ok || tun["auto-redirect"] != false {
		t.Fatalf("managed auto-redirect = %#v", compiled["tun"])
	}
}

func TestUntrustedSourceStillHonorsUserAllowLANOverride(t *testing.T) {
	out, err := (Compiler{Settings: profile.DefaultSettings()}).Compile(CompileInput{
		Source:          []byte("allow-lan: true\nmode: rule\n"),
		ProfileOverride: []byte("allow-lan: true\n"),
		UntrustedSource: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if compiled["allow-lan"] != true {
		t.Fatalf("user override allow-lan = %#v", compiled["allow-lan"])
	}
}

func TestTrustedLocalSourceKeepsAllowLAN(t *testing.T) {
	out, err := (Compiler{Settings: profile.DefaultSettings()}).Compile(CompileInput{
		Source: []byte("allow-lan: true\nmode: rule\n"),
	})
	if err != nil {
		t.Fatal(err)
	}
	compiled, err := Parse(out)
	if err != nil {
		t.Fatal(err)
	}
	if compiled["allow-lan"] != true {
		t.Fatalf("local allow-lan = %#v", compiled["allow-lan"])
	}
}
