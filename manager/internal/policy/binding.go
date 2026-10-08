package policy

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
)

const Proxy = "proxy"

type Bindings map[string]string

type File struct {
	SchemaVersion int      `json:"schemaVersion"`
	Bindings      Bindings `json:"bindings"`
}

type BindingError struct {
	Code       string   `json:"code"`
	Policy     string   `json:"policy"`
	ProfileID  string   `json:"profileId,omitempty"`
	Candidates []string `json:"candidates,omitempty"`
	Message    string   `json:"message"`
}

func (e *BindingError) Error() string {
	if e == nil || e.Message == "" {
		return "policy binding is unavailable"
	}
	return e.Message
}

func Load(s *store.Store, id string) (Bindings, error) {
	b, err := os.ReadFile(s.BindingsPath(id))
	if os.IsNotExist(err) {
		return Bindings{}, nil
	}
	if err != nil {
		return nil, err
	}
	file := File{}
	if err := json.Unmarshal(b, &file); err != nil {
		return nil, err
	}
	if file.SchemaVersion == 0 {
		file.SchemaVersion = 1
	}
	if file.SchemaVersion != 1 {
		return nil, fmt.Errorf("unsupported bindings schema version %d", file.SchemaVersion)
	}
	if file.Bindings == nil {
		file.Bindings = Bindings{}
	}
	return clone(file.Bindings), nil
}

func Save(s *store.Store, id string, bindings Bindings) error {
	if !store.ValidID(id) {
		return fmt.Errorf("valid profile id required")
	}
	if bindings == nil {
		bindings = Bindings{}
	}
	file := File{SchemaVersion: 1, Bindings: clone(bindings)}
	b, err := json.MarshalIndent(file, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return s.WriteAtomic(s.BindingsPath(id), b)
}

func Clone(bindings Bindings) Bindings { return clone(bindings) }

func clone(bindings Bindings) Bindings {
	out := Bindings{}
	for key, value := range bindings {
		out[key] = value
	}
	return out
}

// Candidates returns the proxy groups a routing policy may target. Terminal
// groups are deliberately excluded; DIRECT/REJECT are represented by policies.
func Candidates(config map[string]any) []string {
	raw, ok := config["proxy-groups"]
	if !ok {
		return []string{}
	}
	items, ok := raw.([]any)
	if !ok {
		return []string{}
	}
	seen := map[string]bool{}
	out := []string{}
	for _, value := range items {
		group, ok := value.(map[string]any)
		if !ok {
			continue
		}
		name, _ := group["name"].(string)
		name = strings.TrimSpace(name)
		if name == "" || seen[name] {
			continue
		}
		kind, _ := group["type"].(string)
		switch strings.ToLower(strings.TrimSpace(kind)) {
		case "direct", "reject", "reject-drop", "rejectdrop", "pass", "pass-rule", "passrule", "dns":
			continue
		}
		seen[name] = true
		out = append(out, name)
	}
	return out
}

func selectorCandidates(config map[string]any) []string {
	raw, ok := config["proxy-groups"]
	if !ok {
		return []string{}
	}
	items, ok := raw.([]any)
	if !ok {
		return []string{}
	}
	out := []string{}
	for _, value := range items {
		group, ok := value.(map[string]any)
		if !ok {
			continue
		}
		kind, _ := group["type"].(string)
		if strings.EqualFold(strings.TrimSpace(kind), "select") || strings.EqualFold(strings.TrimSpace(kind), "selector") {
			if name, ok := group["name"].(string); ok && strings.TrimSpace(name) != "" {
				out = append(out, strings.TrimSpace(name))
			}
		}
	}
	return out
}

// ResolveProxyBinding returns the selected target, whether it should be saved,
// and a structured error when a human choice is required.
func ResolveProxyBinding(config map[string]any, bindings Bindings, profileID string) (string, bool, error) {
	candidates := Candidates(config)
	if len(candidates) == 0 {
		return "", false, &BindingError{
			Code: "binding_unavailable", Policy: Proxy, ProfileID: profileID,
			Message: "no usable proxy group is available for the Proxy policy",
		}
	}
	selected := strings.TrimSpace(bindings[Proxy])
	if selected != "" {
		for _, candidate := range candidates {
			if candidate == selected {
				return selected, false, nil
			}
		}
		return "", false, &BindingError{
			Code: "binding_required", Policy: Proxy, ProfileID: profileID,
			Candidates: candidates,
			Message:    fmt.Sprintf("saved Proxy group %q is no longer available", selected),
		}
	}
	if len(candidates) == 1 {
		return candidates[0], true, nil
	}
	selectors := selectorCandidates(config)
	if len(selectors) == 1 {
		return selectors[0], true, nil
	}
	sort.Strings(candidates)
	return "", false, &BindingError{
		Code: "binding_required", Policy: Proxy, ProfileID: profileID,
		Candidates: candidates,
		Message:    "choose a proxy group for the Proxy policy",
	}
}

func ValidateTarget(config map[string]any, target string) error {
	target = strings.TrimSpace(target)
	for _, candidate := range Candidates(config) {
		if candidate == target {
			return nil
		}
	}
	return fmt.Errorf("proxy group %q is not available", target)
}
