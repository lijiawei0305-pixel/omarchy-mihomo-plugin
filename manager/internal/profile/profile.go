package profile

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
)

type SubscriptionInfo struct {
	Upload   int64 `json:"upload"`
	Download int64 `json:"download"`
	Total    int64 `json:"total"`
	Expire   int64 `json:"expire"`
}
type Meta struct {
	SchemaVersion     int              `json:"schemaVersion"`
	ID                string           `json:"id"`
	Name              string           `json:"name"`
	Type              string           `json:"type"`
	URL               string           `json:"url,omitempty"`
	UpdateIntervalSec int              `json:"updateIntervalSec"`
	UpdateViaProxy    bool             `json:"updateViaProxy"`
	FetchUserAgent    string           `json:"fetchUserAgent"`
	CreatedAt         string           `json:"createdAt"`
	LastUpdatedAt     string           `json:"lastUpdatedAt"`
	LastSuccessAt     string           `json:"lastSuccessAt"`
	ETag              string           `json:"etag"`
	LastModified      string           `json:"lastModified"`
	LastError         string           `json:"lastError,omitempty"`
	SubscriptionInfo  SubscriptionInfo `json:"subscriptionInfo"`
}
type Index struct {
	Profiles      []string `json:"profiles"`
	ActiveProfile string   `json:"activeProfile,omitempty"`
}
type Settings struct {
	Network       NetworkSettings `json:"network"`
	DNSManagement string          `json:"dnsManagement"`
	TUNManagement string          `json:"tunManagement"`
	DNS           DNSSettings     `json:"dns"`
	TUN           TUNSettings     `json:"tun"`
}
type NetworkSettings struct {
	MixedPort int `json:"mixedPort"`
}
type DNSSettings struct {
	Enable                bool     `json:"enable"`
	IPv6                  bool     `json:"ipv6"`
	EnhancedMode          string   `json:"enhancedMode"`
	FakeIPRange           string   `json:"fakeIPRange"`
	DefaultNameserver     []string `json:"defaultNameserver"`
	Nameserver            []string `json:"nameserver"`
	ProxyServerNameserver []string `json:"proxyServerNameserver"`
	FakeIPFilter          []string `json:"fakeIPFilter"`
}
type TUNSettings struct {
	Enable              bool     `json:"enable"`
	Stack               string   `json:"stack"`
	AutoRoute           bool     `json:"autoRoute"`
	AutoDetectInterface bool     `json:"autoDetectInterface"`
	StrictRoute         bool     `json:"strictRoute"`
	DNSHijack           []string `json:"dnsHijack"`
}

const DefaultTUNStack = "gvisor"

// NormalizeTUNStack applies the product default without taking ownership of an
// explicit stack selected by the user. In particular, mixed remains a valid
// Mihomo choice; the UI/doctor can explain firewall trade-offs without silently
// changing the user's source or settings.
func NormalizeTUNStack(stack string) string {
	stack = strings.ToLower(strings.TrimSpace(stack))
	if stack == "" {
		return DefaultTUNStack
	}
	return stack
}

func DefaultSettings() Settings {
	return Settings{
		Network: NetworkSettings{
			MixedPort: 7890,
		},
		DNSManagement: "managed",
		TUNManagement: "managed",
		DNS: DNSSettings{
			Enable:                true,
			IPv6:                  false,
			EnhancedMode:          "fake-ip",
			FakeIPRange:           "198.18.0.1/16",
			DefaultNameserver:     []string{"223.5.5.5", "1.1.1.1"},
			Nameserver:            []string{"https://dns.alidns.com/dns-query", "https://1.1.1.1/dns-query"},
			ProxyServerNameserver: []string{"https://dns.alidns.com/dns-query", "https://1.1.1.1/dns-query"},
			FakeIPFilter:          []string{"*.lan", "*.local", "localhost"},
		},
		TUN: TUNSettings{
			// Do not enable TUN before the user explicitly asks for system-wide
			// capture. A fresh core may not have cap_net_admin, and profile setup
			// should succeed even when TUN is unavailable.
			Enable:              false,
			Stack:               DefaultTUNStack,
			AutoRoute:           true,
			AutoDetectInterface: true,
			StrictRoute:         false,
			DNSHijack:           []string{"any:53", "tcp://any:53"},
		},
	}
}
func LoadIndex(s *store.Store) (Index, error) {
	var x Index
	b, e := os.ReadFile(s.IndexPath())
	if os.IsNotExist(e) {
		return x, nil
	}
	if e != nil {
		return x, e
	}
	e = json.Unmarshal(b, &x)
	return x, e
}
func SaveIndex(s *store.Store, x Index) error {
	sort.Strings(x.Profiles)
	return s.WriteJSON(s.IndexPath(), x)
}
func LoadSettings(s *store.Store) (Settings, error) {
	x := DefaultSettings()
	b, e := os.ReadFile(s.SettingsPath())
	if os.IsNotExist(e) {
		return x, nil
	}
	if e != nil {
		return x, e
	}
	e = json.Unmarshal(b, &x)
	if e != nil {
		return x, e
	}
	if x.Network.MixedPort <= 0 {
		// Older settings files predate the managed network block. Keep the
		// bootstrap contract when the block or its field was absent.
		x.Network.MixedPort = DefaultSettings().Network.MixedPort
	}
	// Normalize casing/whitespace, but preserve an explicit mixed stack. The
	// default is gvisor; migration must not rewrite a user's chosen strategy.
	if normalized := NormalizeTUNStack(x.TUN.Stack); normalized != x.TUN.Stack {
		x.TUN.Stack = normalized
		if e = SaveSettings(s, x); e != nil {
			return x, e
		}
	}
	return x, nil
}
func SaveSettings(s *store.Store, x Settings) error {
	if x.Network.MixedPort <= 0 {
		x.Network.MixedPort = DefaultSettings().Network.MixedPort
	}
	x.TUN.Stack = NormalizeTUNStack(x.TUN.Stack)
	return s.WriteJSON(s.SettingsPath(), x)
}
func LoadMeta(s *store.Store, id string) (Meta, error) {
	var x Meta
	b, e := os.ReadFile(s.ProfilePath(id, "meta.json"))
	if e != nil {
		return x, e
	}
	e = json.Unmarshal(b, &x)
	return x, e
}
func SaveMeta(s *store.Store, x Meta) error { return s.WriteJSON(s.ProfilePath(x.ID, "meta.json"), x) }
func EnsureMeta(m Meta) Meta {
	if m.SchemaVersion == 0 {
		m.SchemaVersion = 1
	}
	if m.CreatedAt == "" {
		m.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	}
	return m
}
func Add(s *store.Store, m Meta, source, override []byte) error {
	if !store.ValidID(m.ID) || strings.TrimSpace(m.Name) == "" {
		return fmt.Errorf("invalid profile")
	}
	if m.Type != "remote" && m.Type != "local" {
		return fmt.Errorf("profile type must be remote or local")
	}
	// A profile is only visible after all three files have been committed.
	// Use Mkdir rather than MkdirAll so a failed create can never delete an
	// existing profile directory supplied by a caller.
	if err := os.Mkdir(s.ProfileDir(m.ID), 0700); err != nil {
		return err
	}
	committed := false
	defer func() {
		if !committed {
			_ = os.RemoveAll(s.ProfileDir(m.ID))
		}
	}()
	m = EnsureMeta(m)
	if err := SaveMeta(s, m); err != nil {
		return err
	}
	if err := s.WriteAtomic(s.ProfilePath(m.ID, "source.yaml"), source); err != nil {
		return err
	}
	if override == nil {
		override = []byte("{}\n")
	}
	if err := s.WriteAtomic(s.ProfilePath(m.ID, "override.yaml"), override); err != nil {
		return err
	}
	committed = true
	return nil
}
func Delete(s *store.Store, id string) error {
	if !store.ValidID(id) {
		return fmt.Errorf("invalid profile id")
	}
	return os.RemoveAll(s.ProfileDir(id))
}
func List(s *store.Store, idx Index) ([]Meta, error) {
	out := []Meta{}
	for _, id := range idx.Profiles {
		m, e := LoadMeta(s, id)
		if e == nil {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}
func TouchSuccess(m Meta, etag, lastmod string) Meta {
	now := time.Now().UTC().Format(time.RFC3339)
	m.LastUpdatedAt = now
	m.LastSuccessAt = now
	m.ETag = etag
	m.LastModified = lastmod
	m.LastError = ""
	return m
}
func SetError(m Meta, err error) Meta { m.LastError = err.Error(); return m }
func ReadSource(s *store.Store, id string) ([]byte, error) {
	return os.ReadFile(s.ProfilePath(id, "source.yaml"))
}
func ReadOverride(s *store.Store, id string) ([]byte, error) {
	return os.ReadFile(s.ProfilePath(id, "override.yaml"))
}
func Rename(s *store.Store, id, name string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return fmt.Errorf("profile name must not be empty")
	}
	m, err := LoadMeta(s, id)
	if err != nil {
		return err
	}
	m.Name = name
	return SaveMeta(s, m)
}
func parseTime(s string) time.Time { t, _ := time.Parse(time.RFC3339, s); return t }
func Due(m Meta, now time.Time) bool {
	if m.Type != "remote" || m.UpdateIntervalSec <= 0 {
		return false
	}
	if m.LastSuccessAt == "" {
		return true
	}
	parsed := parseTime(m.LastSuccessAt)
	return !parsed.IsZero() && !now.Before(parsed.Add(time.Duration(m.UpdateIntervalSec)*time.Second))
}
func ProfilePath(s *store.Store, id string) string { return filepath.Join(s.ProfilesDir(), id) }
