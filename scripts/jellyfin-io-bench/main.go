package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const defaultInput = "/mnt/nfs/media/movies/Oppenheimer.2023.2160p.UHD.Bluray.REMUX.HDR10.HEVC.DTS-HD.MA.5.1-GHD[TGx]/Oppenheimer.2023.2160p.UHD.Bluray.REMUX.HDR10.HEVC.DTS-HD.MA.5.1-GHD.mkv"

type Report struct {
	StartedAt string        `json:"started_at"`
	Hostname  string        `json:"hostname"`
	DNS       *DNSReport    `json:"dns,omitempty"`
	Probe     *ProbeReport  `json:"probe,omitempty"`
	Phases    []PhaseResult `json:"phases"`
	Notes     []string      `json:"notes"`
}

func ffmpegFromJellyfin() string {
	ents, err := os.ReadDir("/proc")
	if err != nil {
		return ""
	}
	for _, e := range ents {
		if !e.IsDir() {
			continue
		}
		cmd, err := os.ReadFile(filepath.Join("/proc", e.Name(), "cmdline"))
		if err != nil {
			continue
		}
		args := strings.Split(string(cmd), "\x00")
		looksLike := false
		for _, a := range args {
			if strings.Contains(a, "/bin/jellyfin") || strings.HasSuffix(a, "jellyfin") {
				looksLike = true
				break
			}
		}
		if !looksLike {
			continue
		}
		for i, a := range args {
			if v, ok := strings.CutPrefix(a, "--ffmpeg="); ok {
				return v
			}
			if a == "--ffmpeg" && i+1 < len(args) {
				return args[i+1]
			}
		}
	}
	return ""
}

func findFFmpeg() (string, error) {
	if p := ffmpegFromJellyfin(); p != "" {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	if p, err := os.Stat("/run/current-system/sw/bin/ffmpeg"); err == nil && !p.IsDir() {
		return "/run/current-system/sw/bin/ffmpeg", nil
	}
	matches, err := filepath.Glob("/nix/store/*-jellyfin-ffmpeg-*-bin/bin/ffmpeg")
	if err != nil {
		return "", err
	}
	if len(matches) == 0 {
		return "", fmt.Errorf("no jellyfin-ffmpeg in /nix/store; pass -ffmpeg")
	}
	return matches[len(matches)-1], nil
}

func lookupIDs(name string) (int, int, error) {
	u, err := user.Lookup(name)
	if err != nil {
		return 0, 0, err
	}
	uid, err := strconv.Atoi(u.Uid)
	if err != nil {
		return 0, 0, err
	}
	gid, err := strconv.Atoi(u.Gid)
	if err != nil {
		return 0, 0, err
	}
	return uid, gid, nil
}

func printPhase(p PhaseResult) {
	fmt.Printf("\n== %s ==\n", p.Name)
	fmt.Printf("  dest=%s fstype=%s throttle(-re)=%v wall=%.1fs ffmpeg=%s\n",
		p.Dest, p.FSType, p.RealtimeThrottle, p.WallSeconds, p.FFmpegExit)
	fmt.Printf("  iowait avg=%.2f%% max=%.2f%%  sda read=%.1f MiB write=%.1f MiB\n",
		p.IOWaitPct, p.IOWaitPctMax, p.SdaMiBRead, p.SdaMiBWritten)
	fmt.Printf("  dest=%.1f MiB (%d files)  root avail Δ=%+.1f MiB (after %.1f MiB)  dest avail Δ=%+.1f MiB\n",
		p.DestMiB, p.Files, p.RootAvailDeltaMiB, p.RootAvailAfterMiB, p.DestAvailDeltaMiB)
	if p.NFS != nil && p.NFS.Found {
		fmt.Printf("  nfs write=%.1f MiB (ops=%d commit=%d)  server read=%.1f MiB  badxid=%d\n",
			mib(p.NFS.ServerWrite), p.NFS.WriteOps, p.NFS.CommitOps, mib(p.NFS.ServerRead), p.NFS.BadXIDs)
	}
	if p.Health != nil && p.Health.URL != "" {
		fmt.Printf("  jellyfin HTTP ok=%d fail=%d avg=%.1fms max=%.1fms",
			p.Health.OK, p.Health.Fail, p.Health.AvgMillis, p.Health.MaxMillis)
		if p.Health.LastError != "" {
			fmt.Printf(" last_err=%s", p.Health.LastError)
		}
		fmt.Println()
	}
	if p.FFmpegTail != "" && p.Name != "idle" {
		fmt.Printf("  ffmpeg tail:\n%s\n", indent(p.FFmpegTail, "    "))
	}
}

func printProbe(p ProbeReport) {
	fmt.Printf("== probe ==\n")
	fmt.Printf("  CachePath xml=%q\n", p.CachePathXML)
	fmt.Printf("  mount %s source=%s fstype=%s addr=%s tailscale=%v size=%.0f MiB avail=%.0f MiB\n",
		p.CacheMount.Target, p.CacheMount.Source, p.CacheMount.FSType, p.CacheMount.ServerAddr,
		p.CacheMount.Tailscale, p.CacheMount.SizeMiB, p.CacheMount.AvailMiB)
	fmt.Printf("  truenas-scale %v (%.1fms) err=%s\n", p.TrueNAS.Addrs, p.TrueNAS.Millis, p.TrueNAS.Error)
	fmt.Printf("  jellyfin %s  HTTP %s status=%d (%.1fms) err=%s\n",
		p.JellyfinActive, p.JellyfinHTTP.URL, p.JellyfinHTTP.Status, p.JellyfinHTTP.Millis, p.JellyfinHTTP.Error)
	for _, w := range p.Writes {
		if w.OK {
			fmt.Printf("  write %s ok owner=%s\n", w.User, w.Owner)
		} else {
			fmt.Printf("  write %s FAIL %s\n", w.User, w.Error)
		}
	}
	for _, u := range p.Units {
		fmt.Printf("  unit %s load=%s active=%s idle=%s what=%s\n",
			u.Name, u.LoadState, u.ActiveState, u.IdleTimeout, u.What)
	}
	for _, n := range p.Notes {
		fmt.Printf("  note: %s\n", n)
	}
}

func indent(s, prefix string) string {
	lines := strings.Split(strings.TrimRight(s, "\n"), "\n")
	for i, l := range lines {
		lines[i] = prefix + l
	}
	return strings.Join(lines, "\n")
}

func main() {
	var (
		cmd         = "all"
		jsonPath    string
		name        = "jellyfin.alexmayers.co.za"
		input       string
		ffmpegPath  string
		workDir     string
		diskDev     = "sda"
		asUser      = ""
		tmpfsSize   = "2048M"
		nfsCache    = "/mnt/nfs/jellyfin/cache"
		healthURL   = "http://127.0.0.1:8096/System/Info/Public"
		xmlPath     = "/mnt/nfs/jellyfin/config/config/system.xml"
		duration    = 120 * time.Second
		idleFor     = 15 * time.Second
		force       bool
		includeDisk bool
	)
	fs := flag.NewFlagSet("jellyfin-io-bench", flag.ExitOnError)
	fs.StringVar(&jsonPath, "json", "", "write the full JSON report to this path")
	fs.StringVar(&name, "host", name, "Jellyfin public hostname for the DNS check")
	fs.StringVar(&input, "input", defaultInput, "4K source file")
	fs.StringVar(&ffmpegPath, "ffmpeg", "", "ffmpeg binary (default: jellyfin-ffmpeg in the nix store)")
	fs.StringVar(&workDir, "workdir", "/var/tmp/jellyfin-io-bench", "scratch directory for tmpfs HLS output")
	fs.StringVar(&nfsCache, "nfs-cache", nfsCache, "original SSD NFS cache mountpoint")
	fs.StringVar(&healthURL, "health", healthURL, "Jellyfin URL to poll during each phase")
	fs.StringVar(&xmlPath, "system-xml", xmlPath, "path to system.xml for CachePath")
	fs.StringVar(&diskDev, "disk", diskDev, "sysfs block device name under /sys/block")
	fs.StringVar(&asUser, "user", asUser, "run ffmpeg as this user (default: root)")
	fs.StringVar(&tmpfsSize, "tmpfs-size", tmpfsSize, "tmpfs size for the throttled control phase")
	fs.DurationVar(&duration, "duration", duration, "wall time for each transcode phase")
	fs.DurationVar(&idleFor, "idle", idleFor, "idle sample before transcodes")
	fs.BoolVar(&force, "force", false, "allow running on a host other than proxmox-applications-1")
	fs.BoolVar(&includeDisk, "include-disk", false, "also run unthrottled HLS onto the VM root (fills gigabytes)")
	fs.Usage = func() {
		fmt.Fprintf(os.Stderr, `Usage: jellyfin-io-bench [flags] [dns|probe|transcode|all]

Go I/O bench for Jellyfin on proxmox-applications-1. Run it on that host
(not on the laptop). Subcommands:

  dns        resolve and fetch https://jellyfin.alexmayers.co.za from this box
  probe      NFS cache mount, uid write, automount, Jellyfin HTTP
  transcode  idle, then 4K QSV HLS onto the SSD NFS cache (unthrottled and -re) vs tmpfs
  all        dns, probe, transcode (default)

`)
		fs.PrintDefaults()
	}
	if err := fs.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}
	if fs.NArg() == 1 {
		cmd = fs.Arg(0)
	} else if fs.NArg() > 1 {
		fs.Usage()
		os.Exit(2)
	}

	hostname, _ := os.Hostname()
	needRoot := cmd == "transcode" || cmd == "all" || cmd == "probe"
	if !force && hostname != "proxmox-applications-1" && (cmd == "transcode" || cmd == "all") {
		fmt.Fprintf(os.Stderr, "refusing to transcode on %s (pass -force if you mean it)\n", hostname)
		os.Exit(2)
	}
	if os.Geteuid() != 0 && needRoot {
		fmt.Fprintln(os.Stderr, "probe/transcode need root (mounts, iostat, runuser)")
		os.Exit(2)
	}

	ctx := context.Background()
	rep := Report{
		StartedAt: time.Now().Format(time.RFC3339),
		Hostname:  hostname,
	}

	if cmd == "dns" || cmd == "all" {
		d := runDNS(ctx, name)
		rep.DNS = &d
		fmt.Printf("== dns on %s ==\n", hostname)
		for _, l := range d.Lookups {
			fmt.Printf("  %-18s %v", l.Resolver, l.Addrs)
			if l.Error != "" {
				fmt.Printf(" err=%s", l.Error)
			}
			fmt.Printf(" (%.1fms)\n", l.Millis)
		}
		fmt.Printf("  https %s status=%d remote=%s via=%q (%.1fms)\n",
			d.HTTPS.URL, d.HTTPS.Status, d.HTTPS.Remote, d.HTTPS.Via, d.HTTPS.Millis)
		if d.HTTPS.Error != "" {
			fmt.Printf("  https error: %s\n", d.HTTPS.Error)
		}
		fmt.Printf("  hairpin=%v\n", d.Hairpin)
		for _, n := range d.Notes {
			fmt.Printf("  note: %s\n", n)
		}
	}

	if cmd == "probe" || cmd == "all" {
		p := runProbe(ctx, nfsCache, healthURL, xmlPath)
		rep.Probe = &p
		printProbe(p)
	}

	if cmd == "transcode" || cmd == "all" {
		if ffmpegPath == "" {
			var err error
			ffmpegPath, err = findFFmpeg()
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
		}
		if _, err := os.Stat(input); err != nil {
			fmt.Fprintf(os.Stderr, "input: %v\n", err)
			os.Exit(1)
		}
		if ft := findmntFSType(nfsCache); ft != "nfs" {
			fmt.Fprintf(os.Stderr, "NFS cache %s is %s, not nfs. Mount truenas-scale:/mnt/ssd/jellyfin/cache first.\n", nfsCache, ft)
			os.Exit(1)
		}
		if includeDisk {
			avail, err := rootAvail()
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			if avail < 3<<30 {
				fmt.Fprintf(os.Stderr, "root has %.1f MiB free; need >= 3 GiB for -include-disk\n", mib(avail))
				os.Exit(1)
			}
		}
		var uid, gid int
		var err error
		if asUser != "" {
			uid, gid, err = lookupIDs(asUser)
			if err != nil {
				fmt.Fprintf(os.Stderr, "user %s: %v\n", asUser, err)
				os.Exit(1)
			}
		}

		who := asUser
		if who == "" {
			who = "root"
		}
		fmt.Printf("\nffmpeg=%s\ninput=%s\nduration=%s user=%s (%d:%d)\nnfs-cache=%s\n",
			ffmpegPath, input, duration, who, uid, gid, nfsCache)

		idle, err := idlePhase(ctx, diskDev, healthURL, idleFor)
		if err != nil {
			fmt.Fprintf(os.Stderr, "idle: %v\n", err)
			os.Exit(1)
		}
		printPhase(idle)
		rep.Phases = append(rep.Phases, idle)

		runOne := func(name, dest string, realtime, tmpfs bool) bool {
			p, err := runPhase(ctx, PhaseOpts{
				Name:      name,
				Dest:      dest,
				FFmpeg:    ffmpegPath,
				Input:     input,
				DiskDev:   diskDev,
				AsUser:    asUser,
				Realtime:  realtime,
				RunFor:    duration,
				Tmpfs:     tmpfs,
				TmpfsSize: tmpfsSize,
				UID:       uid,
				GID:       gid,
				HealthURL: healthURL,
				NFSMount:  nfsCache,
			})
			printPhase(p)
			rep.Phases = append(rep.Phases, p)
			if err != nil {
				fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
				writeJSON(jsonPath, rep)
				return false
			}
			return true
		}

		nfsDir := filepath.Join(nfsCache, "io-bench")
		if !runOne("nfs_unthrottled", nfsDir, false, false) {
			os.Exit(1)
		}
		if !runOne("nfs_throttled", nfsDir, true, false) {
			os.Exit(1)
		}
		if includeDisk {
			if !runOne("disk_unthrottled", filepath.Join(workDir, "disk"), false, false) {
				os.Exit(1)
			}
		}
		if !runOne("tmpfs_throttled", filepath.Join(workDir, "tmpfs"), true, true) {
			os.Exit(1)
		}

		rep.Notes = append(rep.Notes,
			"nfs_unthrottled writes HLS as fast as QSV can go onto truenas-scale:/mnt/ssd/jellyfin/cache (original architecture).",
			"nfs_throttled is the same dest with ffmpeg -re (realtime analogue of EnableThrottling).",
			"tmpfs_throttled is a RAM-backed control. sda counters are the VM disk; NFS cache writes show up in nfs_delta, not sda.",
			"NFS reads of the 4K source happen in every transcode phase.",
		)
	}

	if jsonPath != "" {
		if err := writeJSON(jsonPath, rep); err != nil {
			fmt.Fprintf(os.Stderr, "write json: %s\n", err)
			os.Exit(1)
		}
		fmt.Printf("\nwrote %s\n", jsonPath)
	}
}

func writeJSON(path string, rep Report) error {
	if path == "" {
		return nil
	}
	b, err := json.MarshalIndent(rep, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}
