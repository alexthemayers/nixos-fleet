package main

import (
	"context"
	"io"
	"net/http"
	"sync"
	"time"
)

type HealthSample struct {
	At     time.Time `json:"at"`
	Status int       `json:"status,omitempty"`
	Millis float64   `json:"millis"`
	Error  string    `json:"error,omitempty"`
}

type HealthSummary struct {
	URL       string         `json:"url"`
	OK        int            `json:"ok"`
	Fail      int            `json:"fail"`
	AvgMillis float64        `json:"avg_millis"`
	MaxMillis float64        `json:"max_millis"`
	LastError string         `json:"last_error,omitempty"`
	Samples   []HealthSample `json:"-"`
}

func pollHealth(ctx context.Context, rawURL string, every time.Duration) HealthSummary {
	sum := HealthSummary{URL: rawURL}
	if rawURL == "" {
		return sum
	}
	client := &http.Client{Timeout: 2 * time.Second}
	tick := time.NewTicker(every)
	defer tick.Stop()
	hit := func() {
		start := time.Now()
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
		s := HealthSample{At: start}
		if err != nil {
			s.Error = err.Error()
			s.Millis = float64(time.Since(start).Microseconds()) / 1000
			sum.Fail++
			sum.LastError = s.Error
			sum.Samples = append(sum.Samples, s)
			return
		}
		resp, err := client.Do(req)
		s.Millis = float64(time.Since(start).Microseconds()) / 1000
		if s.Millis > sum.MaxMillis {
			sum.MaxMillis = s.Millis
		}
		if err != nil {
			s.Error = err.Error()
			sum.Fail++
			sum.LastError = s.Error
			sum.Samples = append(sum.Samples, s)
			return
		}
		_, _ = io.CopyN(io.Discard, resp.Body, 8<<10)
		resp.Body.Close()
		s.Status = resp.StatusCode
		if resp.StatusCode >= 200 && resp.StatusCode < 400 {
			sum.OK++
		} else {
			sum.Fail++
			sum.LastError = resp.Status
		}
		sum.Samples = append(sum.Samples, s)
	}
	hit()
	for {
		select {
		case <-ctx.Done():
			if n := sum.OK + sum.Fail; n > 0 {
				var total float64
				for _, s := range sum.Samples {
					total += s.Millis
				}
				sum.AvgMillis = total / float64(n)
			}
			return sum
		case <-tick.C:
			hit()
		}
	}
}

func startHealth(ctx context.Context, url string) (func() HealthSummary, context.CancelFunc) {
	hctx, stop := context.WithCancel(ctx)
	var (
		mu  sync.Mutex
		sum HealthSummary
		wg  sync.WaitGroup
	)
	if url == "" {
		return func() HealthSummary { return HealthSummary{} }, stop
	}
	wg.Add(1)
	go func() {
		defer wg.Done()
		s := pollHealth(hctx, url, time.Second)
		mu.Lock()
		sum = s
		mu.Unlock()
	}()
	return func() HealthSummary {
		stop()
		wg.Wait()
		mu.Lock()
		defer mu.Unlock()
		return sum
	}, stop
}
