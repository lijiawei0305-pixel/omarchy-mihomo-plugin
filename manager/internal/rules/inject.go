package rules

import (
	"fmt"
	"strings"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/policy"
)

// Inject prepends enabled global rules and leaves the source rule array intact.
// It deliberately operates on the already merged config map, so global/profile
// overrides can still change proxy groups without coupling persistence to the
// compiler.
func Inject(config map[string]any, custom []Rule, bindings policy.Bindings) (map[string]any, error) {
	out := cloneMap(config)
	if len(custom) == 0 {
		return out, nil
	}
	inserted := make([]any, 0, len(custom))
	for _, item := range custom {
		if !item.Enabled {
			continue
		}
		normalized, err := NormalizeRule(item)
		if err != nil {
			return nil, err
		}
		target := ""
		switch normalized.Policy {
		case Direct:
			target = "DIRECT"
		case Reject:
			target = "REJECT"
		case Proxy:
			target = strings.TrimSpace(bindings[Proxy])
			if target == "" {
				return nil, fmt.Errorf("proxy policy binding is required")
			}
		}
		inserted = append(inserted, ruleText(normalized, target))
	}
	if len(inserted) == 0 {
		return out, nil
	}
	existing, err := existingRules(out["rules"])
	if err != nil {
		return nil, err
	}
	out["rules"] = append(inserted, existing...)
	return out, nil
}

func ruleText(item Rule, target string) string {
	return strings.ToUpper(item.Match.Type) + "," + item.Match.Value + "," + target
}

func existingRules(value any) ([]any, error) {
	if value == nil {
		return []any{}, nil
	}
	switch items := value.(type) {
	case []any:
		out := make([]any, len(items))
		copy(out, items)
		return out, nil
	case []string:
		out := make([]any, len(items))
		for i, item := range items {
			out[i] = item
		}
		return out, nil
	default:
		return nil, fmt.Errorf("rules must be an array")
	}
}

func cloneMap(in map[string]any) map[string]any {
	out := map[string]any{}
	for key, value := range in {
		switch nested := value.(type) {
		case map[string]any:
			out[key] = cloneMap(nested)
		case []any:
			items := make([]any, len(nested))
			copy(items, nested)
			out[key] = items
		default:
			out[key] = value
		}
	}
	return out
}
