package core

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type Info struct {
	PID                 int    `json:"pid"`
	Exe                 string `json:"exe"`
	ConfigPath          string `json:"configPath"`
	ConfigDir           string `json:"configDir"`
	ControllerTransport string `json:"controllerTransport"`
	ControllerTarget    string `json:"controllerTarget"`
}

func ctl() string {
	if x := os.Getenv("MIHOMO_CTL"); x != "" {
		return x
	}
	if exe, e := os.Executable(); e == nil {
		candidate := filepath.Join(filepath.Dir(exe), "mihomo-ctl")
		if _, e = os.Stat(candidate); e == nil {
			return candidate
		}
	}
	return "mihomo-ctl"
}
func Run(args ...string) ([]byte, error) {
	cmd := exec.Command(ctl(), args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, e := cmd.Output()
	if e != nil {
		msg := strings.TrimSpace(stderr.String())
		if len(out) > 0 {
			msg = strings.TrimSpace(string(out))
		}
		if msg == "" {
			msg = e.Error()
		}
		return nil, fmt.Errorf("%s", msg)
	}
	return out, nil
}
func CoreInfo() (Info, error) {
	b, e := Run("coreinfo")
	var x Info
	if e != nil {
		return x, e
	}
	e = json.Unmarshal(b, &x)
	return x, e
}
func Binary() string {
	if x := os.Getenv("MIHOMO_BIN"); x != "" {
		return x
	}
	if x, e := CoreInfo(); e == nil && x.Exe != "" {
		return x.Exe
	}
	if x, e := exec.LookPath("mihomo"); e == nil {
		return x
	}
	return ""
}
func MixedPort() (int, error) {
	b, e := Run("get", "/configs")
	if e != nil {
		return 0, e
	}
	var x map[string]any
	if e = json.Unmarshal(b, &x); e != nil {
		return 0, e
	}
	if port := MixedPortFromConfig(x); port > 0 {
		return port, nil
	}
	return 0, fmt.Errorf("mihomo has no mixed-port")
}

// MixedPortFromConfig returns only Mihomo's mixed listener. A regular HTTP
// port is intentionally not a substitute: the desktop System Proxy writes
// HTTP, HTTPS, and SOCKS to one endpoint and therefore requires mixed-port.
func MixedPortFromConfig(config map[string]any) int {
	switch number := config["mixed-port"].(type) {
	case float64:
		if number > 0 {
			return int(number)
		}
	case json.Number:
		value, _ := number.Int64()
		if value > 0 {
			return int(value)
		}
	case int:
		if number > 0 {
			return number
		}
	}
	return 0
}

// HTTPProxyPort returns a port that can accept an HTTP proxy request. A
// socks-port is intentionally excluded: update-via-proxy uses Go's HTTP
// CONNECT transport and cannot speak SOCKS on that endpoint.
func HTTPProxyPort(config map[string]any) int {
	for _, key := range []string{"mixed-port", "port"} {
		switch number := config[key].(type) {
		case float64:
			if number > 0 {
				return int(number)
			}
		case json.Number:
			value, _ := number.Int64()
			if value > 0 {
				return int(value)
			}
		case int:
			if number > 0 {
				return number
			}
		}
	}
	return 0
}
func Apply(path string) error {
	// Mihomo only permits path-based reloads inside its home directory (or an
	// explicit SAFE_PATHS entry). The manager store is intentionally private
	// under ~/.config, so send the compiled YAML as the documented payload
	// instead of asking the core to read that private path.
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	body := struct {
		Path    string `json:"path"`
		Payload string `json:"payload"`
	}{Payload: string(b)}
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp("", "omarchy-mihomo-apply-*.json")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(encoded); err != nil {
		_ = f.Close()
		return err
	}
	if err = f.Chmod(0600); err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	if _, err = Run("put-file", "/configs?force=true", tmp); err != nil {
		return err
	}
	if _, err = Run("get", "/version"); err != nil {
		return fmt.Errorf("controller check failed: %w", err)
	}
	if _, err = Run("get", "/configs"); err != nil {
		return fmt.Errorf("config check failed: %w", err)
	}
	return nil
}
func ConfigDir(path string) string {
	if path == "" {
		return ""
	}
	return filepath.Dir(path)
}
