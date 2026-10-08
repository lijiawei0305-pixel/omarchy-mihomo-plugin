package store

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
)

const (
	dirMode  os.FileMode = 0700
	fileMode os.FileMode = 0600
)

type Store struct{ Home string }

func New() *Store {
	home := os.Getenv("OMARCHY_MIHOMO_HOME")
	if home == "" {
		home = filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "omarchy-mihomo")
	}
	if os.Getenv("XDG_CONFIG_HOME") == "" && os.Getenv("OMARCHY_MIHOMO_HOME") == "" {
		home = filepath.Join(os.Getenv("HOME"), ".config", "omarchy-mihomo")
	}
	return &Store{Home: home}
}
func (s *Store) Ensure() error {
	if s.Home == "" {
		return fmt.Errorf("configuration home is empty")
	}
	for _, p := range []string{s.Home, s.ProfilesDir(), s.RuntimeDir(), s.OverridesDir(), s.LocksDir()} {
		if err := os.MkdirAll(p, dirMode); err != nil {
			return err
		}
		_ = os.Chmod(p, dirMode)
	}
	return nil
}
func (s *Store) ProfilesDir() string        { return filepath.Join(s.Home, "profiles") }
func (s *Store) RuntimeDir() string         { return filepath.Join(s.Home, "runtime") }
func (s *Store) OverridesDir() string       { return filepath.Join(s.Home, "overrides") }
func (s *Store) LocksDir() string           { return filepath.Join(s.Home, "locks") }
func (s *Store) IndexPath() string          { return filepath.Join(s.ProfilesDir(), "index.json") }
func (s *Store) SettingsPath() string       { return filepath.Join(s.Home, "settings.json") }
func (s *Store) GlobalOverridePath() string { return filepath.Join(s.OverridesDir(), "global.yaml") }
func (s *Store) CustomRulesPath() string    { return filepath.Join(s.Home, "custom-rules.json") }
func (s *Store) BindingsPath(id string) string {
	return s.ProfilePath(id, "bindings.json")
}
func (s *Store) CurrentPath() string   { return filepath.Join(s.RuntimeDir(), "current.yaml") }
func (s *Store) PreviousPath() string  { return filepath.Join(s.RuntimeDir(), "previous.yaml") }
func (s *Store) CandidatePath() string { return filepath.Join(s.RuntimeDir(), "candidate.yaml") }
func (s *Store) StatePath() string     { return filepath.Join(s.RuntimeDir(), "state.json") }

type RuntimeState struct {
	ActiveProfile   string `json:"activeProfile,omitempty"`
	PreviousProfile string `json:"previousProfile,omitempty"`
	LastAppliedAt   string `json:"lastAppliedAt,omitempty"`
	// Protected contains controller fields captured from the running core.
	// state.json is written with mode 0600 because this may include `secret`.
	Protected map[string]any `json:"protected,omitempty"`
}

func (s *Store) SaveRuntimeState(x RuntimeState) error { return s.WriteJSON(s.StatePath(), x) }
func (s *Store) LockPath() string                      { return filepath.Join(s.LocksDir(), "manager.lock") }
func (s *Store) ProfileDir(id string) string           { return filepath.Join(s.ProfilesDir(), id) }
func (s *Store) ProfilePath(id, name string) string    { return filepath.Join(s.ProfileDir(id), name) }
func (s *Store) Read(path string) ([]byte, error)      { return os.ReadFile(path) }
func (s *Store) WriteAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), dirMode); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tmp-")
	if err != nil {
		return err
	}
	tmp := f.Name()
	ok := false
	defer func() {
		_ = f.Close()
		if !ok {
			_ = os.Remove(tmp)
		}
	}()
	if err = f.Chmod(fileMode); err == nil {
		_, err = f.Write(data)
	}
	if err == nil {
		err = f.Sync()
	}
	if err == nil {
		err = f.Close()
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	if err == nil {
		if d, e := os.Open(filepath.Dir(path)); e == nil {
			_ = d.Sync()
			_ = d.Close()
		}
		ok = true
	}
	return err
}
func (s *Store) WriteJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return s.WriteAtomic(path, b)
}
func (s *Store) Lock() (func(), error) {
	if err := s.Ensure(); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(s.LockPath(), os.O_CREATE|os.O_RDWR, fileMode)
	if err != nil {
		return nil, err
	}
	if err = syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		_ = f.Close()
		return nil, err
	}
	return func() { _ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN); _ = f.Close() }, nil
}
func RandomID() (string, error) {
	b := make([]byte, 16)
	if _, err := io.ReadFull(rand.Reader, b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b)
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32], nil
}
func ValidID(id string) bool {
	if len(id) != 36 || id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' {
		return false
	}
	_, err := hex.DecodeString(id[:8] + id[9:13] + id[14:18] + id[19:23] + id[24:])
	return err == nil
}
func JSONError(err error) error {
	if err == nil {
		return errors.New("unknown error")
	}
	return fmt.Errorf("%w", err)
}
