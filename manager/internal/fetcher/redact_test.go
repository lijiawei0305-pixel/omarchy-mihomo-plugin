package fetcher

import (
	"strings"
	"testing"
)

func TestURLIsNotLoggedByFetcherErrors(t *testing.T) {
	_, err := Fetch("file:///secret/token", "", "", "", false, 0)
	if err == nil {
		t.Fatal("expected scheme error")
	}
	if got := err.Error(); got == "" || containsSecret(got) {
		t.Fatalf("unsafe error: %q", got)
	}
}
func containsSecret(s string) bool {
	lower := strings.ToLower(s)
	return strings.Contains(lower, "secret") || strings.Contains(lower, "token")
}
