package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/config"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/core"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/doctor"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/fetcher"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/policy"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/profile"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/rules"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/store"
	"github.com/lijiawei0305-pixel/omarchy-mihomo-plugin/manager/internal/validator"
)

var st = store.New()

type response struct {
	OK         bool     `json:"ok"`
	Stage      string   `json:"stage,omitempty"`
	Error      string   `json:"error,omitempty"`
	Message    string   `json:"message,omitempty"`
	Code       string   `json:"code,omitempty"`
	Policy     string   `json:"policy,omitempty"`
	ProfileID  string   `json:"profileId,omitempty"`
	Candidates []string `json:"candidates,omitempty"`
	Data       any      `json:"data,omitempty"`
}

func emit(v any) { _ = json.NewEncoder(os.Stdout).Encode(v) }
func ok(v any)   { emit(response{OK: true, Data: v}) }
func fail(stage string, err error) {
	var bindingErr *policy.BindingError
	_ = errors.As(err, &bindingErr)
	message := err.Error()
	// Keep stdout machine-readable for QML, while retaining a useful
	// diagnostic for interactive callers. Never print raw command arguments
	// here: fetcher/core errors are expected to redact subscription URLs.
	fmt.Fprintf(os.Stderr, "omarchy-mihomo-manager: %s: %s\n", stage, message)
	if bindingErr != nil {
		emit(response{OK: false, Stage: stage, Error: message, Code: bindingErr.Code,
			Policy: bindingErr.Policy, ProfileID: bindingErr.ProfileID,
			Candidates: bindingErr.Candidates, Message: message})
	} else {
		emit(response{OK: false, Stage: stage, Error: message})
	}
	os.Exit(1)
}
func runLocked(fn func() error) error {
	release, err := st.Lock()
	if err != nil {
		return err
	}
	defer release()
	return fn()
}

func main() {
	if err := st.Ensure(); err != nil {
		fail("store", err)
	}
	args := os.Args[1:]
	if len(args) == 0 {
		fail("args", fmt.Errorf("command required"))
	}
	switch args[0] {
	case "status":
		status()
	case "profile":
		profileCommand(args[1:])
	case "config":
		configCommand(args[1:])
	case "reconcile":
		reconcile()
	case "settings":
		settingsCommand(args[1:])
	case "override":
		overrideCommand(args[1:])
	case "rule":
		ruleCommand(args[1:])
	case "policy":
		policyCommand(args[1:])
	case "doctor":
		if len(args) > 1 && args[1] == "tun" {
			doctorTUN(args[2:])
		} else if len(args) > 1 && args[1] == "fix-tun-permission" {
			result, err := doctor.FixTUNPermission()
			if err != nil {
				fail("doctor", err)
			}
			ok(result)
		} else if len(args) > 1 {
			fail("args", fmt.Errorf("unknown doctor command: %s", args[1]))
		} else {
			emit(doctor.Run(st))
		}
	case "redact":
		if len(args) != 2 {
			fail("args", fmt.Errorf("URL required"))
		}
		fmt.Println(redact(args[1]))
	default:
		fail("args", fmt.Errorf("unknown command: %s", args[0]))
	}
}

func doctorTUN(args []string) {
	fs := flag.NewFlagSet("doctor tun", flag.ContinueOnError)
	stack := fs.String("stack", "gvisor", "TUN stack to check")
	if err := fs.Parse(args); err != nil {
		fail("args", err)
	}
	if fs.NArg() != 0 {
		fail("args", fmt.Errorf("unexpected doctor tun argument: %s", fs.Arg(0)))
	}
	emit(doctor.RunTUNPreflight(*stack))
}

func publicMeta(m profile.Meta) profile.Meta {
	if m.URL != "" {
		m.URL = redact(m.URL)
	}
	return m
}
func publicMetas(in []profile.Meta) []profile.Meta {
	out := make([]profile.Meta, len(in))
	for i, m := range in {
		out[i] = publicMeta(m)
	}
	return out
}
func status() {
	idx, err := profile.LoadIndex(st)
	if err != nil {
		fail("store", err)
	}
	list, _ := profile.List(st, idx)
	info, _ := core.CoreInfo()
	ok(map[string]any{"activeProfile": idx.ActiveProfile, "profiles": publicMetas(list), "core": info})
}

func profileCommand(args []string) {
	if len(args) == 0 {
		fail("args", fmt.Errorf("profile command required"))
	}
	switch args[0] {
	case "list":
		idx, err := profile.LoadIndex(st)
		if err != nil {
			fail("store", err)
		}
		list, _ := profile.List(st, idx)
		ok(publicMetas(list))
	case "get":
		requireID(args)
		m, err := profile.LoadMeta(st, args[1])
		if err != nil {
			fail("profile", err)
		}
		ok(publicMeta(m))
	case "source":
		requireID(args)
		b, err := profile.ReadSource(st, args[1])
		if err != nil {
			fail("store", err)
		}
		emit(map[string]any{"ok": true, "id": args[1], "source": string(b)})
	case "url":
		requireID(args)
		m, err := profile.LoadMeta(st, args[1])
		if err != nil {
			fail("profile", err)
		}
		if m.Type != "remote" || m.URL == "" {
			fail("profile", fmt.Errorf("local profile has no subscription URL"))
		}
		// This command is used only by the explicit URL editor flow. All
		// listing/status APIs use publicMeta and remain redacted.
		emit(map[string]any{"ok": true, "id": args[1], "url": m.URL})
	case "override":
		requireID(args)
		b, err := profile.ReadOverride(st, args[1])
		if err != nil {
			fail("store", err)
		}
		emit(map[string]any{"ok": true, "id": args[1], "override": string(b)})
	case "runtime":
		requireID(args)
		if args[1] != currentActive() {
			fail("runtime", fmt.Errorf("profile is not active"))
		}
		b, err := os.ReadFile(st.CurrentPath())
		if err != nil {
			fail("store", err)
		}
		info, _ := os.Stat(st.CurrentPath())
		data := map[string]any{"ok": true, "id": args[1], "runtime": string(b), "path": st.CurrentPath()}
		if info != nil {
			data["size"] = info.Size()
			data["mtime"] = info.ModTime().Unix()
		}
		emit(data)
	case "add":
		addProfile(args[1:])
	case "import-current":
		importCurrent(args[1:])
	case "import":
		importFile(args[1:])
	case "rename":
		requireID(args)
		if len(args) < 3 {
			fail("args", fmt.Errorf("id and name required"))
		}
		name := strings.TrimSpace(strings.Join(args[2:], " "))
		if name == "" {
			fail("args", fmt.Errorf("name must not be empty"))
		}
		if err := runLocked(func() error { return profile.Rename(st, args[1], name) }); err != nil {
			fail("store", err)
		}
		ok(map[string]string{"id": args[1], "name": name})
	case "set-url":
		requireID(args)
		if len(args) < 3 {
			fail("args", fmt.Errorf("id and URL required"))
		}
		rawURL := strings.TrimSpace(args[2])
		parsed, parseErr := url.Parse(rawURL)
		if parseErr != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" || parsed.User != nil || strings.TrimSpace(parsed.Hostname()) == "" {
			fail("args", fmt.Errorf("profile URL must be HTTP or HTTPS"))
		}
		if err := runLocked(func() error {
			meta, err := profile.LoadMeta(st, args[1])
			if err != nil {
				return err
			}
			if meta.Type != "remote" {
				return fmt.Errorf("local profile has no subscription URL")
			}
			meta.URL = rawURL
			meta.ETag = ""
			meta.LastModified = ""
			meta.LastError = ""
			return profile.SaveMeta(st, meta)
		}); err != nil {
			fail("store", err)
		}
		ok(map[string]string{"id": args[1], "url": redact(rawURL)})
	case "delete":
		requireID(args)
		if err := deleteProfile(args[1]); err != nil {
			fail("store", err)
		}
	case "select":
		requireID(args)
		selectProfile(args[1])
	case "update":
		requireID(args)
		result, err := updateProfile(args[1], len(args) > 2 && args[2] == "--via-proxy")
		if err != nil {
			fail(operationStage(err), operationError(err))
		}
		ok(result)
	case "update-due":
		updateDue()
	default:
		fail("args", fmt.Errorf("unknown profile command: %s", args[0]))
	}
}
func requireID(args []string) {
	if len(args) < 2 || !store.ValidID(args[1]) {
		fail("args", fmt.Errorf("valid profile id required"))
	}
}
func deleteProfile(id string) error {
	err := runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		found := false
		for _, item := range idx.Profiles {
			if item == id {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("profile not found")
		}
		// Deleting the active profile would leave the controller running a
		// configuration whose source no longer exists. Require an explicit
		// switch first so index, runtime, and controller stay coherent.
		if idx.ActiveProfile == id {
			return fmt.Errorf("cannot delete the active profile; select another profile first")
		}
		dir := st.ProfileDir(id)
		tombstone := st.ProfileDir(".delete-" + id)
		_ = os.RemoveAll(tombstone)
		if err := os.Rename(dir, tombstone); err != nil {
			return err
		}
		committed := false
		tombstonePreserved := false
		defer func() {
			if committed {
				_ = os.RemoveAll(tombstone)
			} else if !tombstonePreserved {
				_ = os.RemoveAll(tombstone)
			}
		}()
		next := make([]string, 0, len(idx.Profiles))
		for _, item := range idx.Profiles {
			if item != id {
				next = append(next, item)
			}
		}
		idx.Profiles = next
		if err := profile.SaveIndex(st, idx); err != nil {
			if restoreErr := os.Rename(tombstone, dir); restoreErr != nil {
				tombstonePreserved = true
				return rollbackErrors(err, restoreErr)
			}
			return err
		}
		committed = true
		return nil
	})
	if err != nil {
		return err
	}
	ok(map[string]bool{"deleted": true})
	return nil
}

func addProfile(args []string) {
	fs := flag.NewFlagSet("add", flag.ContinueOnError)
	rawURL := fs.String("url", "", "subscription URL")
	name := fs.String("name", "", "profile name")
	interval := fs.Int("update-interval", 21600, "update interval in seconds")
	activateIfEmpty := fs.Bool("activate-if-empty", false, "activate this profile when no profile is active")
	if err := fs.Parse(args); err != nil {
		fail("args", err)
	}
	if *rawURL == "" || strings.TrimSpace(*name) == "" {
		fail("args", fmt.Errorf("--url and --name are required"))
	}
	if *interval < 0 {
		fail("args", fmt.Errorf("update interval must not be negative"))
	}
	result, err := fetcher.Fetch(*rawURL, "", "", "", false, 0)
	if err != nil {
		fail("fetch", err)
	}
	if _, err = config.Parse(result.Body); err != nil {
		fail("parse", err)
	}
	if err = validateCompiled(result.Body, []byte("{}\n"), true); err != nil {
		fail("validate", err)
	}
	id, err := store.RandomID()
	if err != nil {
		fail("store", err)
	}
	meta := profile.TouchSuccess(profile.Meta{ID: id, Name: strings.TrimSpace(*name), Type: "remote", URL: *rawURL, UpdateIntervalSec: *interval}, result.ETag, result.LastModified)
	setSubscriptionInfo(&meta, result)
	err = runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		oldIndex := profile.Index{Profiles: append([]string(nil), idx.Profiles...), ActiveProfile: idx.ActiveProfile}
		activate := *activateIfEmpty && idx.ActiveProfile == ""
		var oldState []byte
		var hadState bool
		var oldRuntime runtimeSnapshot
		var oldBinding []byte
		var hadBinding bool
		if activate {
			oldState, hadState, err = snapshot(st.StatePath())
			if err != nil {
				return err
			}
			oldRuntime, err = snapshotRuntime()
			if err != nil {
				return err
			}
			oldBinding, hadBinding, err = snapshot(st.BindingsPath(id))
			if err != nil {
				return err
			}
		}
		committed := false
		defer func() {
			if !committed {
				_ = profile.Delete(st, id)
			}
		}()
		if err := profile.Add(st, meta, result.Body, []byte("{}\n")); err != nil {
			return err
		}
		idx.Profiles = append(idx.Profiles, id)
		if activate {
			if err = applyLocked(id, meta, result.Body); err != nil {
				var bindingErr *policy.BindingError
				if errors.As(err, &bindingErr) {
					// Keep a valid, inactive profile when the first profile
					// needs a human proxy-group choice. The UI can save the
					// binding and retry select without downloading again.
					if saveErr := profile.SaveIndex(st, idx); saveErr != nil {
						return rollbackErrors(err, saveErr)
					}
					committed = true
				}
				return err
			}
			idx.ActiveProfile = id
		}
		if err = profile.SaveIndex(st, idx); err != nil {
			if activate {
				runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
				stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
				bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
				indexErr := profile.SaveIndex(st, oldIndex)
				return rollbackErrors(err, runtimeErr, stateErr, bindingErr, indexErr)
			}
			return err
		}
		committed = true
		return nil
	})
	if err != nil {
		fail("store", err)
	}
	ok(publicMeta(meta))
}

func importCurrent(args []string) {
	fs := flag.NewFlagSet("import-current", flag.ContinueOnError)
	name := fs.String("name", "Local Config", "profile name")
	if err := fs.Parse(args); err != nil {
		fail("args", err)
	}
	info, err := core.CoreInfo()
	if err != nil {
		fail("coreinfo", err)
	}
	if info.ConfigPath == "" {
		fail("coreinfo", fmt.Errorf("running config path unavailable"))
	}
	source, err := os.ReadFile(info.ConfigPath)
	if err != nil {
		fail("read", err)
	}
	if _, err = config.Parse(source); err != nil {
		fail("parse", err)
	}
	if err = validateCompiled(source, []byte("{}\n"), false); err != nil {
		fail("validate", err)
	}
	id, err := store.RandomID()
	if err != nil {
		fail("store", err)
	}
	meta := profile.Meta{ID: id, Name: strings.TrimSpace(*name), Type: "local"}
	err = runLocked(func() error {
		if err := profile.Add(st, meta, source, []byte("{}\n")); err != nil {
			return err
		}
		idx, err := profile.LoadIndex(st)
		if err != nil {
			_ = profile.Delete(st, id)
			return err
		}
		idx.Profiles = append(idx.Profiles, id)
		if err = profile.SaveIndex(st, idx); err != nil {
			_ = profile.Delete(st, id)
			return err
		}
		return nil
	})
	if err != nil {
		fail("store", err)
	}
	ok(publicMeta(meta))
}

func importFile(args []string) {
	fs := flag.NewFlagSet("import", flag.ContinueOnError)
	path := fs.String("file", "", "local YAML file")
	name := fs.String("name", "Local Config", "profile name")
	if err := fs.Parse(args); err != nil {
		fail("args", err)
	}
	if strings.TrimSpace(*path) == "" || strings.TrimSpace(*name) == "" {
		fail("args", fmt.Errorf("--file and --name are required"))
	}
	source, err := os.ReadFile(*path)
	if err != nil {
		fail("read", err)
	}
	if _, err = config.Parse(source); err != nil {
		fail("parse", err)
	}
	if err = validateCompiled(source, []byte("{}\n"), false); err != nil {
		fail("validate", err)
	}
	id, err := store.RandomID()
	if err != nil {
		fail("store", err)
	}
	meta := profile.Meta{ID: id, Name: strings.TrimSpace(*name), Type: "local"}
	err = runLocked(func() error {
		if err := profile.Add(st, meta, source, []byte("{}\n")); err != nil {
			return err
		}
		idx, err := profile.LoadIndex(st)
		if err != nil {
			_ = profile.Delete(st, id)
			return err
		}
		idx.Profiles = append(idx.Profiles, id)
		if err = profile.SaveIndex(st, idx); err != nil {
			_ = profile.Delete(st, id)
			return err
		}
		return nil
	})
	if err != nil {
		fail("store", err)
	}
	ok(publicMeta(meta))
}

func selectProfile(id string) {
	err := runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		found := false
		for _, candidate := range idx.Profiles {
			if candidate == id {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf("profile not found")
		}
		meta, err := profile.LoadMeta(st, id)
		if err != nil {
			return err
		}
		oldIndex := idx
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		oldBinding, hadBinding, err := snapshot(st.BindingsPath(id))
		if err != nil {
			return err
		}
		if err := applyLocked(id, meta, nil); err != nil {
			return err
		}
		idx.ActiveProfile = id
		if err = profile.SaveIndex(st, idx); err != nil {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
			indexErr := profile.SaveIndex(st, oldIndex)
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
			if runtimeErr != nil || indexErr != nil || stateErr != nil || bindingErr != nil {
				return rollbackErrors(err, runtimeErr, indexErr, stateErr, bindingErr)
			}
			return err
		}
		return nil
	})
	if err != nil {
		fail("apply", err)
	}
	ok(map[string]string{"activeProfile": id})
}

type operationFailure struct {
	stage string
	err   error
}

func (e operationFailure) Error() string { return e.err.Error() }
func operationStage(err error) string {
	if e, ok := err.(operationFailure); ok {
		return e.stage
	}
	return "profile"
}
func operationError(err error) error {
	if e, ok := err.(operationFailure); ok {
		return e.err
	}
	return err
}

func rollbackErrors(primary error, rollbackErrs ...error) error {
	parts := []string{primary.Error()}
	for _, err := range rollbackErrs {
		if err != nil {
			parts = append(parts, "rollback: "+err.Error())
		}
	}
	return fmt.Errorf("%s", strings.Join(parts, "; "))
}
func snapshot(path string) ([]byte, bool, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, false, nil
	}
	return b, err == nil, err
}
func restoreSnapshot(path string, data []byte, existed bool) error {
	if !existed {
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			return err
		}
		return nil
	}
	return st.WriteAtomic(path, data)
}

func updateDue() {
	idx, err := profile.LoadIndex(st)
	if err != nil {
		fail("store", err)
	}
	results := []any{}
	failures := []string{}
	now := time.Now()
	for _, id := range idx.Profiles {
		meta, loadErr := profile.LoadMeta(st, id)
		if loadErr != nil || !profile.Due(meta, now) {
			continue
		}
		result, updateErr := updateProfile(id, meta.UpdateViaProxy)
		if updateErr != nil {
			failures = append(failures, id+": "+updateErr.Error())
			continue
		}
		results = append(results, result)
	}
	if len(failures) > 0 {
		fail("update", fmt.Errorf("%s", strings.Join(failures, "; ")))
	}
	ok(map[string]any{"updated": results})
}

func updateProfile(id string, viaProxy bool) (map[string]any, error) {
	meta, err := profile.LoadMeta(st, id)
	if err != nil {
		return nil, operationFailure{"profile", err}
	}
	if meta.Type != "remote" {
		return map[string]any{"id": id, "updated": false, "reason": "local profile"}, nil
	}
	port := 0
	if viaProxy {
		port, err = core.MixedPort()
		if err != nil {
			return nil, operationFailure{"fetch", err}
		}
	}
	result, err := fetcher.Fetch(meta.URL, meta.FetchUserAgent, meta.ETag, meta.LastModified, viaProxy, port)
	if err != nil {
		_ = runLocked(func() error {
			current, loadErr := profile.LoadMeta(st, id)
			if loadErr != nil || current.URL != meta.URL {
				return nil
			}
			return profile.SaveMeta(st, profile.SetError(current, err))
		})
		return nil, operationFailure{"fetch", err}
	}
	if result.NotModified {
		err = runLocked(func() error {
			current, loadErr := profile.LoadMeta(st, id)
			if loadErr != nil {
				return loadErr
			}
			if current.URL != meta.URL {
				return fmt.Errorf("profile changed during update; retry")
			}
			etag, lastModified := result.ETag, result.LastModified
			if etag == "" {
				etag = current.ETag
			}
			if lastModified == "" {
				lastModified = current.LastModified
			}
			next := profile.TouchSuccess(current, etag, lastModified)
			setSubscriptionInfo(&next, result)
			return profile.SaveMeta(st, next)
		})
		if err != nil {
			return nil, operationFailure{"store", err}
		}
		return map[string]any{"id": id, "notModified": true}, nil
	}
	if _, err = config.Parse(result.Body); err != nil {
		_ = runLocked(func() error {
			current, loadErr := profile.LoadMeta(st, id)
			if loadErr != nil || current.URL != meta.URL {
				return nil
			}
			return profile.SaveMeta(st, profile.SetError(current, err))
		})
		return nil, operationFailure{"parse", err}
	}
	newMeta := profile.TouchSuccess(meta, result.ETag, result.LastModified)
	active := false
	err = runLocked(func() error {
		// Re-read the index while holding the lock. A profile can be selected
		// while the subscription request is in flight; deciding active/inactive
		// from the earlier snapshot could otherwise skip the required apply.
		idx, indexErr := profile.LoadIndex(st)
		if indexErr != nil {
			return operationFailure{"store", indexErr}
		}
		currentMeta, metaErr := profile.LoadMeta(st, id)
		if metaErr != nil {
			return operationFailure{"store", metaErr}
		}
		if currentMeta.URL != meta.URL {
			return operationFailure{"store", fmt.Errorf("profile changed during update; retry")}
		}
		newMeta = profile.TouchSuccess(currentMeta, result.ETag, result.LastModified)
		setSubscriptionInfo(&newMeta, result)
		active = idx.ActiveProfile == id
		oldSource, readErr := profile.ReadSource(st, id)
		if readErr != nil {
			return operationFailure{"store", readErr}
		}
		oldBinding, hadBinding, bindingSnapshotErr := snapshot(st.BindingsPath(id))
		if bindingSnapshotErr != nil {
			return operationFailure{"store", bindingSnapshotErr}
		}
		if !active {
			candidate, compileErr := compile(id, result.Body)
			if compileErr != nil {
				bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
				if saveErr := profile.SaveMeta(st, profile.SetError(currentMeta, compileErr)); saveErr != nil {
					return operationFailure{"rollback", rollbackErrors(compileErr, bindingErr, saveErr)}
				}
				if bindingErr != nil {
					return operationFailure{"rollback", rollbackErrors(compileErr, bindingErr)}
				}
				return operationFailure{"compile", compileErr}
			}
			if validateErr := validateCandidate(candidate); validateErr != nil {
				bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
				if saveErr := profile.SaveMeta(st, profile.SetError(currentMeta, validateErr)); saveErr != nil {
					return operationFailure{"rollback", rollbackErrors(validateErr, bindingErr, saveErr)}
				}
				if bindingErr != nil {
					return operationFailure{"rollback", rollbackErrors(validateErr, bindingErr)}
				}
				return operationFailure{"validate", validateErr}
			}
		}
		if active {
			oldState, hadState, stateErr := snapshot(st.StatePath())
			if stateErr != nil {
				return operationFailure{"store", stateErr}
			}
			oldRuntime, runtimeSnapshotErr := snapshotRuntime()
			if runtimeSnapshotErr != nil {
				return operationFailure{"store", runtimeSnapshotErr}
			}
			if applyErr := applyLocked(id, currentMeta, result.Body); applyErr != nil {
				_ = profile.SaveMeta(st, profile.SetError(currentMeta, applyErr))
				return operationFailure{"apply", applyErr}
			}
			if writeErr := st.WriteAtomic(st.ProfilePath(id, "source.yaml"), result.Body); writeErr != nil {
				rollbackErr := restoreAppliedRuntime(oldSource, id, oldState, hadState, oldRuntime)
				bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
				if rollbackErr != nil || bindingErr != nil {
					return operationFailure{"rollback", rollbackErrors(writeErr, rollbackErr, bindingErr)}
				}
				return operationFailure{"store", writeErr}
			}
			if saveErr := profile.SaveMeta(st, newMeta); saveErr != nil {
				sourceErr := st.WriteAtomic(st.ProfilePath(id, "source.yaml"), oldSource)
				rollbackErr := restoreAppliedRuntime(oldSource, id, oldState, hadState, oldRuntime)
				bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
				if sourceErr != nil || rollbackErr != nil || bindingErr != nil {
					return operationFailure{"rollback", rollbackErrors(saveErr, rollbackErr, sourceErr, bindingErr)}
				}
				return operationFailure{"store", saveErr}
			}
			return nil
		}
		if writeErr := st.WriteAtomic(st.ProfilePath(id, "source.yaml"), result.Body); writeErr != nil {
			bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
			if bindingErr != nil {
				return operationFailure{"rollback", rollbackErrors(writeErr, bindingErr)}
			}
			return operationFailure{"store", writeErr}
		}
		if saveErr := profile.SaveMeta(st, newMeta); saveErr != nil {
			sourceErr := st.WriteAtomic(st.ProfilePath(id, "source.yaml"), oldSource)
			bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
			if sourceErr != nil || bindingErr != nil {
				return operationFailure{"rollback", rollbackErrors(saveErr, sourceErr, bindingErr)}
			}
			return operationFailure{"store", saveErr}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"id": id, "updated": true, "active": active}, nil
}

func setSubscriptionInfo(meta *profile.Meta, result fetcher.Result) {
	if meta == nil || !result.HasSubscriptionInfo {
		return
	}
	meta.SubscriptionInfo = profile.SubscriptionInfo{
		Upload:   result.SubscriptionInfo.Upload,
		Download: result.SubscriptionInfo.Download,
		Total:    result.SubscriptionInfo.Total,
		Expire:   result.SubscriptionInfo.Expire,
	}
}

func snapshotRuntime() (runtimeSnapshot, error) {
	var out runtimeSnapshot
	var err error
	if out.current.data, out.current.existed, err = snapshot(st.CurrentPath()); err != nil {
		return out, err
	}
	if out.previous.data, out.previous.existed, err = snapshot(st.PreviousPath()); err != nil {
		return out, err
	}
	if out.candidate.data, out.candidate.existed, err = snapshot(st.CandidatePath()); err != nil {
		return out, err
	}
	return out, nil
}

type runtimeFileSnapshot struct {
	data    []byte
	existed bool
}

type runtimeSnapshot struct {
	current, previous, candidate runtimeFileSnapshot
}

type restoreMode struct {
	applyPreviousIfCurrentMissing bool
}

func restoreRuntime(old runtimeSnapshot) error {
	return restoreRuntimeWithFallback(old, restoreMode{})
}

func restoreRuntimeFiles(old runtimeSnapshot) error {
	var errs []error
	if err := restoreSnapshot(st.PreviousPath(), old.previous.data, old.previous.existed); err != nil {
		errs = append(errs, err)
	}
	if err := restoreSnapshot(st.CandidatePath(), old.candidate.data, old.candidate.existed); err != nil {
		errs = append(errs, err)
	}
	if len(errs) > 0 {
		return rollbackErrors(fmt.Errorf("runtime file restoration failed"), errs...)
	}
	return nil
}

func restoreRuntimeWithFallback(old runtimeSnapshot, mode restoreMode) error {
	var errs []error
	if old.current.existed {
		if err := st.WriteAtomic(st.CurrentPath(), old.current.data); err != nil {
			errs = append(errs, err)
		} else if err := core.Apply(st.CurrentPath()); err != nil {
			errs = append(errs, err)
		}
	} else {
		if mode.applyPreviousIfCurrentMissing {
			// current.yaml did not exist before this transaction. backupRuntime
			// copied the live core config to previous.yaml.
			if err := applyPrevious(); err != nil {
				errs = append(errs, err)
			}
		}
		if err := os.Remove(st.CurrentPath()); err != nil && !os.IsNotExist(err) {
			errs = append(errs, err)
		}
	}
	if err := restoreRuntimeFiles(old); err != nil {
		errs = append(errs, err)
	}
	if len(errs) > 0 {
		return rollbackErrors(fmt.Errorf("runtime restoration failed"), errs...)
	}
	return nil
}

func restoreAppliedRuntime(oldSource []byte, id string, oldState []byte, hadState bool, oldRuntime runtimeSnapshot) error {
	var errs []error
	if id != "" && oldSource != nil {
		if err := st.WriteAtomic(st.ProfilePath(id, "source.yaml"), oldSource); err != nil {
			errs = append(errs, err)
		}
	}
	if err := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true}); err != nil {
		errs = append(errs, err)
	}
	if err := restoreSnapshot(st.StatePath(), oldState, hadState); err != nil {
		errs = append(errs, err)
	}
	if len(errs) > 0 {
		return rollbackErrors(fmt.Errorf("runtime restoration failed"), errs...)
	}
	return nil
}

func configCommand(args []string) {
	if len(args) == 0 {
		fail("args", fmt.Errorf("config command required"))
	}
	switch args[0] {
	case "compile":
		requireID(args)
		err := runLocked(func() error {
			b, err := compile(args[1], nil)
			if err != nil {
				return err
			}
			return st.WriteAtomic(st.CandidatePath(), b)
		})
		if err != nil {
			fail("compile", err)
		}
		emit(map[string]any{"ok": true, "stage": "compile", "path": st.CandidatePath()})
	case "apply":
		requireID(args)
		selectProfile(args[1])
	case "rollback":
		rollback()
	default:
		fail("args", fmt.Errorf("unknown config command: %s", args[0]))
	}
}

func saveUpdatedSource(s *store.Store, id string, body []byte) error {
	if _, err := config.Parse(body); err != nil {
		return fmt.Errorf("parse: %w", err)
	}
	return s.WriteAtomic(s.ProfilePath(id, "source.yaml"), body)
}

type compileOptions struct {
	globalOverride  []byte
	profileOverride []byte
	customRules     []rules.Rule
	customRulesSet  bool
	bindings        policy.Bindings
	bindingsSet     bool
	settings        *profile.Settings
}

type compilePlan struct {
	compiled       []byte
	bindings       policy.Bindings
	bindingChanged bool
}

func readGlobalOverride() ([]byte, error) {
	b, err := os.ReadFile(st.GlobalOverridePath())
	if os.IsNotExist(err) {
		return nil, nil
	}
	return b, err
}

func prepareCompile(id string, source []byte, options compileOptions) (compilePlan, error) {
	meta, err := profile.LoadMeta(st, id)
	if err != nil {
		return compilePlan{}, err
	}
	untrusted := meta.Type == "remote"
	if source == nil {
		source, err = profile.ReadSource(st, id)
		if err != nil {
			return compilePlan{}, err
		}
	}
	global := options.globalOverride
	if global == nil {
		var err error
		global, err = readGlobalOverride()
		if err != nil {
			return compilePlan{}, err
		}
	}
	override := options.profileOverride
	if override == nil {
		var err error
		override, err = profile.ReadOverride(st, id)
		if err != nil {
			return compilePlan{}, err
		}
	}
	custom := options.customRules
	if !options.customRulesSet {
		collection, err := rules.Load(st)
		if err != nil {
			return compilePlan{}, err
		}
		custom = collection.Rules
	}
	bindings := options.bindings
	if !options.bindingsSet {
		var err error
		bindings, err = policy.Load(st, id)
		if err != nil {
			return compilePlan{}, err
		}
	}
	if bindings == nil {
		bindings = policy.Bindings{}
	}
	bindings = policy.Clone(bindings)
	if rules.NeedsProxyBinding(custom) {
		effective, err := config.MergeLayers(source, global, override)
		if err != nil {
			return compilePlan{}, err
		}
		target, changed, err := policy.ResolveProxyBinding(effective, bindings, id)
		if err != nil {
			return compilePlan{}, err
		}
		if changed {
			bindings[policy.Proxy] = target
		}
		options.bindings = bindings
		options.bindingsSet = true
		plan, err := compileWithOptions(source, global, override, custom, bindings, options.settings, untrusted)
		if err != nil {
			return compilePlan{}, err
		}
		return compilePlan{compiled: plan, bindings: bindings, bindingChanged: changed}, nil
	}
	compiled, err := compileWithOptions(source, global, override, custom, bindings, options.settings, untrusted)
	if err != nil {
		return compilePlan{}, err
	}
	return compilePlan{compiled: compiled, bindings: bindings}, nil
}

func compileWithOptions(source, global, override []byte, custom []rules.Rule, bindings policy.Bindings, settingsOverride *profile.Settings, untrusted bool) ([]byte, error) {
	settings := settingsOverride
	if settings == nil {
		loaded, err := profile.LoadSettings(st)
		if err != nil {
			return nil, err
		}
		settings = &loaded
	}
	protected, err := protectedController()
	if err != nil {
		return nil, err
	}
	return (config.Compiler{}).Compile(config.CompileInput{
		Source: source, GlobalOverride: global, ProfileOverride: override,
		CustomRules: custom, Bindings: bindings, Settings: *settings, Protected: protected,
		UntrustedSource: untrusted,
	})
}

func compile(id string, source []byte) ([]byte, error) {
	plan, err := prepareCompile(id, source, compileOptions{})
	if err != nil {
		return nil, err
	}
	if plan.bindingChanged {
		if err := policy.Save(st, id, plan.bindings); err != nil {
			return nil, err
		}
	}
	return plan.compiled, nil
}

func loadRuntimeState() (store.RuntimeState, bool, error) {
	var state store.RuntimeState
	b, err := os.ReadFile(st.StatePath())
	if os.IsNotExist(err) {
		return state, false, nil
	}
	if err != nil {
		return state, false, err
	}
	if err := json.Unmarshal(b, &state); err != nil {
		return state, true, err
	}
	return state, true, nil
}

// protectedController returns the last known controller fields. A nil map
// means there was no running core to inspect; an empty non-nil map means the
// running config was inspected and contained none of those fields.
func protectedController() (map[string]any, error) {
	state, exists, err := loadRuntimeState()
	if err != nil {
		return nil, err
	}
	info, infoErr := core.CoreInfo()
	if infoErr == nil && info.ConfigPath != "" {
		protected, readErr := config.ReadProtected(info.ConfigPath)
		if readErr == nil {
			return withLiveController(protected, info), nil
		}
		if exists && state.Protected != nil {
			return state.Protected, nil
		}
		if live := liveController(info); live != nil {
			return live, nil
		}
		return nil, fmt.Errorf("read running config for protected fields: %w", readErr)
	}
	if exists && state.Protected != nil {
		return state.Protected, nil
	}
	if infoErr == nil {
		if live := liveController(info); live != nil {
			return live, nil
		}
	}
	// A stopped core has no live controller snapshot. Preserve source fields
	// until the first apply can capture them; an unavailable config file should
	// not make adding a profile impossible.
	return nil, nil
}

func liveController(info core.Info) map[string]any {
	if strings.TrimSpace(info.ControllerTarget) == "" {
		return nil
	}
	switch info.ControllerTransport {
	case "unix":
		return map[string]any{"external-controller-unix": info.ControllerTarget}
	case "tcp":
		return map[string]any{"external-controller": info.ControllerTarget}
	default:
		if strings.HasPrefix(info.ControllerTarget, "/") {
			return map[string]any{"external-controller-unix": info.ControllerTarget}
		}
		return map[string]any{"external-controller": info.ControllerTarget}
	}
}

func withLiveController(protected map[string]any, info core.Info) map[string]any {
	if protected == nil {
		protected = map[string]any{}
	}
	for key, value := range liveController(info) {
		if _, ok := protected[key]; !ok {
			protected[key] = value
		}
	}
	return protected
}

func compileBytes(source, global, override []byte, untrusted bool) ([]byte, error) {
	settings, err := profile.LoadSettings(st)
	if err != nil {
		return nil, err
	}
	protected, err := protectedController()
	if err != nil {
		return nil, err
	}
	return (config.Compiler{}).Compile(config.CompileInput{
		Source: source, GlobalOverride: global, ProfileOverride: override,
		Settings: settings, Protected: protected, UntrustedSource: untrusted,
	})
}

func validateCandidate(b []byte) error {
	if err := validateListenerConflicts(b); err != nil {
		return err
	}
	f, err := os.CreateTemp(st.RuntimeDir(), ".validate-*.yaml")
	if err != nil {
		return err
	}
	path := f.Name()
	defer os.Remove(path)
	if err = f.Chmod(0600); err == nil {
		_, err = f.Write(b)
	}
	if err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return validator.Validate(core.Binary(), path)
}

func validateListenerConflicts(b []byte) error {
	parsed, err := config.Parse(b)
	if err != nil {
		return fmt.Errorf("parse candidate: %w", err)
	}
	return config.ValidateListenerConflicts(parsed)
}

func validateCompiled(source, override []byte, untrusted bool) error {
	b, err := compileBytes(source, nil, override, untrusted)
	if err != nil {
		return err
	}
	return validateCandidate(b)
}

func applyLocked(id string, meta profile.Meta, source []byte) error {
	return applyLockedWithOptions(id, meta, source, compileOptions{})
}

func applyLockedWithOptions(id string, meta profile.Meta, source []byte, options compileOptions) error {
	oldState, hadState, err := snapshot(st.StatePath())
	if err != nil {
		return err
	}
	oldRuntime, err := snapshotRuntime()
	if err != nil {
		return err
	}
	oldBinding, hadBinding, err := snapshot(st.BindingsPath(id))
	if err != nil {
		return err
	}
	plan, err := prepareCompile(id, source, options)
	if err != nil {
		return fmt.Errorf("compile: %w", err)
	}
	b := plan.compiled
	if err = validateListenerConflicts(b); err != nil {
		return err
	}
	if err = st.WriteAtomic(st.CandidatePath(), b); err != nil {
		return err
	}
	if err = validator.Validate(core.Binary(), st.CandidatePath()); err != nil {
		fileErr := restoreRuntimeFiles(oldRuntime)
		if fileErr != nil {
			return rollbackErrors(fmt.Errorf("validate: %w", err), fileErr)
		}
		return fmt.Errorf("validate: %w", err)
	}
	if err = backupRuntime(); err != nil {
		primary := fmt.Errorf("backup: %w", err)
		if fileErr := restoreRuntimeFiles(oldRuntime); fileErr != nil {
			return rollbackErrors(primary, fileErr)
		}
		return primary
	}

	restore := func(primary error) error {
		runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
		stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
		bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
		if runtimeErr != nil || stateErr != nil || bindingErr != nil {
			return rollbackErrors(primary, runtimeErr, stateErr, bindingErr)
		}
		return primary
	}
	if err = core.Apply(st.CandidatePath()); err != nil {
		return restore(fmt.Errorf("apply: %w", err))
	}
	if plan.bindingChanged {
		if err = policy.Save(st, id, plan.bindings); err != nil {
			return restore(fmt.Errorf("save policy binding: %w", err))
		}
	}
	if err = st.WriteAtomic(st.CurrentPath(), b); err != nil {
		return restore(fmt.Errorf("promote runtime: %w", err))
	}
	protected, protectedErr := protectedController()
	if protectedErr != nil {
		return restore(fmt.Errorf("capture protected controller: %w", protectedErr))
	}
	state, _, stateErr := loadRuntimeState()
	if stateErr != nil {
		return restore(fmt.Errorf("load runtime state: %w", stateErr))
	}
	state.PreviousProfile = state.ActiveProfile
	state.ActiveProfile = id
	state.LastAppliedAt = time.Now().UTC().Format(time.RFC3339)
	if protected != nil {
		state.Protected = protected
	}
	if err = st.SaveRuntimeState(state); err != nil {
		return restore(fmt.Errorf("save runtime state: %w", err))
	}
	return nil
}
func restorePreviousRuntime() error {
	// Read before applying: if the backup disappeared, do not leave the core
	// on the previous config while current.yaml still points at the candidate.
	previous, err := os.ReadFile(st.PreviousPath())
	if err != nil {
		return err
	}
	if err = applyPrevious(); err != nil {
		return err
	}
	if err = st.WriteAtomic(st.CurrentPath(), previous); err != nil {
		return err
	}
	return nil
}
func backupRuntime() error {
	if b, err := os.ReadFile(st.CurrentPath()); err == nil {
		return st.WriteAtomic(st.PreviousPath(), b)
	} else if !os.IsNotExist(err) {
		return err
	}
	info, err := core.CoreInfo()
	if err != nil || info.ConfigPath == "" {
		if err != nil {
			return err
		}
		return fmt.Errorf("no current runtime to back up")
	}
	b, err := os.ReadFile(info.ConfigPath)
	if err != nil {
		return err
	}
	return st.WriteAtomic(st.PreviousPath(), b)
}
func applyPrevious() error { return core.Apply(st.PreviousPath()) }
func rollback() {
	active := ""
	err := runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		oldIndex := idx
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		state, _, err := loadRuntimeState()
		if err != nil {
			return err
		}
		restore := func(primary error) error {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{})
			indexErr := profile.SaveIndex(st, oldIndex)
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			if runtimeErr != nil || indexErr != nil || stateErr != nil {
				return rollbackErrors(primary, runtimeErr, indexErr, stateErr)
			}
			return primary
		}

		if err := validator.Validate(core.Binary(), st.PreviousPath()); err != nil {
			return fmt.Errorf("validate: %w", err)
		}
		if err := applyPrevious(); err != nil {
			return restore(fmt.Errorf("apply: %w", err))
		}
		previous, err := os.ReadFile(st.PreviousPath())
		if err != nil {
			return restore(err)
		}
		if err = st.WriteAtomic(st.CurrentPath(), previous); err != nil {
			return restore(fmt.Errorf("promote rollback: %w", err))
		}
		// A rollback swaps the two runtime generations. Keeping the old current
		// config as previous makes a second rollback coherent with the profile
		// index and preserves a useful recovery point.
		if oldRuntime.current.existed {
			if err = st.WriteAtomic(st.PreviousPath(), oldRuntime.current.data); err != nil {
				return restore(fmt.Errorf("swap rollback backup: %w", err))
			}
		} else if err = os.Remove(st.PreviousPath()); err != nil && !os.IsNotExist(err) {
			return restore(fmt.Errorf("remove rollback backup: %w", err))
		}

		previousProfile := state.PreviousProfile
		if !store.ValidID(previousProfile) {
			previousProfile = ""
		} else if _, err = profile.LoadMeta(st, previousProfile); err != nil {
			previousProfile = ""
		}
		idx.ActiveProfile = previousProfile
		state.PreviousProfile = oldIndex.ActiveProfile
		state.ActiveProfile = previousProfile
		state.LastAppliedAt = time.Now().UTC().Format(time.RFC3339)
		if err = st.SaveRuntimeState(state); err != nil {
			return restore(fmt.Errorf("save runtime state: %w", err))
		}
		if err = profile.SaveIndex(st, idx); err != nil {
			return restore(fmt.Errorf("save profile index: %w", err))
		}
		active = previousProfile
		return nil
	})
	if err != nil {
		fail("rollback", err)
	}
	ok(map[string]any{"rolledBack": true, "activeProfile": active})
}
func reconcile() {
	err := runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		if idx.ActiveProfile == "" {
			return nil
		}
		meta, err := profile.LoadMeta(st, idx.ActiveProfile)
		if err != nil {
			return err
		}
		return applyLocked(idx.ActiveProfile, meta, nil)
	})
	if err != nil {
		fail("reconcile", err)
	}
	idx, err := profile.LoadIndex(st)
	if err != nil {
		fail("store", err)
	}
	ok(map[string]bool{"reconciled": idx.ActiveProfile != ""})
}

func overrideCommand(args []string) {
	if len(args) == 0 {
		fail("args", fmt.Errorf("override command required"))
	}
	switch args[0] {
	case "global":
		if len(args) == 1 || args[1] == "get" {
			b, err := readOverride(st.GlobalOverridePath())
			if err != nil {
				fail("store", err)
			}
			emit(map[string]any{"ok": true, "scope": "global", "override": string(b), "empty": overrideIsEmpty(b)})
			return
		}
		if args[1] == "set" || args[1] == "set-file" {
			data, err := readOverrideInput(args[1:], 1)
			if err != nil {
				fail("args", err)
			}
			if err = setOverride("global", "", data); err != nil {
				fail("apply", err)
			}
			ok(map[string]string{"scope": "global", "saved": "true"})
			return
		}
		fail("args", fmt.Errorf("unknown global override command: %s", args[1]))
	case "profile":
		if len(args) < 2 || !store.ValidID(args[1]) {
			fail("args", fmt.Errorf("valid profile id required"))
		}
		if len(args) == 2 || args[2] == "get" {
			b, err := profile.ReadOverride(st, args[1])
			if err != nil {
				fail("store", err)
			}
			emit(map[string]any{"ok": true, "scope": "profile", "id": args[1], "override": string(b)})
			return
		}
		if args[2] == "set" || args[2] == "set-file" {
			data, err := readOverrideInput(args[2:], 1)
			if err != nil {
				fail("args", err)
			}
			if err = setOverride("profile", args[1], data); err != nil {
				fail("apply", err)
			}
			ok(map[string]string{"scope": "profile", "id": args[1], "saved": "true"})
			return
		}
		fail("args", fmt.Errorf("unknown profile override command: %s", args[2]))
	case "open-global":
		openOverride(st.GlobalOverridePath())
	case "open-profile":
		if len(args) < 2 || !store.ValidID(args[1]) {
			fail("args", fmt.Errorf("valid profile id required"))
		}
		openOverride(st.ProfilePath(args[1], "override.yaml"))
	default:
		fail("args", fmt.Errorf("unknown override command: %s", args[0]))
	}
}

func readOverride(path string) ([]byte, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return []byte("{}\n"), nil
	}
	return b, err
}

func overrideIsEmpty(data []byte) bool {
	parsed, err := config.Parse(data)
	return err == nil && len(parsed) == 0
}

func readOverrideInput(args []string, index int) ([]byte, error) {
	if len(args) > 0 && args[0] == "set-file" {
		if len(args) != 2 {
			return nil, fmt.Errorf("set-file requires one path")
		}
		return os.ReadFile(args[1])
	}
	if len(args) <= index {
		return nil, fmt.Errorf("override content source required (--stdin, --file, or --text)")
	}
	if args[index] == "--stdin" {
		if len(args) != index+1 {
			return nil, fmt.Errorf("--stdin does not accept extra arguments")
		}
		return io.ReadAll(os.Stdin)
	}
	if args[index] == "--file" {
		if len(args) != index+2 {
			return nil, fmt.Errorf("--file requires one path")
		}
		return os.ReadFile(args[index+1])
	}
	if args[index] == "--text" {
		if len(args) != index+2 {
			return nil, fmt.Errorf("--text requires one value")
		}
		return []byte(args[index+1]), nil
	}
	return nil, fmt.Errorf("override content source must be --stdin, --file, or --text")
}

func normalizedOverride(data []byte) ([]byte, error) {
	parsed, err := config.Parse(data)
	if err != nil {
		return nil, fmt.Errorf("parse override: %w", err)
	}
	if len(parsed) == 0 {
		return []byte("{}\n"), nil
	}
	data = []byte(strings.TrimRight(string(data), "\n") + "\n")
	return data, nil
}

func setOverride(scope, id string, data []byte) error {
	normalized, err := normalizedOverride(data)
	if err != nil {
		return err
	}
	return runLocked(func() error {
		path := st.GlobalOverridePath()
		if scope == "profile" {
			if !store.ValidID(id) {
				return fmt.Errorf("valid profile id required")
			}
			path = st.ProfilePath(id, "override.yaml")
		}
		oldOverride, hadOverride, err := snapshot(path)
		if err != nil {
			return err
		}
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		activeID := idx.ActiveProfile
		if scope == "profile" && activeID != id {
			return st.WriteAtomic(path, normalized)
		}
		if activeID == "" {
			return st.WriteAtomic(path, normalized)
		}
		meta, err := profile.LoadMeta(st, activeID)
		if err != nil {
			return err
		}
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		oldBinding, hadBinding, err := snapshot(st.BindingsPath(activeID))
		if err != nil {
			return err
		}
		options := compileOptions{}
		if scope == "global" {
			options.globalOverride = normalized
		} else {
			options.profileOverride = normalized
		}
		if err = applyLockedWithOptions(activeID, meta, nil, options); err != nil {
			return err
		}
		if err = st.WriteAtomic(path, normalized); err != nil {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			bindingErr := restoreSnapshot(st.BindingsPath(activeID), oldBinding, hadBinding)
			overrideErr := restoreSnapshot(path, oldOverride, hadOverride)
			return rollbackErrors(err, runtimeErr, stateErr, bindingErr, overrideErr)
		}
		return nil
	})
}

func ruleCommand(args []string) {
	if len(args) == 0 {
		fail("args", fmt.Errorf("rule command required"))
	}
	switch args[0] {
	case "list":
		collection, err := rules.Load(st)
		if err != nil {
			fail("store", err)
		}
		ok(collection.Rules)
	case "add":
		item, err := parseRuleFlags("add", args[1:], rules.Rule{})
		if err != nil {
			fail("args", err)
		}
		collection, err := mutateRules(func(candidate *rules.Collection) error {
			for _, existing := range candidate.Rules {
				if rules.Key(existing) == rules.Key(item) {
					return fmt.Errorf("duplicate rule for %s", item.Match.Value)
				}
			}
			candidate.Rules = append(candidate.Rules, item)
			return nil
		})
		if err != nil {
			failOperation("apply", err)
		}
		_, added, _ := rules.Find(collection, item.ID)
		ok(map[string]any{"rule": added})
	case "update":
		if len(args) < 2 || !store.ValidID(args[1]) {
			fail("args", fmt.Errorf("valid rule id required"))
		}
		var updated rules.Rule
		collection, err := mutateRules(func(candidate *rules.Collection) error {
			index, current, found := rules.Find(*candidate, args[1])
			if !found {
				return fmt.Errorf("rule not found")
			}
			item, parseErr := parseRuleFlags("update", args[2:], current)
			if parseErr != nil {
				return parseErr
			}
			item.ID = current.ID
			item.CreatedAt = current.CreatedAt
			candidate.Rules[index] = item
			updated = item
			return nil
		})
		if err != nil {
			failOperation("apply", err)
		}
		if updated.ID == "" {
			_, updated, _ = rules.Find(collection, args[1])
		}
		ok(map[string]any{"rule": updated})
	case "delete", "enable", "disable":
		if len(args) != 2 || !store.ValidID(args[1]) {
			fail("args", fmt.Errorf("valid rule id required"))
		}
		collection, err := mutateRules(func(candidate *rules.Collection) error {
			index, _, found := rules.Find(*candidate, args[1])
			if !found {
				return fmt.Errorf("rule not found")
			}
			if args[0] == "delete" {
				candidate.Rules = append(candidate.Rules[:index], candidate.Rules[index+1:]...)
			} else {
				candidate.Rules[index].Enabled = args[0] == "enable"
			}
			return nil
		})
		if err != nil {
			failOperation("apply", err)
		}
		ok(collection)
	default:
		fail("args", fmt.Errorf("unknown rule command: %s", args[0]))
	}
}

func parseRuleFlags(name string, args []string, current rules.Rule) (rules.Rule, error) {
	fs := flag.NewFlagSet("rule "+name, flag.ContinueOnError)
	domain := fs.String("domain", current.Match.Value, "domain")
	matchType := fs.String("match", current.Match.Type, "match type")
	policyName := fs.String("policy", current.Policy, "policy")
	if err := fs.Parse(args); err != nil {
		return rules.Rule{}, err
	}
	if fs.NArg() != 0 {
		return rules.Rule{}, fmt.Errorf("unexpected rule argument: %s", fs.Arg(0))
	}
	if name == "add" && strings.TrimSpace(*domain) == "" {
		return rules.Rule{}, fmt.Errorf("--domain is required")
	}
	item, err := rules.New(*domain, *matchType, *policyName)
	if err != nil {
		return rules.Rule{}, err
	}
	item.Enabled = current.ID == "" || current.Enabled
	if current.ID != "" {
		item.ID = current.ID
	}
	return item, nil
}

func failOperation(stage string, err error) {
	// Preserve structured binding errors through the same CLI error contract used
	// by profile/apply transactions.
	fail(stage, err)
}

func mutateRules(mutator func(*rules.Collection) error) (rules.Collection, error) {
	var result rules.Collection
	err := runLocked(func() error {
		oldRules, hadRules, err := snapshot(st.CustomRulesPath())
		if err != nil {
			return err
		}
		collection, err := rules.Load(st)
		if err != nil {
			return err
		}
		candidate := rules.Clone(collection)
		if err := mutator(&candidate); err != nil {
			return err
		}
		candidate, err = rules.NormalizeCollection(candidate)
		if err != nil {
			return err
		}
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		if idx.ActiveProfile == "" {
			if err := rules.Save(st, candidate); err != nil {
				return err
			}
			result = candidate
			return nil
		}
		meta, err := profile.LoadMeta(st, idx.ActiveProfile)
		if err != nil {
			return err
		}
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		oldBinding, hadBinding, err := snapshot(st.BindingsPath(idx.ActiveProfile))
		if err != nil {
			return err
		}
		if err := applyLockedWithOptions(idx.ActiveProfile, meta, nil, compileOptions{
			customRules: candidate.Rules, customRulesSet: true,
		}); err != nil {
			return err
		}
		if err := rules.Save(st, candidate); err != nil {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			bindingErr := restoreSnapshot(st.BindingsPath(idx.ActiveProfile), oldBinding, hadBinding)
			rulesErr := restoreSnapshot(st.CustomRulesPath(), oldRules, hadRules)
			return rollbackErrors(err, runtimeErr, stateErr, bindingErr, rulesErr)
		}
		result = candidate
		return nil
	})
	return result, err
}

func policyCommand(args []string) {
	if len(args) < 2 || args[0] != "binding" {
		fail("args", fmt.Errorf("policy binding command required"))
	}
	if len(args) < 3 || !store.ValidID(args[2]) {
		fail("args", fmt.Errorf("valid profile id required"))
	}
	id := args[2]
	switch args[1] {
	case "get":
		bindings, err := policy.Load(st, id)
		if err != nil {
			fail("store", err)
		}
		ok(map[string]any{"profileId": id, "bindings": bindings})
	case "candidates":
		configMap, err := effectiveConfig(id)
		if err != nil {
			fail("compile", err)
		}
		ok(map[string]any{"profileId": id, "candidates": policy.Candidates(configMap)})
	case "set":
		if len(args) != 5 || args[3] != policy.Proxy || strings.TrimSpace(args[4]) == "" {
			fail("args", fmt.Errorf("policy binding set <profile-id> proxy <group> required"))
		}
		if err := setPolicyBinding(id, args[3], args[4]); err != nil {
			fail("apply", err)
		}
		ok(map[string]any{"profileId": id, "policy": args[3], "target": args[4]})
	default:
		fail("args", fmt.Errorf("unknown policy binding command: %s", args[1]))
	}
}

func effectiveConfig(id string) (map[string]any, error) {
	source, err := profile.ReadSource(st, id)
	if err != nil {
		return nil, err
	}
	override, err := profile.ReadOverride(st, id)
	if err != nil {
		return nil, err
	}
	global, err := readGlobalOverride()
	if err != nil {
		return nil, err
	}
	return config.MergeLayers(source, global, override)
}

func setPolicyBinding(id, policyName, target string) error {
	if policyName != policy.Proxy {
		return fmt.Errorf("only the proxy policy can be bound")
	}
	configMap, err := effectiveConfig(id)
	if err != nil {
		return err
	}
	if err := policy.ValidateTarget(configMap, target); err != nil {
		return err
	}
	return runLocked(func() error {
		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		oldBinding, hadBinding, err := snapshot(st.BindingsPath(id))
		if err != nil {
			return err
		}
		bindings, err := policy.Load(st, id)
		if err != nil {
			return err
		}
		bindings[policyName] = strings.TrimSpace(target)
		if idx.ActiveProfile != id {
			return policy.Save(st, id, bindings)
		}
		meta, err := profile.LoadMeta(st, id)
		if err != nil {
			return err
		}
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		if err := applyLockedWithOptions(id, meta, nil, compileOptions{bindings: bindings, bindingsSet: true}); err != nil {
			return err
		}
		if err := policy.Save(st, id, bindings); err != nil {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			bindingErr := restoreSnapshot(st.BindingsPath(id), oldBinding, hadBinding)
			return rollbackErrors(err, runtimeErr, stateErr, bindingErr)
		}
		return nil
	})
}
func openOverride(path string) {
	if _, err := os.Stat(path); err != nil {
		if os.IsNotExist(err) {
			if err = st.WriteAtomic(path, []byte("{}\n")); err != nil {
				fail("store", err)
			}
		} else {
			fail("store", err)
		}
	}
	launcher := ""
	for _, candidate := range []string{"omarchy-launch-config-editor", "omarchy-launch-editor", "xdg-open"} {
		if _, err := exec.LookPath(candidate); err == nil {
			launcher = candidate
			break
		}
	}
	if launcher == "" {
		fail("editor", fmt.Errorf("no editor launcher found"))
	}
	if err := exec.Command("setsid", launcher, path).Start(); err != nil {
		fail("editor", err)
	}
	ok(map[string]string{"path": path})
}
func settingsCommand(args []string) {
	if len(args) == 0 || args[0] == "get" {
		settings, err := profile.LoadSettings(st)
		if err != nil {
			fail("settings", err)
		}
		ok(settings)
		return
	}
	updates := []settingUpdate{}
	switch args[0] {
	case "set":
		if len(args) < 3 {
			fail("args", fmt.Errorf("settings set key value required"))
		}
		updates = append(updates, settingUpdate{key: args[1], value: strings.Join(args[2:], " ")})
	case "patch":
		if len(args) < 3 || (len(args)-1)%2 != 0 {
			fail("args", fmt.Errorf("settings patch requires key value pairs"))
		}
		for i := 1; i < len(args); i += 2 {
			updates = append(updates, settingUpdate{key: args[i], value: args[i+1]})
		}
	default:
		fail("args", fmt.Errorf("settings set or patch required"))
	}
	var next profile.Settings
	err := runLocked(func() error {
		old, err := profile.LoadSettings(st)
		if err != nil {
			return err
		}
		next = old
		for _, update := range updates {
			if err = setSetting(&next, update.key, update.value); err != nil {
				return err
			}
		}
		if err = validateSettings(next); err != nil {
			return err
		}
		next.TUN.Stack = profile.NormalizeTUNStack(next.TUN.Stack)

		idx, err := profile.LoadIndex(st)
		if err != nil {
			return err
		}
		if idx.ActiveProfile == "" {
			return profile.SaveSettings(st, next)
		}
		meta, err := profile.LoadMeta(st, idx.ActiveProfile)
		if err != nil {
			return err
		}
		oldState, hadState, err := snapshot(st.StatePath())
		if err != nil {
			return err
		}
		oldRuntime, err := snapshotRuntime()
		if err != nil {
			return err
		}
		oldBinding, hadBinding, err := snapshot(st.BindingsPath(idx.ActiveProfile))
		if err != nil {
			return err
		}
		if err = applyLockedWithOptions(idx.ActiveProfile, meta, nil, compileOptions{settings: &next}); err != nil {
			return err
		}
		if err = profile.SaveSettings(st, next); err != nil {
			runtimeErr := restoreRuntimeWithFallback(oldRuntime, restoreMode{applyPreviousIfCurrentMissing: true})
			stateErr := restoreSnapshot(st.StatePath(), oldState, hadState)
			bindingErr := restoreSnapshot(st.BindingsPath(idx.ActiveProfile), oldBinding, hadBinding)
			settingsErr := profile.SaveSettings(st, old)
			return rollbackErrors(err, runtimeErr, stateErr, bindingErr, settingsErr)
		}
		return nil
	})
	if err != nil {
		fail("apply", err)
	}
	ok(next)
}

type settingUpdate struct {
	key   string
	value string
}

func parseBoolSetting(value string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "true", "on", "yes", "enabled":
		return true, nil
	case "0", "false", "off", "no", "disabled":
		return false, nil
	default:
		return false, fmt.Errorf("boolean setting must be true or false")
	}
}

func parseListSetting(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if item := strings.TrimSpace(part); item != "" {
			out = append(out, item)
		}
	}
	return out
}

func setSetting(settings *profile.Settings, key, value string) error {
	if settings == nil {
		return fmt.Errorf("settings are unavailable")
	}
	switch key {
	case "dns-management":
		settings.DNSManagement = strings.ToLower(strings.TrimSpace(value))
	case "tun-management":
		settings.TUNManagement = strings.ToLower(strings.TrimSpace(value))
	case "mixed-port":
		v, err := strconv.Atoi(strings.TrimSpace(value))
		if err != nil {
			return fmt.Errorf("mixed-port must be an integer")
		}
		settings.Network.MixedPort = v
	case "dns-enable":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("dns-enable: %w", err)
		}
		settings.DNS.Enable = v
	case "dns-ipv6":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("dns-ipv6: %w", err)
		}
		settings.DNS.IPv6 = v
	case "dns-enhanced-mode":
		settings.DNS.EnhancedMode = strings.ToLower(strings.TrimSpace(value))
	case "dns-fake-ip-range":
		settings.DNS.FakeIPRange = strings.TrimSpace(value)
	case "dns-default-nameserver":
		settings.DNS.DefaultNameserver = parseListSetting(value)
	case "dns-nameserver":
		settings.DNS.Nameserver = parseListSetting(value)
	case "dns-proxy-server-nameserver":
		settings.DNS.ProxyServerNameserver = parseListSetting(value)
	case "dns-fake-ip-filter":
		settings.DNS.FakeIPFilter = parseListSetting(value)
	case "tun-enable":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("tun-enable: %w", err)
		}
		settings.TUN.Enable = v
	case "tun-stack":
		settings.TUN.Stack = profile.NormalizeTUNStack(value)
	case "tun-auto-route":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("tun-auto-route: %w", err)
		}
		settings.TUN.AutoRoute = v
	case "tun-auto-detect-interface":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("tun-auto-detect-interface: %w", err)
		}
		settings.TUN.AutoDetectInterface = v
	case "tun-strict-route":
		v, err := parseBoolSetting(value)
		if err != nil {
			return fmt.Errorf("tun-strict-route: %w", err)
		}
		settings.TUN.StrictRoute = v
	case "tun-dns-hijack":
		settings.TUN.DNSHijack = parseListSetting(value)
	default:
		return fmt.Errorf("unsupported setting: %s", key)
	}
	return nil
}

func validateSettings(settings profile.Settings) error {
	if settings.Network.MixedPort < 1 || settings.Network.MixedPort > 65535 {
		return fmt.Errorf("mixed-port must be between 1 and 65535")
	}
	if settings.DNSManagement != "managed" && settings.DNSManagement != "inherit" {
		return fmt.Errorf("dns-management must be managed or inherit")
	}
	if settings.TUNManagement != "managed" && settings.TUNManagement != "inherit" {
		return fmt.Errorf("tun-management must be managed or inherit")
	}
	if settings.DNS.EnhancedMode != "fake-ip" && settings.DNS.EnhancedMode != "redir-host" {
		return fmt.Errorf("dns-enhanced-mode must be fake-ip or redir-host")
	}
	stack := profile.NormalizeTUNStack(settings.TUN.Stack)
	if stack != "system" && stack != "gvisor" && stack != "mixed" {
		return fmt.Errorf("tun-stack must be system, gvisor, or mixed")
	}
	if strings.TrimSpace(settings.DNS.FakeIPRange) == "" {
		return fmt.Errorf("dns-fake-ip-range must not be empty")
	}
	return nil
}

func currentActive() string { idx, _ := profile.LoadIndex(st); return idx.ActiveProfile }
func redact(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		if i := strings.IndexByte(raw, '?'); i >= 0 {
			return raw[:i] + "?••••••••"
		}
		return raw
	}
	if u.RawQuery != "" {
		u.RawQuery = "••••••••"
	}
	if u.User != nil {
		u.User = url.UserPassword(u.User.Username(), "••••••••")
	}
	return u.String()
}
