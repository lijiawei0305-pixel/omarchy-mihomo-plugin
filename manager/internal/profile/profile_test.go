package profile

import (
	"os"
	"strings"
	"testing"
	"time"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
)

func TestDefaultSettingsUseGVisorTUNStack(t *testing.T) {
	settings := DefaultSettings()
	if got := settings.Network.MixedPort; got != 7890 {
		t.Fatalf("default mixed port = %d, want 7890", got)
	}
	if got := settings.TUN.Stack; got != DefaultTUNStack {
		t.Fatalf("default TUN stack = %q, want %q", got, DefaultTUNStack)
	}
	if settings.TUN.Enable {
		t.Fatal("TUN must be disabled until the user explicitly enables it")
	}
}

func TestLoadSettingsMigratesMissingNetworkSettings(t *testing.T) {
	s := &store.Store{Home: t.TempDir()}
	if err := s.Ensure(); err != nil {
		t.Fatal(err)
	}
	legacy := DefaultSettings()
	legacy.Network.MixedPort = 0
	if err := s.WriteJSON(s.SettingsPath(), legacy); err != nil {
		t.Fatal(err)
	}
	got, err := LoadSettings(s)
	if err != nil {
		t.Fatal(err)
	}
	if got.Network.MixedPort != 7890 {
		t.Fatalf("migrated mixed port = %d, want 7890", got.Network.MixedPort)
	}
}

func TestNormalizeTUNStackDefaultsEmptyAndPreservesMixed(t *testing.T) {
	if got := NormalizeTUNStack(""); got != DefaultTUNStack {
		t.Errorf("NormalizeTUNStack(empty) = %q, want %q", got, DefaultTUNStack)
	}
	for _, input := range []string{"mixed", " MIXED "} {
		if got := NormalizeTUNStack(input); got != "mixed" {
			t.Errorf("NormalizeTUNStack(%q) = %q, want mixed", input, got)
		}
	}
	if got := NormalizeTUNStack("system"); got != "system" {
		t.Fatalf("NormalizeTUNStack(system) = %q", got)
	}
}

func TestLoadSettingsPreservesMixedStack(t *testing.T) {
	s := &store.Store{Home: t.TempDir()}
	if err := s.Ensure(); err != nil {
		t.Fatal(err)
	}
	legacy := DefaultSettings()
	legacy.TUN.Stack = "mixed"
	if err := s.WriteJSON(s.SettingsPath(), legacy); err != nil {
		t.Fatal(err)
	}
	got, err := LoadSettings(s)
	if err != nil {
		t.Fatal(err)
	}
	if got.TUN.Stack != "mixed" {
		t.Fatalf("loaded TUN stack = %q, want mixed", got.TUN.Stack)
	}
	persisted, err := os.ReadFile(s.SettingsPath())
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(persisted), `"stack": "mixed"`) {
		t.Fatalf("explicit mixed stack was not preserved: %s", persisted)
	}
}

func TestDueAndUUIDProfile(t *testing.T) {
	id, e := store.RandomID()
	if e != nil || !store.ValidID(id) {
		t.Fatalf("bad UUID: %q %v", id, e)
	}
	m := Meta{ID: id, Type: "remote", UpdateIntervalSec: 60, LastSuccessAt: time.Now().Add(-time.Minute * 2).UTC().Format(time.RFC3339)}
	if !Due(m, time.Now()) {
		t.Fatal("profile should be due")
	}
}
