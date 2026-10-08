package fetcher

import (
	"context"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"testing"
)

func TestETag304(t *testing.T) {
	old := allowPrivateHosts
	allowPrivateHosts = true
	defer func() { allowPrivateHosts = old }()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("subscription-userinfo", "upload=10; download=20; total=100; expire=1700000000")
		if r.Header.Get("If-None-Match") == "v1" {
			w.WriteHeader(http.StatusNotModified)
			return
		}
		w.Header().Set("ETag", "v1")
		_, _ = w.Write([]byte("mode: rule\n"))
	}))
	defer srv.Close()
	a, e := Fetch(srv.URL, "", "", "", false, 0)
	if e != nil || a.NotModified || a.ETag != "v1" || !a.HasSubscriptionInfo || a.SubscriptionInfo.Download != 20 || a.SubscriptionInfo.Total != 100 {
		t.Fatalf("first fetch: %#v %v", a, e)
	}
	b, e := Fetch(srv.URL, "", "v1", "", false, 0)
	if e != nil || !b.NotModified {
		t.Fatalf("304: %#v %v", b, e)
	}
}

func TestFetchRejectsMalformedOrHostlessURL(t *testing.T) {
	for _, rawURL := range []string{"http://", "https:///path", "http://?token=secret"} {
		if _, err := Fetch(rawURL, "", "", "", false, 0); err == nil {
			t.Fatalf("expected URL validation error for %q", rawURL)
		} else if containsSecret(err.Error()) {
			t.Fatalf("URL credential leaked for %q: %v", rawURL, err)
		}
	}
}

func TestFetchRejectsPrivateHosts(t *testing.T) {
	for _, rawURL := range []string{"http://127.0.0.1/", "http://localhost/", "http://[::1]/", "http://192.168.1.1/"} {
		for _, viaProxy := range []bool{false, true} {
			if _, err := Fetch(rawURL, "", "", "", viaProxy, 7890); err == nil {
				t.Fatalf("expected private host to be rejected for %q (viaProxy=%v)", rawURL, viaProxy)
			}
		}
	}
}

func TestFetchRejectsUserinfo(t *testing.T) {
	if _, err := Fetch("http://user:password@example.com/", "", "", "", false, 0); err == nil {
		t.Fatal("expected userinfo URL to be rejected")
	}
}

func TestRedirectLimit(t *testing.T) {
	old := allowPrivateHosts
	allowPrivateHosts = true
	defer func() { allowPrivateHosts = old }()
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := r.URL.Query().Get("n")
		if n == "" {
			n = "0"
		}
		w.Header().Set("Location", srv.URL+"/?n="+n+"x")
		w.WriteHeader(http.StatusFound)
	}))
	defer srv.Close()
	if _, err := Fetch(srv.URL, "", "", "", false, 0); err == nil {
		t.Fatal("expected redirect limit error")
	}
}

func TestRedirectRejectsUnsupportedScheme(t *testing.T) {
	old := allowPrivateHosts
	allowPrivateHosts = true
	defer func() { allowPrivateHosts = old }()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Location", "file:///secret/token")
		w.WriteHeader(http.StatusFound)
	}))
	defer srv.Close()
	if _, err := Fetch(srv.URL, "", "", "", false, 0); err == nil || containsSecret(err.Error()) {
		t.Fatalf("unexpected redirect error: %v", err)
	}
}

func TestFetchRejectsPrivateResolvedHost(t *testing.T) {
	oldAllow := allowPrivateHosts
	oldLookup := lookupIP
	allowPrivateHosts = false
	lookupIP = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("10.0.0.1")}}, nil
	}
	defer func() {
		allowPrivateHosts = oldAllow
		lookupIP = oldLookup
	}()

	if _, err := Fetch("https://subscription.example.test/config.yaml", "", "", "", false, 0); err == nil {
		t.Fatal("expected a hostname resolving to a private address to be rejected")
	}
}

func TestSafeDialRejectsPrivateResolvedHost(t *testing.T) {
	oldAllow := allowPrivateHosts
	oldLookup := lookupIP
	allowPrivateHosts = false
	lookupIP = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("127.0.0.1")}}, nil
	}
	defer func() {
		allowPrivateHosts = oldAllow
		lookupIP = oldLookup
	}()

	dial := safeDialContext("")
	if _, err := dial(context.Background(), "tcp", "subscription.example.test:443"); err == nil {
		t.Fatal("expected the custom dialer to reject a private DNS result")
	}
}

func TestBlockedSpecialPurposeAddresses(t *testing.T) {
	blocked := []string{
		"0.0.0.0", "0.0.0.1", "10.1.2.3", "100.64.0.1", "127.0.0.1", "169.254.169.254",
		"172.16.0.1", "192.0.2.1", "192.168.1.1", "198.18.0.1", "198.51.100.1", "203.0.113.1",
		"224.0.0.1", "255.255.255.255", "::", "::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1",
		"::7f00:1", "2002:7f00:1::", "64:ff9b::7f00:1", "64:ff9b:1::", "2001:db8::1", "fd00::1",
	}
	for _, host := range blocked {
		if ip := net.ParseIP(host); ip == nil || !isBlockedIP(ip) {
			t.Fatalf("expected %s to be blocked", host)
		}
	}
	allowed := []string{"1.1.1.1", "8.8.8.8", "9.9.9.9", "2606:4700:4700::1111", "2002:0101:0101::"}
	for _, host := range allowed {
		if ip := net.ParseIP(host); ip == nil || isBlockedIP(ip) {
			t.Fatalf("expected %s to stay reachable", host)
		}
	}
	for _, rawURL := range []string{
		"http://0.0.0.1/latest?token=secret",
		"http://100.64.0.1/",
		"http://169.254.169.254/latest?token=secret",
		"http://198.18.0.1/",
		"http://[::ffff:127.0.0.1]/",
		"http://[::7f00:1]/",
		"http://[2002:7f00:1::]/",
		"http://[64:ff9b::7f00:1]/",
		"http://metadata.google.internal/latest?token=secret",
	} {
		if _, err := Fetch(rawURL, "", "", "", false, 0); err == nil {
			t.Fatalf("expected %s to be rejected", rawURL)
		} else if containsSecret(err.Error()) {
			t.Fatalf("token leaked for %s: %v", rawURL, err)
		}
	}
}

func TestRedirectToPrivateAddressIsRejected(t *testing.T) {
	old := allowPrivateHosts
	allowPrivateHosts = true
	defer func() { allowPrivateHosts = old }()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://10.1.2.3/latest?token=secret", http.StatusFound)
	}))
	defer srv.Close()
	if _, err := Fetch(srv.URL, "", "", "", false, 0); err == nil {
		t.Fatal("expected redirect to a private address to be rejected")
	} else if containsSecret(err.Error()) {
		t.Fatalf("token leaked: %v", err)
	}
}

func TestDialRechecksDNSRebinding(t *testing.T) {
	oldAllow := allowPrivateHosts
	oldLookup := lookupIP
	allowPrivateHosts = false
	var lookups int
	lookupIP = func(context.Context, string) ([]net.IPAddr, error) {
		lookups++
		if lookups == 1 {
			return []net.IPAddr{{IP: net.ParseIP("1.1.1.1")}}, nil
		}
		return []net.IPAddr{{IP: net.ParseIP("10.0.0.1")}}, nil
	}
	defer func() {
		allowPrivateHosts = oldAllow
		lookupIP = oldLookup
	}()
	_, err := Fetch("https://subscription.example.test/sub?token=secret", "", "", "", false, 0)
	if err == nil {
		t.Fatal("expected dial-time rebinding to be rejected")
	}
	if containsSecret(err.Error()) {
		t.Fatalf("token leaked: %v", err)
	}
}

func TestViaProxyConnectsToPinnedAddress(t *testing.T) {
	oldAllow := allowPrivateHosts
	oldLookup := lookupIP
	allowPrivateHosts = false
	lookupIP = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("1.1.1.1")}}, nil
	}
	defer func() {
		allowPrivateHosts = oldAllow
		lookupIP = oldLookup
	}()

	var seen string
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodConnect {
			seen = r.Host
		} else if r.URL != nil {
			seen = r.URL.Host
		}
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer proxy.Close()
	proxyURL, err := url.Parse(proxy.URL)
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(proxyURL.Port())
	if err != nil {
		t.Fatal(err)
	}
	_, err = Fetch("https://subscription.example.test/sub?token=secret", "", "", "", true, port)
	if err == nil {
		t.Fatal("expected the pinned proxy request to fail closed")
	}
	if containsSecret(err.Error()) {
		t.Fatalf("token leaked: %v", err)
	}
	if !strings.Contains(seen, "1.1.1.1") || strings.Contains(seen, "subscription.example.test") {
		t.Fatalf("proxy target = %q, want the checked address", seen)
	}
}
