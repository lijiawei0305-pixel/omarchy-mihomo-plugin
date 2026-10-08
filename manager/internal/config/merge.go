package config

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

func Parse(data []byte) (map[string]any, error) {
	if len(strings.TrimSpace(string(data))) == 0 {
		return map[string]any{}, nil
	}
	var raw any
	if err := yaml.Unmarshal(data, &raw); err != nil {
		return nil, err
	}
	if raw == nil {
		return map[string]any{}, nil
	}
	n, ok := normalize(raw).(map[string]any)
	if !ok {
		return nil, fmt.Errorf("YAML root must be a map")
	}
	return n, nil
}
func normalize(v any) any {
	switch x := v.(type) {
	case map[string]any:
		for k, vv := range x {
			x[k] = normalize(vv)
		}
		return x
	case map[any]any:
		m := map[string]any{}
		for k, vv := range x {
			m[fmt.Sprint(k)] = normalize(vv)
		}
		return m
	case []any:
		for i, vv := range x {
			x[i] = normalize(vv)
		}
		return x
	default:
		return v
	}
}
func clone(v any) any {
	switch x := v.(type) {
	case map[string]any:
		m := map[string]any{}
		for k, vv := range x {
			m[k] = clone(vv)
		}
		return m
	case []any:
		a := make([]any, len(x))
		for i, vv := range x {
			a[i] = clone(vv)
		}
		return a
	default:
		return x
	}
}

// DeepMerge applies the V1 policy: maps recurse, arrays and scalars replace,
// and null in the later map deletes the key.
func DeepMerge(base, overlay map[string]any) map[string]any {
	out := clone(base).(map[string]any)
	for k, v := range overlay {
		if v == nil {
			delete(out, k)
			continue
		}
		if om, ok := v.(map[string]any); ok {
			if bm, ok := out[k].(map[string]any); ok {
				out[k] = DeepMerge(bm, om)
			} else {
				out[k] = clone(om)
			}
			continue
		}
		out[k] = clone(v)
	}
	return out
}
func ParseOptional(data []byte) (map[string]any, error) {
	if len(strings.TrimSpace(string(data))) == 0 {
		return map[string]any{}, nil
	}
	return Parse(data)
}
func Marshal(m map[string]any) ([]byte, error) { return yaml.Marshal(m) }

// ValidateListenerConflicts provides a friendly error before Mihomo's own
// validator runs. Mihomo remains authoritative; this check only turns the
// common duplicate-listener case into an actionable message.
func ValidateListenerConflicts(m map[string]any) error {
	type listener struct {
		key   string
		label string
	}
	listeners := []listener{
		{key: "mixed-port", label: "mixed-port"},
		{key: "port", label: "HTTP port"},
		{key: "socks-port", label: "SOCKS port"},
		{key: "redir-port", label: "redir-port"},
		{key: "tproxy-port", label: "tproxy-port"},
	}
	used := map[int]string{}
	for _, item := range listeners {
		port := configPort(m[item.key])
		if port <= 0 {
			continue
		}
		if previous, ok := used[port]; ok {
			return fmt.Errorf("Port %d is already used by %s (also configured as %s)", port, previous, item.label)
		}
		used[port] = item.label
	}
	return nil
}

func configPort(value any) int {
	switch number := value.(type) {
	case int:
		return number
	case int8:
		return int(number)
	case int16:
		return int(number)
	case int32:
		return int(number)
	case int64:
		return int(number)
	case uint:
		return int(number)
	case uint8:
		return int(number)
	case uint16:
		return int(number)
	case uint32:
		return int(number)
	case uint64:
		return int(number)
	case float64:
		return int(number)
	case float32:
		return int(number)
	case string:
		var port int
		_, _ = fmt.Sscanf(strings.TrimSpace(number), "%d", &port)
		return port
	default:
		return 0
	}
}
