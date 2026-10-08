package validator

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidateRejectsUnsafePath(t *testing.T) {
	if err := Validate("/bin/true", "relative.yaml"); err == nil {
		t.Fatal("expected relative path to be rejected")
	}
}

func TestValidateRunsMihomoWithAbsolutePath(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte("mode: rule\n"), 0600); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(dir, "args")
	binary := filepath.Join(dir, "mihomo")
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" > " + marker + "\n"
	if err := os.WriteFile(binary, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	if err := Validate(binary, path); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	want := "-t -f " + path + "\n"
	if string(got) != want {
		t.Fatalf("mihomo args = %q, want %q", got, want)
	}
}
