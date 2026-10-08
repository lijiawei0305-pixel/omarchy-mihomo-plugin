package doctor

import (
	"encoding/json"
	"testing"
)

func TestDoctorValueHelpers(t *testing.T) {
	data := map[string]any{
		"mixed-port": json.Number("7890"),
		"version":    "1.2.3",
		"meta":       map[string]any{"version": "fallback"},
	}
	if got := intAt(data, "mixed-port"); got != 7890 {
		t.Fatalf("intAt = %d, want 7890", got)
	}
	if got := firstString(data, "missing", "version"); got != "1.2.3" {
		t.Fatalf("firstString = %q, want 1.2.3", got)
	}
	if got := firstString(data, "meta.version"); got != "fallback" {
		t.Fatalf("nested firstString = %q, want fallback", got)
	}
}

func TestDoctorNetworkValues(t *testing.T) {
	report := Report{}
	addNetworkChecks(&report, map[string]any{
		"mixed-port": float64(7890),
		"tun": map[string]any{
			"enable": true,
			"stack":  "gvisor",
			"device": "mihomo",
		},
		"dns": map[string]any{
			"enable":        true,
			"enhanced-mode": "fake-ip",
		},
	})
	checks := map[string]Check{}
	for _, check := range report.Checks {
		checks[check.ID] = check
	}
	if checks["tunEnabled"].Status != "ok" || checks["dnsEnabled"].Status != "ok" {
		t.Fatalf("network checks = %#v", checks)
	}
	if checks["httpProxyPort"].Message != "7890" {
		t.Fatalf("proxy port check = %#v", checks["httpProxyPort"])
	}
}

func TestDisabledTUNIsInformationalAndSkipsInterfaceProbe(t *testing.T) {
	report := Report{}
	addNetworkChecks(&report, map[string]any{
		"tun": map[string]any{"enable": false},
		"dns": map[string]any{"enable": true, "enhanced-mode": "fake-ip"},
	})
	checks := map[string]Check{}
	for _, check := range report.Checks {
		checks[check.ID] = check
	}
	if checks["tunEnabled"].Status != "info" {
		t.Fatalf("disabled TUN status = %#v", checks["tunEnabled"])
	}
	if _, ok := checks["tunInterface"]; ok {
		t.Fatal("disabled TUN should not probe for an interface")
	}
}

func TestDNSChecksFallBackToRuntimeConfig(t *testing.T) {
	report := Report{}
	addNetworkChecksWithRuntime(&report, map[string]any{
		"tun": map[string]any{"enable": false},
	}, map[string]any{
		"dns": map[string]any{"enable": true, "enhanced-mode": "fake-ip"},
	})
	checks := map[string]Check{}
	for _, check := range report.Checks {
		checks[check.ID] = check
	}
	if checks["dnsEnabled"].Status != "ok" || checks["dnsMode"].Message != "fake-ip" {
		t.Fatalf("DNS runtime fallback = %#v", checks)
	}
}

func TestFirewallSensitiveTUNStack(t *testing.T) {
	if stack, ok := firewallSensitiveTUNStack(map[string]any{
		"tun": map[string]any{"enable": true, "stack": "mixed"},
	}); !ok || stack != "mixed" {
		t.Fatalf("mixed TUN stack = %q, %v", stack, ok)
	}
	if _, ok := firewallSensitiveTUNStack(map[string]any{
		"tun": map[string]any{"enable": true, "stack": "gvisor"},
	}); ok {
		t.Fatal("gvisor should not trigger a firewall compatibility hint")
	}
	if _, ok := firewallSensitiveTUNStack(map[string]any{
		"tun": map[string]any{"enable": false, "stack": "system"},
	}); ok {
		t.Fatal("disabled TUN should not trigger a firewall compatibility hint")
	}
}

func TestFirewallTUNPreflightDefaultsToGVisor(t *testing.T) {
	report := Report{}
	addFirewallTUNPreflightCheck(&report, "  GVISOR ")
	if len(report.Checks) != 1 {
		t.Fatalf("preflight checks = %#v", report.Checks)
	}
	if report.Checks[0].ID != "firewallTunCompatibility" || report.Checks[0].Status != "ok" || report.Checks[0].Message != "gvisor" {
		t.Fatalf("preflight check = %#v", report.Checks[0])
	}
}
