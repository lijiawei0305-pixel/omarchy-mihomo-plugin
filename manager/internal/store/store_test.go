package store

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAtomicWrite(t *testing.T) {
	s := &Store{Home: t.TempDir()}
	p := filepath.Join(s.Home, "nested", "file")
	if e := s.WriteAtomic(p, []byte("ok")); e != nil {
		t.Fatal(e)
	}
	b, e := os.ReadFile(p)
	if e != nil || string(b) != "ok" {
		t.Fatalf("%q %v", b, e)
	}
	i, _ := os.Stat(p)
	if i.Mode().Perm() != 0600 {
		t.Fatalf("mode %o", i.Mode().Perm())
	}
}
