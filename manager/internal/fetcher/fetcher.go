package fetcher

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

const MaxResponse = 16 << 20

// Tests may opt into loopback httptest servers. The switch does not allow
// LAN, link-local, or other non-public destinations; production leaves it unset.
var allowPrivateHosts = os.Getenv("OMARCHY_MIHOMO_ALLOW_PRIVATE_HOSTS") == "1"

// Keep DNS lookup injectable so the SSRF checks can be tested without relying
// on the host resolver or a real private DNS record.
var lookupIP = func(ctx context.Context, host string) ([]net.IPAddr, error) {
	return net.DefaultResolver.LookupIPAddr(ctx, host)
}

func validateHTTPURL(rawURL string, redirect bool) (*url.URL, error) {
	u, err := url.Parse(rawURL)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil || strings.TrimSpace(u.Hostname()) == "" {
		if redirect {
			return nil, fmt.Errorf("subscription redirect must be HTTP or HTTPS")
		}
		return nil, fmt.Errorf("subscription URL must be HTTP or HTTPS")
	}
	return u, nil
}

func validateRedirectURL(u *url.URL) error {
	return validateRedirectURLContext(context.Background(), u)
}

func validateRedirectURLContext(ctx context.Context, u *url.URL) error {
	if u == nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || u.User != nil || strings.TrimSpace(u.Hostname()) == "" {
		return fmt.Errorf("subscription redirect must be HTTP or HTTPS")
	}
	if err := validateResolvedHost(ctx, u.Hostname()); err != nil {
		return err
	}
	return nil
}

func isLoopbackHost(host string) bool {
	name := strings.ToLower(strings.TrimSpace(strings.TrimSuffix(host, ".")))
	if name == "localhost" {
		return true
	}
	ip := net.ParseIP(name)
	return ip != nil && ip.IsLoopback()
}

func isBlockedIP(ip net.IP) bool {
	if len(ip) == 0 {
		return true
	}
	if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified() || ip.IsMulticast() {
		return true
	}
	if ip4 := ip.To4(); ip4 != nil {
		return isBlockedIPv4(ip4)
	}
	ip = ip.To16()
	if ip == nil {
		return true
	}
	// Deprecated IPv4-compatible form, ::a.b.c.d. Mapped addresses are handled
	// by To4 above.
	if allZero(ip[:12]) {
		return isBlockedIPv4(net.IP(ip[12:16]))
	}
	// Site-local fec0::/10.
	if ip[0] == 0xfe && ip[1]&0xc0 == 0xc0 {
		return true
	}
	// Documentation 2001:db8::/32 and Teredo 2001:0::/32.
	if ip[0] == 0x20 && ip[1] == 0x01 && ip[2] == 0x0d && ip[3] == 0xb8 {
		return true
	}
	if ip[0] == 0x20 && ip[1] == 0x01 && ip[2] == 0x00 && ip[3] == 0x00 {
		return true
	}
	// 6to4 embeds an IPv4 address. Block it when that address is not public.
	if ip[0] == 0x20 && ip[1] == 0x02 {
		return isBlockedIPv4(net.IPv4(ip[2], ip[3], ip[4], ip[5]))
	}
	// Well-known NAT64 prefix 64:ff9b::/96.
	if ip[0] == 0x00 && ip[1] == 0x64 && ip[2] == 0xff && ip[3] == 0x9b && allZero(ip[4:12]) {
		return isBlockedIPv4(net.IPv4(ip[12], ip[13], ip[14], ip[15]))
	}
	// Local-use NAT64 prefix 64:ff9b:1::/48 is not a public subscription target.
	if ip[0] == 0x00 && ip[1] == 0x64 && ip[2] == 0xff && ip[3] == 0x9b && ip[4] == 0x00 && ip[5] == 0x01 {
		return true
	}
	return false
}

func isBlockedIPv4(ip net.IP) bool {
	ip = ip.To4()
	if ip == nil {
		return true
	}
	// 0.0.0.0/8, loopback, 224.0.0.0/4 (multicast) and 240.0.0.0/4 (reserved).
	// Loopback is repeated here so embedded forms (6to4, NAT64, IPv4-compatible)
	// cannot skip the check in isBlockedIP.
	if ip[0] == 0 || ip[0] == 127 || ip[0] >= 224 {
		return true
	}
	if ip[0] == 10 || (ip[0] == 172 && ip[1]&0xf0 == 16) || (ip[0] == 192 && ip[1] == 168) {
		return true
	}
	// CGNAT, link-local, IETF protocol assignments, documentation, and the
	// benchmarking range Mihomo uses for fake-ip.
	if ip[0] == 100 && ip[1]&0xc0 == 64 {
		return true
	}
	if ip[0] == 169 && ip[1] == 254 {
		return true
	}
	if ip[0] == 192 && ip[1] == 0 && (ip[2] == 0 || ip[2] == 2) {
		return true
	}
	if ip[0] == 198 && ip[1] == 51 && ip[2] == 100 {
		return true
	}
	if ip[0] == 203 && ip[1] == 0 && ip[2] == 113 {
		return true
	}
	if ip[0] == 198 && (ip[1] == 18 || ip[1] == 19) {
		return true
	}
	return false
}

func allZero(b []byte) bool {
	for _, value := range b {
		if value != 0 {
			return false
		}
	}
	return true
}

func rejectPrivateHost(host string) error {
	name := strings.ToLower(strings.TrimSpace(strings.TrimSuffix(host, ".")))
	switch {
	case name == "localhost" || strings.HasSuffix(name, ".localhost") || strings.HasSuffix(name, ".local"):
		return fmt.Errorf("subscription URL host is not allowed")
	case name == "metadata.google.internal":
		return fmt.Errorf("subscription URL host is not allowed")
	}
	if ip := net.ParseIP(name); ip != nil && isBlockedIP(ip) {
		return fmt.Errorf("subscription URL host is not allowed")
	}
	return nil
}

func resolvePublicIPs(ctx context.Context, host string) ([]net.IP, error) {
	if err := rejectPrivateHost(host); err != nil {
		return nil, err
	}
	if ip := net.ParseIP(host); ip != nil {
		return []net.IP{ip}, nil
	}
	addrs, err := lookupIP(ctx, host)
	if err != nil {
		return nil, fmt.Errorf("subscription URL host could not be resolved: %w", err)
	}
	if len(addrs) == 0 {
		return nil, fmt.Errorf("subscription URL host has no address")
	}
	ips := make([]net.IP, 0, len(addrs))
	for _, addr := range addrs {
		if isBlockedIP(addr.IP) {
			return nil, fmt.Errorf("subscription URL host resolves to a private address")
		}
		ips = append(ips, addr.IP)
	}
	return ips, nil
}

func validateResolvedHost(ctx context.Context, host string) error {
	if allowPrivateHosts && isLoopbackHost(host) {
		return nil
	}
	_, err := resolvePublicIPs(ctx, host)
	return err
}

func safeDialContext(proxyAddress string) func(context.Context, string, string) (net.Conn, error) {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	return func(ctx context.Context, network, address string) (net.Conn, error) {
		// The local Mihomo HTTP proxy is an explicit application dependency, so
		// allow connecting to that exact endpoint while still validating the
		// subscription destination before the request is proxied.
		if proxyAddress != "" && address == proxyAddress {
			return dialer.DialContext(ctx, network, address)
		}
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return nil, fmt.Errorf("invalid subscription dial address")
		}
		if allowPrivateHosts && isLoopbackHost(host) {
			return dialer.DialContext(ctx, network, address)
		}
		ips, err := resolvePublicIPs(ctx, host)
		if err != nil {
			return nil, err
		}
		var lastErr error
		for _, ip := range ips {
			conn, dialErr := dialer.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
			if dialErr == nil {
				return conn, nil
			}
			lastErr = dialErr
		}
		if lastErr == nil {
			lastErr = fmt.Errorf("no usable address")
		}
		return nil, fmt.Errorf("subscription host connection failed: %w", lastErr)
	}
}

type Result struct {
	Body                []byte
	ETag                string
	LastModified        string
	NotModified         bool
	SubscriptionInfo    SubscriptionInfo
	HasSubscriptionInfo bool
}

type SubscriptionInfo struct {
	Upload   int64
	Download int64
	Total    int64
	Expire   int64
}

func parseSubscriptionInfo(raw string) (SubscriptionInfo, bool) {
	var out SubscriptionInfo
	found := false
	for _, item := range strings.Split(raw, ";") {
		parts := strings.SplitN(item, "=", 2)
		if len(parts) != 2 {
			continue
		}
		value, err := strconv.ParseInt(strings.TrimSpace(parts[1]), 10, 64)
		if err != nil || value < 0 {
			continue
		}
		switch strings.ToLower(strings.TrimSpace(parts[0])) {
		case "upload":
			out.Upload, found = value, true
		case "download":
			out.Download, found = value, true
		case "total":
			out.Total, found = value, true
		case "expire":
			out.Expire, found = value, true
		}
	}
	return out, found
}

func Fetch(rawURL, ua, etag, lastModified string, viaProxy bool, proxyPort int) (Result, error) {
	u, err := validateHTTPURL(rawURL, false)
	if err != nil {
		return Result{}, err
	}
	hostContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err = validateResolvedHost(hostContext, u.Hostname()); err != nil {
		return Result{}, err
	}
	tr := &http.Transport{}
	proxyAddress := ""
	if viaProxy {
		if proxyPort <= 0 {
			return Result{}, fmt.Errorf("mihomo mixed-port is unavailable for proxy update")
		}
		p, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", proxyPort))
		tr.Proxy = http.ProxyURL(p)
		proxyAddress = p.Host
	}
	tr.DialContext = safeDialContext(proxyAddress)
	client := &http.Client{Timeout: 30 * time.Second, Transport: tr, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 5 {
			return fmt.Errorf("too many redirects")
		}
		if err := validateRedirectURLContext(req.Context(), req.URL); err != nil {
			return err
		}
		return nil
	}}
	req, err := http.NewRequest(http.MethodGet, rawURL, nil)
	if err != nil {
		return Result{}, fmt.Errorf("invalid subscription request")
	}
	if ua != "" {
		req.Header.Set("User-Agent", ua)
	}
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	if lastModified != "" {
		req.Header.Set("If-Modified-Since", lastModified)
	}
	resp, err := client.Do(req)
	if err != nil {
		return Result{}, fmt.Errorf("subscription request failed: %w", redactError(err))
	}
	defer resp.Body.Close()
	usage, hasUsage := parseSubscriptionInfo(resp.Header.Get("subscription-userinfo"))
	if resp.StatusCode == http.StatusNotModified {
		return Result{NotModified: true, ETag: resp.Header.Get("ETag"), LastModified: resp.Header.Get("Last-Modified"), SubscriptionInfo: usage, HasSubscriptionInfo: hasUsage}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return Result{}, fmt.Errorf("subscription returned HTTP %d", resp.StatusCode)
	}
	r := io.LimitReader(resp.Body, MaxResponse+1)
	body, err := io.ReadAll(r)
	if err != nil {
		return Result{}, err
	}
	if len(body) > MaxResponse {
		return Result{}, fmt.Errorf("subscription exceeds 16 MiB")
	}
	return Result{Body: body, ETag: resp.Header.Get("ETag"), LastModified: resp.Header.Get("Last-Modified"), SubscriptionInfo: usage, HasSubscriptionInfo: hasUsage}, nil
}

func redactError(err error) error {
	if err == nil {
		return nil
	}
	// url.Error may include the full request URL, which can contain a token.
	// Keep the network cause while never returning subscription credentials.
	if e, ok := err.(*url.Error); ok {
		return fmt.Errorf("%s", e.Err)
	}
	return err
}
