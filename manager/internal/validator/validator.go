package validator

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func Validate(binary, path string) error {
	if binary == "" {
		return fmt.Errorf("mihomo binary not found (set MIHOMO_BIN)")
	}
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("candidate config path is empty")
	}
	if !filepath.IsAbs(path) {
		return fmt.Errorf("candidate config path must be absolute")
	}
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("candidate config is unavailable: %w", err)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("candidate config is not a regular file")
	}
	cmd := exec.Command(binary, "-t", "-f", path)
	out, err := cmd.CombinedOutput()
	if err != nil {
		message := strings.TrimSpace(string(out))
		if message == "" {
			message = err.Error()
		}
		return fmt.Errorf("%s", message)
	}
	return nil
}
