package rules

import (
	"fmt"
	"net/url"
	"strings"
	"time"
	"unicode"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
)

const (
	SchemaVersion = 1
	DomainSuffix  = "domain-suffix"
	Domain        = "domain"
	Proxy         = "proxy"
	Direct        = "direct"
	Reject        = "reject"
)

type Match struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type Rule struct {
	ID        string `json:"id"`
	Enabled   bool   `json:"enabled"`
	Match     Match  `json:"match"`
	Policy    string `json:"policy"`
	CreatedAt string `json:"createdAt"`
}

type Collection struct {
	SchemaVersion int    `json:"schemaVersion"`
	Rules         []Rule `json:"rules"`
}

func DefaultCollection() Collection {
	return Collection{SchemaVersion: SchemaVersion, Rules: []Rule{}}
}

func New(domain, matchType, policy string) (Rule, error) {
	normalized, err := NormalizeRule(Rule{
		Match:   Match{Type: matchType, Value: domain},
		Policy:  policy,
		Enabled: true,
	})
	if err != nil {
		return Rule{}, err
	}
	id, err := store.RandomID()
	if err != nil {
		return Rule{}, err
	}
	normalized.ID = id
	normalized.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	return normalized, nil
}

func NormalizeRule(rule Rule) (Rule, error) {
	matchType := strings.ToLower(strings.TrimSpace(rule.Match.Type))
	if matchType == "" {
		matchType = DomainSuffix
	}
	if matchType != DomainSuffix && matchType != Domain {
		return Rule{}, fmt.Errorf("match type must be domain-suffix or domain")
	}
	domain, err := NormalizeDomain(rule.Match.Value)
	if err != nil {
		return Rule{}, err
	}
	policy := strings.ToLower(strings.TrimSpace(rule.Policy))
	if policy != Proxy && policy != Direct && policy != Reject {
		return Rule{}, fmt.Errorf("policy must be proxy, direct, or reject")
	}
	rule.Match = Match{Type: matchType, Value: domain}
	rule.Policy = policy
	if rule.CreatedAt == "" {
		rule.CreatedAt = time.Now().UTC().Format(time.RFC3339)
	}
	return rule, nil
}

// NormalizeDomain accepts the short forms people naturally paste into a rule
// editor, including a URL and a leading wildcard, and stores one stable host.
func NormalizeDomain(raw string) (string, error) {
	value := strings.TrimSpace(raw)
	if value == "" {
		return "", fmt.Errorf("domain must not be empty")
	}
	for _, r := range value {
		if unicode.IsSpace(r) {
			return "", fmt.Errorf("domain must not contain whitespace")
		}
	}
	if strings.Contains(value, "://") || strings.Contains(value, "/") {
		candidate := value
		if !strings.Contains(candidate, "://") {
			candidate = "https://" + candidate
		}
		host, err := hostnameFromURL(candidate)
		if err != nil {
			return "", err
		}
		value = host
	}
	value = strings.TrimPrefix(value, "*.")
	value = strings.TrimSuffix(value, ".")
	value = strings.ToLower(value)
	if value == "" || strings.ContainsAny(value, "/\\,:@[]*?\"'") {
		return "", fmt.Errorf("invalid domain")
	}
	if strings.Contains(value, "..") {
		return "", fmt.Errorf("invalid domain")
	}
	for _, label := range strings.Split(value, ".") {
		if label == "" || strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") {
			return "", fmt.Errorf("invalid domain")
		}
		for _, r := range label {
			if !(unicode.IsLetter(r) || unicode.IsDigit(r) || r == '-' || r == '_') {
				return "", fmt.Errorf("invalid domain")
			}
		}
	}
	return value, nil
}

func hostnameFromURL(raw string) (string, error) {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return "", fmt.Errorf("domain URL must use HTTP or HTTPS")
	}
	if parsed.User != nil {
		return "", fmt.Errorf("domain URL must not contain credentials")
	}
	host := parsed.Hostname()
	if host == "" {
		return "", fmt.Errorf("domain URL host must not be empty")
	}
	return host, nil
}

func ValidateCollection(collection Collection) error {
	if collection.SchemaVersion == 0 {
		collection.SchemaVersion = SchemaVersion
	}
	if collection.SchemaVersion != SchemaVersion {
		return fmt.Errorf("unsupported custom rules schema version %d", collection.SchemaVersion)
	}
	seen := map[string]bool{}
	for i, rule := range collection.Rules {
		normalized, err := NormalizeRule(rule)
		if err != nil {
			return fmt.Errorf("rule %d: %w", i+1, err)
		}
		if rule.ID != "" && !store.ValidID(rule.ID) {
			return fmt.Errorf("rule %d: invalid id", i+1)
		}
		key := normalized.Match.Type + "\x00" + normalized.Match.Value
		if seen[key] {
			return fmt.Errorf("duplicate rule for %s", normalized.Match.Value)
		}
		seen[key] = true
	}
	return nil
}

func NormalizeCollection(collection Collection) (Collection, error) {
	if collection.SchemaVersion == 0 {
		collection.SchemaVersion = SchemaVersion
	}
	if collection.Rules == nil {
		collection.Rules = []Rule{}
	}
	for i := range collection.Rules {
		normalized, err := NormalizeRule(collection.Rules[i])
		if err != nil {
			return Collection{}, fmt.Errorf("rule %d: %w", i+1, err)
		}
		if normalized.ID == "" {
			normalized.ID, err = store.RandomID()
			if err != nil {
				return Collection{}, err
			}
		}
		collection.Rules[i] = normalized
	}
	if err := ValidateCollection(collection); err != nil {
		return Collection{}, err
	}
	return collection, nil
}

func NeedsProxyBinding(items []Rule) bool {
	for _, item := range items {
		if item.Enabled && strings.EqualFold(strings.TrimSpace(item.Policy), Proxy) {
			return true
		}
	}
	return false
}

func Key(rule Rule) string { return rule.Match.Type + "\x00" + rule.Match.Value }
