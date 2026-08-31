package main

import (
	"context"
	"crypto/tls"
	"io"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

type DNSLookup struct {
	Resolver string   `json:"resolver"`
	Name     string   `json:"name"`
	Addrs    []string `json:"addrs,omitempty"`
	Error    string   `json:"error,omitempty"`
	Millis   float64  `json:"millis"`
}

type HTTPPath struct {
	URL    string  `json:"url"`
	Status int     `json:"status,omitempty"`
	Remote string  `json:"remote,omitempty"`
	Via    string  `json:"via,omitempty"`
	Millis float64 `json:"millis"`
	Error  string  `json:"error,omitempty"`
}

type DNSReport struct {
	Hostname string      `json:"hostname"`
	Lookups  []DNSLookup `json:"lookups"`
	HTTPS    HTTPPath    `json:"https"`
	Hairpin  bool        `json:"lan_client_hairpins_through_public_edge"`
	Notes    []string    `json:"notes"`
}

func lookupVia(ctx context.Context, resolverAddr, name string) DNSLookup {
	start := time.Now()
	r := &net.Resolver{
		PreferGo: true,
		Dial: func(ctx context.Context, network, _ string) (net.Conn, error) {
			d := net.Dialer{Timeout: 2 * time.Second}
			return d.DialContext(ctx, "udp", resolverAddr)
		},
	}
	addrs, err := r.LookupHost(ctx, name)
	out := DNSLookup{
		Resolver: resolverAddr,
		Name:     name,
		Addrs:    addrs,
		Millis:   float64(time.Since(start).Microseconds()) / 1000,
	}
	if err != nil {
		out.Error = err.Error()
	}
	return out
}

func lookupSystem(ctx context.Context, name string) DNSLookup {
	start := time.Now()
	addrs, err := net.DefaultResolver.LookupHost(ctx, name)
	out := DNSLookup{
		Resolver: "system",
		Name:     name,
		Addrs:    addrs,
		Millis:   float64(time.Since(start).Microseconds()) / 1000,
	}
	if err != nil {
		out.Error = err.Error()
	}
	return out
}

func fetchHTTPS(ctx context.Context, rawURL string) HTTPPath {
	var remote string
	dialer := &net.Dialer{Timeout: 8 * time.Second}
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{MinVersion: tls.VersionTLS12},
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			c, err := dialer.DialContext(ctx, network, addr)
			if err == nil {
				remote = c.RemoteAddr().String()
			}
			return c, err
		},
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   12 * time.Second,
	}
	start := time.Now()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return HTTPPath{URL: rawURL, Error: err.Error()}
	}
	resp, err := client.Do(req)
	out := HTTPPath{
		URL:    rawURL,
		Remote: remote,
		Millis: float64(time.Since(start).Microseconds()) / 1000,
	}
	if err != nil {
		out.Error = err.Error()
		return out
	}
	defer resp.Body.Close()
	_, _ = io.CopyN(io.Discard, resp.Body, 64<<10)
	out.Status = resp.StatusCode
	out.Via = resp.Header.Get("Via")
	return out
}

func runDNS(ctx context.Context, name string) DNSReport {
	host, _ := os.Hostname()
	rep := DNSReport{Hostname: host}
	rep.Lookups = []DNSLookup{
		lookupVia(ctx, "192.168.3.1:53", name),
		lookupVia(ctx, "1.1.1.1:53", name),
		lookupSystem(ctx, name),
	}
	rep.HTTPS = fetchHTTPS(ctx, "https://"+name+"/web/")
	public := false
	for _, l := range rep.Lookups {
		for _, a := range l.Addrs {
			if a == "154.65.111.172" || strings.HasPrefix(a, "154.65.111.172:") {
				public = true
			}
		}
	}
	if strings.HasPrefix(rep.HTTPS.Remote, "154.65.111.172") {
		public = true
	}
	rep.Hairpin = public
	if public {
		rep.Notes = append(rep.Notes,
			"LAN DNS (192.168.3.1) and public DNS both return the xcloud-caddy edge. There is no split-horizon; a 192.168.3.0/24 client using the public hostname hairpins through the cloud VM.")
	}
	return rep
}
