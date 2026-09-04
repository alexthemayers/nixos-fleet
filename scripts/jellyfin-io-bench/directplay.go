package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// UHD Blu-ray max payload. A 4K remux like Oppenheimer averages far less
// (~65 Mbps for this file); draining at the disc cap is the stall bar.
const uhdBDMaxMbps = 128.0

type DirectPlayReport struct {
	Input           string            `json:"input"`
	FileSize        uint64            `json:"file_size"`
	DurationSeconds float64           `json:"duration_seconds,omitempty"`
	AvgMbps         float64           `json:"avg_mbps,omitempty"`
	DrainMbps       float64           `json:"drain_mbps"`
	BufferSeconds   float64           `json:"buffer_seconds"`
	MediaMount      string            `json:"media_mount"`
	Pass            bool              `json:"pass"`
	Phases          []DirectPlayPhase `json:"phases"`
	Notes           []string          `json:"notes"`
}

type DirectPlayPhase struct {
	Name           string    `json:"name"`
	Kind           string    `json:"kind"`
	WallSeconds    float64   `json:"wall_seconds"`
	ReadMiB        float64   `json:"read_mib"`
	AvgMbps        float64   `json:"avg_mbps"`
	MinWindowMbps  float64   `json:"min_window_mbps"`
	P5WindowMbps   float64   `json:"p5_window_mbps"`
	MaxWindowMbps  float64   `json:"max_window_mbps"`
	PrerollSeconds float64   `json:"preroll_seconds,omitempty"`
	PlayingSeconds float64   `json:"playing_seconds,omitempty"`
	StallCount     int       `json:"stall_count"`
	StallSeconds   float64   `json:"stall_seconds"`
	SpeedMin       float64   `json:"ffmpeg_speed_min,omitempty"`
	OutTimeSeconds float64   `json:"ffmpeg_out_time_seconds,omitempty"`
	Pass           bool      `json:"pass"`
	Error          string    `json:"error,omitempty"`
	NFS            *NFSSnap  `json:"nfs_delta,omitempty"`
	Windows        []float64 `json:"windows_mbps,omitempty"`
}

func findFFprobe(ffmpegPath string) string {
	if ffmpegPath != "" {
		p := filepath.Join(filepath.Dir(ffmpegPath), "ffprobe")
		if st, err := os.Stat(p); err == nil && !st.IsDir() {
			return p
		}
	}
	matches, err := filepath.Glob("/nix/store/*-jellyfin-ffmpeg-*-bin/bin/ffprobe")
	if err == nil && len(matches) > 0 {
		return matches[len(matches)-1]
	}
	if st, err := os.Stat("/run/current-system/sw/bin/ffprobe"); err == nil && !st.IsDir() {
		return "/run/current-system/sw/bin/ffprobe"
	}
	return ""
}

func probeMedia(ffprobe, input string) (duration float64, bitRate uint64, size uint64, err error) {
	st, err := os.Stat(input)
	if err != nil {
		return 0, 0, 0, err
	}
	size = uint64(st.Size())
	if ffprobe == "" {
		return 0, 0, size, nil
	}
	cmd := exec.Command(ffprobe, "-v", "error",
		"-show_entries", "format=duration,bit_rate,size",
		"-of", "default=noprint_wrappers=1", input)
	out, err := cmd.Output()
	if err != nil {
		return 0, 0, size, fmt.Errorf("ffprobe: %w", err)
	}
	for _, line := range strings.Split(string(out), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch k {
		case "duration":
			duration, _ = strconv.ParseFloat(v, 64)
		case "bit_rate":
			bitRate, _ = strconv.ParseUint(v, 10, 64)
		case "size":
			if n, e := strconv.ParseUint(v, 10, 64); e == nil && n > 0 {
				size = n
			}
		}
	}
	return duration, bitRate, size, nil
}

func dropCaches() error {
	if err := exec.Command("sync").Run(); err != nil {
		return err
	}
	return os.WriteFile("/proc/sys/vm/drop_caches", []byte("3\n"), 0o644)
}

func percentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	if p <= 0 {
		return sorted[0]
	}
	if p >= 1 {
		return sorted[len(sorted)-1]
	}
	idx := int(p * float64(len(sorted)-1))
	return sorted[idx]
}

func windowStats(windows []float64) (min, p5, max, avg float64) {
	if len(windows) == 0 {
		return 0, 0, 0, 0
	}
	cp := append([]float64(nil), windows...)
	sort.Float64s(cp)
	min, max = cp[0], cp[len(cp)-1]
	p5 = percentile(cp, 0.05)
	var sum float64
	for _, w := range windows {
		sum += w
	}
	avg = sum / float64(len(windows))
	return min, p5, max, avg
}

func runSequentialMax(ctx context.Context, input, mediaMount string, offset int64, runFor time.Duration) DirectPlayPhase {
	ph := DirectPlayPhase{Name: "nfs_sequential_max", Kind: "sequential"}
	f, err := os.Open(input)
	if err != nil {
		ph.Error = err.Error()
		return ph
	}
	defer f.Close()
	if offset > 0 {
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			ph.Error = err.Error()
			return ph
		}
	}
	nfs0 := readNFSSnap(mediaMount)
	buf := make([]byte, 1<<20)
	start := time.Now()
	var (
		total    uint64
		winBytes uint64
		windows  []float64
		nextWin  = start.Add(time.Second)
	)
	for {
		if err := ctx.Err(); err != nil {
			ph.Error = err.Error()
			break
		}
		if time.Since(start) >= runFor {
			break
		}
		n, err := f.Read(buf)
		total += uint64(n)
		winBytes += uint64(n)
		now := time.Now()
		for !nextWin.After(now) {
			windows = append(windows, 8*float64(winBytes)/1e6)
			winBytes = 0
			nextWin = nextWin.Add(time.Second)
		}
		if n == 0 || err == io.EOF {
			break
		}
		if err != nil {
			ph.Error = err.Error()
			break
		}
	}
	if winBytes > 0 {
		dt := time.Since(nextWin.Add(-time.Second)).Seconds()
		if dt < 0.2 {
			dt = 0.2
		}
		windows = append(windows, 8*float64(winBytes)/1e6/dt)
	}
	wall := time.Since(start).Seconds()
	ph.WallSeconds = wall
	ph.ReadMiB = mib(total)
	if wall > 0 {
		ph.AvgMbps = 8 * float64(total) / 1e6 / wall
	}
	ph.MinWindowMbps, ph.P5WindowMbps, ph.MaxWindowMbps, _ = windowStats(windows)
	ph.Windows = windows
	if nfs1 := readNFSSnap(mediaMount); nfs0.Found || nfs1.Found {
		d := nfsDelta(nfs0, nfs1)
		ph.NFS = &d
	}
	return ph
}

func runPlayerSim(ctx context.Context, input, mediaMount string, offset int64, runFor time.Duration, drainBps float64, buffer time.Duration) DirectPlayPhase {
	ph := DirectPlayPhase{Name: "player_buffer", Kind: "player"}
	capBytes := drainBps * buffer.Seconds()
	preroll := capBytes
	f, err := os.Open(input)
	if err != nil {
		ph.Error = err.Error()
		return ph
	}
	defer f.Close()
	if offset > 0 {
		if _, err := f.Seek(offset, io.SeekStart); err != nil {
			ph.Error = err.Error()
			return ph
		}
	}
	nfs0 := readNFSSnap(mediaMount)
	buf := make([]byte, 1<<20)
	start := time.Now()
	last := start
	var (
		level     float64
		playing   bool
		playStart time.Time
		total     uint64
		stallN    int
		stallDur  time.Duration
		winBytes  uint64
		windows   []float64
		nextWin   = start.Add(time.Second)
	)
	drain := func(dt time.Duration) {
		if dt <= 0 || !playing {
			return
		}
		need := drainBps * dt.Seconds()
		if level < need {
			miss := (need - level) / drainBps
			stallDur += time.Duration(miss * float64(time.Second))
			stallN++
			level = 0
			return
		}
		level -= need
	}
	for {
		if err := ctx.Err(); err != nil {
			ph.Error = err.Error()
			break
		}
		now := time.Now()
		if now.Sub(start) >= runFor {
			drain(now.Sub(last))
			last = now
			break
		}
		if playing && level >= capBytes-1 {
			time.Sleep(5 * time.Millisecond)
			n := time.Now()
			drain(n.Sub(last))
			last = n
			continue
		}
		toRead := len(buf)
		if playing {
			space := int(capBytes - level)
			if space < 1 {
				space = 1
			}
			if space < toRead {
				toRead = space
			}
		}
		n, err := f.Read(buf[:toRead])
		got := time.Now()
		drain(got.Sub(last))
		last = got
		total += uint64(n)
		winBytes += uint64(n)
		level += float64(n)
		if !playing && level >= preroll {
			playing = true
			playStart = got
			ph.PrerollSeconds = got.Sub(start).Seconds()
		}
		for !nextWin.After(got) {
			windows = append(windows, 8*float64(winBytes)/1e6)
			winBytes = 0
			nextWin = nextWin.Add(time.Second)
		}
		if n == 0 && err == io.EOF {
			break
		}
		if err != nil && err != io.EOF {
			ph.Error = err.Error()
			break
		}
	}
	wall := time.Since(start).Seconds()
	ph.WallSeconds = wall
	ph.ReadMiB = mib(total)
	if wall > 0 {
		ph.AvgMbps = 8 * float64(total) / 1e6 / wall
	}
	if playing {
		ph.PlayingSeconds = time.Since(playStart).Seconds()
	}
	ph.StallCount = stallN
	ph.StallSeconds = stallDur.Seconds()
	ph.MinWindowMbps, ph.P5WindowMbps, ph.MaxWindowMbps, _ = windowStats(windows)
	ph.Windows = windows
	if nfs1 := readNFSSnap(mediaMount); nfs0.Found || nfs1.Found {
		d := nfsDelta(nfs0, nfs1)
		ph.NFS = &d
	}
	if !playing {
		ph.Error = "buffer never reached preroll"
	}
	return ph
}

func parseFFmpegProgress(r io.Reader, onSample func(speed, outTime float64)) {
	sc := bufio.NewScanner(r)
	var speed, outTime float64
	for sc.Scan() {
		line := sc.Text()
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		switch k {
		case "speed":
			v = strings.TrimSuffix(v, "x")
			if v == "N/A" {
				speed = 0
			} else {
				speed, _ = strconv.ParseFloat(v, 64)
			}
		case "out_time_us":
			us, _ := strconv.ParseFloat(v, 64)
			if us > 0 {
				outTime = us / 1e6
			}
		case "progress":
			if v == "continue" || v == "end" {
				onSample(speed, outTime)
			}
		}
	}
}

func runFFmpegCopy(ctx context.Context, ffmpeg, input string, seek, mediaFor time.Duration, paced bool, mediaMount string) DirectPlayPhase {
	name := "ffmpeg_copy"
	if paced {
		name = "ffmpeg_copy_re"
	}
	ph := DirectPlayPhase{Name: name, Kind: "ffmpeg"}
	args := []string{"-hide_banner", "-nostdin", "-loglevel", "warning", "-progress", "pipe:1", "-stats_period", "0.5"}
	if seek > 0 {
		args = append(args, "-ss", fmt.Sprintf("%.3f", seek.Seconds()))
	}
	if paced {
		args = append(args, "-re")
	}
	args = append(args, "-i", input, "-t", fmt.Sprintf("%.3f", mediaFor.Seconds()),
		"-map", "0", "-c", "copy", "-f", "null", "-")
	cmd := exec.CommandContext(ctx, ffmpeg, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		ph.Error = err.Error()
		return ph
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	nfs0 := readNFSSnap(mediaMount)
	start := time.Now()
	if err := cmd.Start(); err != nil {
		ph.Error = err.Error()
		return ph
	}
	var (
		minSpeed = 1e9
		lastOut  float64
		slowN    int
		slowRun  int
		windows  []float64
		prevOut  float64
		prevWall = start
	)
	parseFFmpegProgress(stdout, func(speed, outTime float64) {
		if speed > 0 && speed < minSpeed {
			minSpeed = speed
		}
		lastOut = outTime
		now := time.Now()
		dt := now.Sub(prevWall).Seconds()
		dMedia := outTime - prevOut
		if dt > 0 && dMedia > 0 && !paced {
			// unpaced: instantaneous "how many × realtime" as Mbps is not needed;
			// record media-seconds per wall-second as a speed window.
			windows = append(windows, dMedia/dt)
		}
		if paced && speed > 0 && speed < 0.90 {
			slowRun++
			if slowRun == 3 {
				slowN++
			}
		} else {
			slowRun = 0
		}
		prevOut = outTime
		prevWall = now
	})
	waitErr := cmd.Wait()
	wall := time.Since(start).Seconds()
	ph.WallSeconds = wall
	ph.OutTimeSeconds = lastOut
	if minSpeed < 1e9 {
		ph.SpeedMin = minSpeed
	}
	ph.StallCount = slowN
	if paced && lastOut > 0 && wall > lastOut+2 {
		ph.StallSeconds = wall - lastOut
	}
	if !paced && len(windows) > 0 {
		ph.MinWindowMbps, ph.P5WindowMbps, ph.MaxWindowMbps, _ = windowStats(windows)
		ph.Windows = windows
	}
	if nfs1 := readNFSSnap(mediaMount); nfs0.Found || nfs1.Found {
		d := nfsDelta(nfs0, nfs1)
		ph.NFS = &d
		ph.ReadMiB = mib(d.ServerRead)
		if wall > 0 && d.ServerRead > 0 {
			ph.AvgMbps = 8 * float64(d.ServerRead) / 1e6 / wall
		}
	}
	if waitErr != nil && ctx.Err() == nil {
		tail := strings.TrimSpace(stderr.String())
		if tail != "" {
			ph.Error = waitErr.Error() + ": " + lastLines(tail, 8)
		} else {
			ph.Error = waitErr.Error()
		}
	}
	return ph
}

type directPlayOpts struct {
	Input      string
	FFmpeg     string
	FFprobe    string
	MediaMount string
	RunFor     time.Duration
	Seek       time.Duration
	DrainMbps  float64
	Buffer     time.Duration
	DropCache  bool
}

func runDirectPlay(ctx context.Context, o directPlayOpts) (DirectPlayReport, error) {
	rep := DirectPlayReport{
		Input:         o.Input,
		DrainMbps:     o.DrainMbps,
		BufferSeconds: o.Buffer.Seconds(),
		MediaMount:    o.MediaMount,
	}
	dur, br, size, err := probeMedia(o.FFprobe, o.Input)
	if err != nil {
		return rep, err
	}
	rep.FileSize = size
	rep.DurationSeconds = dur
	if br > 0 {
		rep.AvgMbps = float64(br) / 1e6
	} else if dur > 0 && size > 0 {
		rep.AvgMbps = 8 * float64(size) / 1e6 / dur
	}
	if o.DrainMbps <= 0 {
		o.DrainMbps = uhdBDMaxMbps
		rep.DrainMbps = o.DrainMbps
	}
	if ft := findmntFSType(o.MediaMount); ft != "nfs" {
		rep.Notes = append(rep.Notes, "media mount "+o.MediaMount+" is "+ft+", not nfs")
	}

	var offset int64
	if o.Seek > 0 && dur > 0 {
		frac := o.Seek.Seconds() / dur
		if frac > 0 && frac < 0.9 {
			offset = int64(float64(size) * frac)
		}
	}

	drop := func(why string) {
		if !o.DropCache {
			return
		}
		if err := dropCaches(); err != nil {
			rep.Notes = append(rep.Notes, "drop_caches ("+why+"): "+err.Error())
			return
		}
		rep.Notes = append(rep.Notes, "dropped page cache before "+why)
	}

	drop("player_buffer")
	player := runPlayerSim(ctx, o.Input, o.MediaMount, offset, o.RunFor, o.DrainMbps*1e6/8, o.Buffer)
	player.Pass = player.Error == "" && player.StallCount == 0 && player.PlayingSeconds > 0
	rep.Phases = append(rep.Phases, player)

	drop("nfs_sequential_max")
	seq := runSequentialMax(ctx, o.Input, o.MediaMount, offset, o.RunFor)
	seq.Pass = seq.Error == "" && seq.AvgMbps >= o.DrainMbps
	rep.Phases = append(rep.Phases, seq)

	if o.FFmpeg != "" {
		seek := o.Seek
		if dur > 0 && seek.Seconds() >= dur {
			seek = 0
		}
		copyFast := runFFmpegCopy(ctx, o.FFmpeg, o.Input, seek, o.RunFor, false, o.MediaMount)
		copyFast.Pass = copyFast.Error == "" && copyFast.OutTimeSeconds >= o.RunFor.Seconds()*0.95
		rep.Phases = append(rep.Phases, copyFast)

		copyRe := runFFmpegCopy(ctx, o.FFmpeg, o.Input, seek, o.RunFor, true, o.MediaMount)
		copyRe.Pass = copyRe.Error == "" && copyRe.StallCount == 0 && copyRe.OutTimeSeconds >= o.RunFor.Seconds()*0.95
		if copyRe.StallSeconds > 2 {
			copyRe.Pass = false
		}
		rep.Phases = append(rep.Phases, copyRe)
	}

	rep.Pass = true
	for _, p := range rep.Phases {
		if !p.Pass {
			rep.Pass = false
			break
		}
	}
	rep.Notes = append(rep.Notes,
		fmt.Sprintf("player drains at %.0f Mbps (UHD BD max) with a %.0fs buffer; file average is %.1f Mbps.",
			o.DrainMbps, o.Buffer.Seconds(), rep.AvgMbps),
		"nfs_sequential_max is an uncapped cold-ish read. player_buffer only reads when the virtual client has room, so a multi-second NFS hang underruns.",
		"ffmpeg_copy is 1× media seconds demuxed as fast as the NFS+demux path allows. ffmpeg_copy_re is timestamp-paced (Direct Play analogue); speed < 0.90 for 1.5s is a stall.",
	)
	return rep, nil
}

func printDirectPlay(r DirectPlayReport) {
	fmt.Printf("== direct play ==\n")
	fmt.Printf("  input=%s\n", r.Input)
	fmt.Printf("  size=%.1f GiB duration=%.0fs avg=%.1f Mbps drain=%.0f Mbps buffer=%.0fs pass=%v\n",
		float64(r.FileSize)/1024/1024/1024, r.DurationSeconds, r.AvgMbps, r.DrainMbps, r.BufferSeconds, r.Pass)
	for _, p := range r.Phases {
		fmt.Printf("  -- %s (%s) pass=%v wall=%.1fs read=%.1f MiB avg=%.1f Mbps\n",
			p.Name, p.Kind, p.Pass, p.WallSeconds, p.ReadMiB, p.AvgMbps)
		if p.Kind == "sequential" || p.Kind == "player" {
			fmt.Printf("     windows min=%.1f p5=%.1f max=%.1f Mbps\n",
				p.MinWindowMbps, p.P5WindowMbps, p.MaxWindowMbps)
		}
		if p.Kind == "player" {
			fmt.Printf("     preroll=%.2fs playing=%.1fs stalls=%d (%.2fs)\n",
				p.PrerollSeconds, p.PlayingSeconds, p.StallCount, p.StallSeconds)
		}
		if p.Kind == "ffmpeg" {
			fmt.Printf("     out_time=%.1fs speed_min=%.2fx stalls=%d lag=%.2fs\n",
				p.OutTimeSeconds, p.SpeedMin, p.StallCount, p.StallSeconds)
		}
		if p.NFS != nil && p.NFS.Found {
			fmt.Printf("     nfs read=%.1f MiB badxid=%d\n", mib(p.NFS.ServerRead), p.NFS.BadXIDs)
		}
		if p.Error != "" {
			fmt.Printf("     err=%s\n", p.Error)
		}
	}
	for _, n := range r.Notes {
		fmt.Printf("  note: %s\n", n)
	}
}
