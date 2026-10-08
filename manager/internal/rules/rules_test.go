package rules

import (
	"reflect"
	"testing"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/policy"
)

func TestNormalizeDomain(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "plain", in: " OpenAI.COM ", want: "openai.com"},
		{name: "wildcard", in: "*.openai.com", want: "openai.com"},
		{name: "url path", in: "https://openai.com/chat", want: "openai.com"},
		{name: "url query", in: "https://openai.com?token=secret", want: "openai.com"},
		{name: "url port", in: "http://OPENAI.COM:8080/v1", want: "openai.com"},
		{name: "trailing dot", in: "example.com.", want: "example.com"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			got, err := NormalizeDomain(test.in)
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("NormalizeDomain(%q) = %q, want %q", test.in, got, test.want)
			}
		})
	}

	for _, input := range []string{"", "open ai.com", "https://user:pass@example.com", "example..com", "-example.com", "example-.com", "https://"} {
		t.Run("invalid "+input, func(t *testing.T) {
			if _, err := NormalizeDomain(input); err == nil {
				t.Fatalf("NormalizeDomain(%q) unexpectedly succeeded", input)
			}
		})
	}
}

func TestNormalizeCollectionRejectsDuplicateRules(t *testing.T) {
	collection := Collection{SchemaVersion: SchemaVersion, Rules: []Rule{
		{ID: "11111111-1111-4111-8111-111111111111", Enabled: true, Match: Match{Type: DomainSuffix, Value: "example.com"}, Policy: Direct},
		{ID: "22222222-2222-4222-8222-222222222222", Enabled: true, Match: Match{Type: DomainSuffix, Value: "EXAMPLE.COM"}, Policy: Reject},
	}}
	if _, err := NormalizeCollection(collection); err == nil {
		t.Fatal("duplicate domains unexpectedly succeeded")
	}
}

func TestInjectPrependsAndPreservesExistingRules(t *testing.T) {
	config := map[string]any{
		"rules":        []any{"GEOIP,CN,DIRECT", "MATCH,Select"},
		"proxy-groups": []any{map[string]any{"name": "Select", "type": "select"}},
	}
	items := []Rule{
		{Enabled: true, Match: Match{Type: DomainSuffix, Value: "example.com"}, Policy: Direct},
		{Enabled: false, Match: Match{Type: Domain, Value: "disabled.example"}, Policy: Reject},
		{Enabled: true, Match: Match{Type: Domain, Value: "blocked.example"}, Policy: Reject},
		{Enabled: true, Match: Match{Type: DomainSuffix, Value: "proxy.example"}, Policy: Proxy},
	}

	got, err := Inject(config, items, policy.Bindings{policy.Proxy: "Select"})
	if err != nil {
		t.Fatal(err)
	}
	want := []any{
		"DOMAIN-SUFFIX,example.com,DIRECT",
		"DOMAIN,blocked.example,REJECT",
		"DOMAIN-SUFFIX,proxy.example,Select",
		"GEOIP,CN,DIRECT",
		"MATCH,Select",
	}
	if !reflect.DeepEqual(got["rules"], want) {
		t.Fatalf("injected rules = %#v, want %#v", got["rules"], want)
	}
	if len(config["rules"].([]any)) != 2 {
		t.Fatal("Inject mutated the source config")
	}
}

func TestInjectRequiresProxyBinding(t *testing.T) {
	_, err := Inject(map[string]any{}, []Rule{{Enabled: true, Match: Match{Type: DomainSuffix, Value: "example.com"}, Policy: Proxy}}, nil)
	if err == nil {
		t.Fatal("proxy rule without binding unexpectedly succeeded")
	}
}
