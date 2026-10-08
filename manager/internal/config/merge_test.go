package config

import "testing"

func TestDeepMergeV1(t *testing.T) {
	base := map[string]any{"map": map[string]any{"a": 1, "b": 2}, "scalar": "old", "array": []any{"a", "b"}, "remove": true}
	over := map[string]any{"map": map[string]any{"b": 3, "c": 4}, "scalar": "new", "array": []any{"z"}, "remove": nil}
	got := DeepMerge(base, over)
	if got["scalar"] != "new" {
		t.Fatal("scalar was not replaced")
	}
	if _, ok := got["remove"]; ok {
		t.Fatal("null did not delete key")
	}
	if len(got["array"].([]any)) != 1 || got["array"].([]any)[0] != "z" {
		t.Fatal("array was not replaced")
	}
	m := got["map"].(map[string]any)
	if m["a"] != 1 || m["b"] != 3 || m["c"] != 4 {
		t.Fatalf("bad deep merge: %#v", m)
	}
}
