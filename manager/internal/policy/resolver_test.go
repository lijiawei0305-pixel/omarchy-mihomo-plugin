package policy

import (
	"reflect"
	"testing"
)

func testConfig(groups ...map[string]any) map[string]any {
	items := make([]any, len(groups))
	for i, group := range groups {
		items[i] = group
	}
	return map[string]any{"proxy-groups": items}
}

func group(name, kind string) map[string]any {
	return map[string]any{"name": name, "type": kind}
}

func TestResolveProxyBinding(t *testing.T) {
	for _, test := range []struct {
		name       string
		config     map[string]any
		bindings   Bindings
		want       string
		wantChange bool
	}{
		{name: "single", config: testConfig(group("Proxy", "select")), want: "Proxy", wantChange: true},
		{name: "single selector", config: testConfig(group("Proxy", "select"), group("Auto", "url-test")), want: "Proxy", wantChange: true},
		{name: "saved", config: testConfig(group("Proxy", "select"), group("Auto", "url-test")), bindings: Bindings{Proxy: "Auto"}, want: "Auto"},
	} {
		t.Run(test.name, func(t *testing.T) {
			got, changed, err := ResolveProxyBinding(test.config, test.bindings, "profile")
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want || changed != test.wantChange {
				t.Fatalf("ResolveProxyBinding = (%q, %v), want (%q, %v)", got, changed, test.want, test.wantChange)
			}
		})
	}
}

func TestResolveProxyBindingRequiresChoice(t *testing.T) {
	_, changed, err := ResolveProxyBinding(testConfig(
		group("Proxy", "url-test"), group("Auto", "fallback"), group("Media", "load-balance")), nil, "profile")
	if changed {
		t.Fatal("ambiguous binding was marked as changed")
	}
	bindingErr, ok := err.(*BindingError)
	if !ok || bindingErr.Code != "binding_required" {
		t.Fatalf("error = %#v, want binding_required", err)
	}
	want := []string{"Auto", "Media", "Proxy"}
	if !reflect.DeepEqual(bindingErr.Candidates, want) {
		t.Fatalf("candidates = %#v, want %#v", bindingErr.Candidates, want)
	}
}

func TestResolveProxyBindingRejectsStaleBinding(t *testing.T) {
	_, changed, err := ResolveProxyBinding(testConfig(group("Proxy", "select")), Bindings{Proxy: "Removed"}, "profile")
	if changed {
		t.Fatal("stale binding was marked as changed")
	}
	bindingErr, ok := err.(*BindingError)
	if !ok || bindingErr.Code != "binding_required" {
		t.Fatalf("error = %#v, want binding_required", err)
	}
}

func TestResolveProxyBindingUnavailable(t *testing.T) {
	_, changed, err := ResolveProxyBinding(testConfig(group("DIRECT", "direct")), nil, "profile")
	if changed {
		t.Fatal("unavailable binding was marked as changed")
	}
	bindingErr, ok := err.(*BindingError)
	if !ok || bindingErr.Code != "binding_unavailable" {
		t.Fatalf("error = %#v, want binding_unavailable", err)
	}
}

func TestCandidatesExcludeTerminalGroups(t *testing.T) {
	got := Candidates(testConfig(
		group("Direct", "direct"),
		group("Reject drop", "reject-drop"),
		group("Pass rule", "pass-rule"),
		group("DNS", "dns"),
		group("Proxy", "select"),
	))
	if !reflect.DeepEqual(got, []string{"Proxy"}) {
		t.Fatalf("Candidates = %#v, want [Proxy]", got)
	}
}
