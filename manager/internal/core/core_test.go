package core

import (
	"encoding/json"
	"testing"
)

func TestHTTPProxyPortExcludesSocksOnly(t *testing.T) {
	if got := HTTPProxyPort(map[string]any{"socks-port": float64(7891)}); got != 0 {
		t.Fatalf("HTTPProxyPort(socks only) = %d, want 0", got)
	}
	if got := HTTPProxyPort(map[string]any{"port": json.Number("7890")}); got != 7890 {
		t.Fatalf("HTTPProxyPort(port) = %d, want 7890", got)
	}
	if got := HTTPProxyPort(map[string]any{"mixed-port": float64(7892), "port": float64(7890)}); got != 7892 {
		t.Fatalf("HTTPProxyPort(mixed-port) = %d, want 7892", got)
	}
}

func TestMixedPortFromConfigDoesNotFallbackToHTTP(t *testing.T) {
	if got := MixedPortFromConfig(map[string]any{"port": float64(7890)}); got != 0 {
		t.Fatalf("MixedPortFromConfig(HTTP only) = %d, want 0", got)
	}
	if got := MixedPortFromConfig(map[string]any{"mixed-port": json.Number("7892"), "port": float64(7890)}); got != 7892 {
		t.Fatalf("MixedPortFromConfig = %d, want 7892", got)
	}
}
