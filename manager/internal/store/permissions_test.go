package store

import (
	"os"
	"testing"
)

func TestEnsureUsesPrivatePermissions(t *testing.T) {
	s := &Store{Home: t.TempDir() + "/home"}
	if e := s.Ensure(); e != nil {
		t.Fatal(e)
	}
	for _, p := range []string{s.Home, s.ProfilesDir(), s.RuntimeDir(), s.OverridesDir(), s.LocksDir()} {
		i, e := os.Stat(p)
		if e != nil {
			t.Fatal(e)
		}
		if i.Mode().Perm() != 0700 {
			t.Fatalf("%s mode %o", p, i.Mode().Perm())
		}
	}
}
