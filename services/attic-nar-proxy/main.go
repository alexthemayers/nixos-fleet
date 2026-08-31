// attic-nar-proxy sits in front of atticd and turns single-chunk NAR 307s
// into 200s. atticd redirects those NARs to a Garage presigned URL; Nix's
// HTTP binary-cache store treats a 307 with an empty body as "path is not
// valid" and will not substitute.
//
// Caddy cannot do this hop: reverse_proxy {Location} treats the path as a
// port, and rewrite/map re-encodes the query string, which breaks SigV4.
package main

import (
	"flag"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"time"
)

func main() {
	listen := flag.String("listen", ":8080", "listen address")
	upstream := flag.String("upstream", "http://127.0.0.1:8081", "atticd base URL")
	flag.Parse()

	u, err := url.Parse(*upstream)
	if err != nil {
		log.Fatal(err)
	}

	s3 := &http.Client{
		Timeout: 0,
		Transport: &http.Transport{
			DisableCompression: true,
			IdleConnTimeout:    90 * time.Second,
		},
	}

	proxy := &httputil.ReverseProxy{
		Rewrite: func(pr *httputil.ProxyRequest) {
			// Keep the client's Host. atticd puts it in API URLs; sending
			// 127.0.0.1:8081 makes `attic push` from another machine connect
			// to its own loopback and fail.
			incomingHost := pr.In.Host
			pr.SetXForwarded()
			pr.SetURL(u)
			pr.Out.Host = incomingHost
		},
		FlushInterval: -1,
		ModifyResponse: func(resp *http.Response) error {
			return followS3Redirect(s3, resp)
		},
	}

	srv := &http.Server{
		Addr:              *listen,
		Handler:           proxy,
		ReadHeaderTimeout: 10 * time.Second,
	}
	log.Printf("attic-nar-proxy listen %s -> %s", *listen, u)
	log.Fatal(srv.ListenAndServe())
}

func followS3Redirect(s3 *http.Client, resp *http.Response) error {
	switch resp.StatusCode {
	case http.StatusMovedPermanently, http.StatusFound,
		http.StatusTemporaryRedirect, http.StatusPermanentRedirect:
	default:
		return nil
	}

	req := resp.Request
	if req == nil || (req.Method != http.MethodGet && req.Method != http.MethodHead) {
		return nil
	}
	loc := resp.Header.Get("Location")
	if loc == "" {
		return nil
	}

	// Presigned Garage URLs are signed for GET. Nix HEADs NARs when narinfo
	// omits FileSize; forwarding HEAD yields 403 and the substituter skips
	// the path. Always GET the object, then drop the body for HEAD clients.
	s3req, err := http.NewRequestWithContext(req.Context(), http.MethodGet, loc, nil)
	if err != nil {
		return err
	}

	s3resp, err := s3.Do(s3req)
	if err != nil {
		_ = resp.Body.Close()
		return err
	}

	_ = resp.Body.Close()
	resp.Status = s3resp.Status
	resp.StatusCode = s3resp.StatusCode
	resp.Proto = s3resp.Proto
	resp.ProtoMajor = s3resp.ProtoMajor
	resp.ProtoMinor = s3resp.ProtoMinor
	resp.Header = s3resp.Header.Clone()
	resp.ContentLength = s3resp.ContentLength
	resp.Trailer = s3resp.Trailer
	resp.TransferEncoding = s3resp.TransferEncoding
	resp.Uncompressed = s3resp.Uncompressed
	if req.Method == http.MethodHead {
		_, _ = io.Copy(io.Discard, s3resp.Body)
		_ = s3resp.Body.Close()
		resp.Body = http.NoBody
		return nil
	}
	resp.Body = s3resp.Body
	return nil
}
