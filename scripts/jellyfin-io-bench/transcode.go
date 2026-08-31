package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
)

func emptyDir(dir string) error {
	ents, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return os.MkdirAll(dir, 0o750)
		}
		return err
	}
	for _, e := range ents {
		if err := os.RemoveAll(filepath.Join(dir, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

func mountTmpfs(dir, size string, uid, gid int) error {
	if err := os.MkdirAll(dir, 0o750); err != nil {
		return err
	}
	opts := fmt.Sprintf("size=%s,mode=0750,uid=%d,gid=%d,nosuid,nodev,noexec", size, uid, gid)
	cmd := exec.Command("mount", "-t", "tmpfs", "-o", opts, "tmpfs", dir)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("mount tmpfs: %w: %s", err, bytes.TrimSpace(out))
	}
	return nil
}

func unmount(dir string) {
	_ = exec.Command("umount", dir).Run()
}

func runFFmpeg(ctx context.Context, ffmpeg, input, dest string, realtime bool, runFor time.Duration, asUser string) (exit string, tail string, wall float64, err error) {
	args := []string{
		"-hide_banner", "-nostdin", "-y", "-loglevel", "warning", "-stats",
	}
	if realtime {
		args = append(args, "-re")
	}
	args = append(args,
		"-hwaccel", "qsv", "-hwaccel_output_format", "qsv",
		"-qsv_device", "/dev/dri/renderD128",
		"-i", input,
		"-an",
		"-vf", "vpp_qsv=w=1920:h=1080:format=nv12",
		"-c:v", "h264_qsv", "-preset", "veryfast", "-b:v", "8M",
		"-f", "hls", "-hls_time", "4", "-hls_list_size", "0",
		filepath.Join(dest, "bench.m3u8"),
	)
	var cmd *exec.Cmd
	env := append(os.Environ(),
		"LIBVA_DRIVER_NAME=iHD",
		"LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri",
	)
	if asUser != "" && asUser != "root" {
		wrapped := append([]string{"-u", asUser, "--", "env",
			"LIBVA_DRIVER_NAME=iHD",
			"LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri",
			ffmpeg}, args...)
		cmd = exec.Command("runuser", wrapped...)
	} else {
		cmd = exec.Command(ffmpeg, args...)
		cmd.Env = env
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	start := time.Now()
	if err := cmd.Start(); err != nil {
		return "start-failed", buf.String(), 0, err
	}

	stopFF := func(sig syscall.Signal) {
		if cmd.Process == nil {
			return
		}
		_ = syscall.Kill(-cmd.Process.Pid, sig)
	}

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	timer := time.NewTimer(runFor)
	defer timer.Stop()

	select {
	case err := <-done:
		wall = time.Since(start).Seconds()
		if err != nil {
			return err.Error(), lastLines(buf.String(), 12), wall, err
		}
		return "exited", lastLines(buf.String(), 12), wall, nil
	case <-timer.C:
		stopFF(syscall.SIGINT)
		select {
		case err := <-done:
			wall = time.Since(start).Seconds()
			exit = "interrupted"
			if cmd.ProcessState != nil {
				exit = cmd.ProcessState.String()
			}
			if err != nil && !errors.Is(err, context.Canceled) {
				return exit, lastLines(buf.String(), 12), wall, nil
			}
			return exit, lastLines(buf.String(), 12), wall, nil
		case <-time.After(8 * time.Second):
			stopFF(syscall.SIGKILL)
			<-done
			wall = time.Since(start).Seconds()
			return "killed", lastLines(buf.String(), 12), wall, nil
		}
	case <-ctx.Done():
		stopFF(syscall.SIGKILL)
		<-done
		wall = time.Since(start).Seconds()
		return "ctx", lastLines(buf.String(), 12), wall, ctx.Err()
	}
}

func lastLines(s string, n int) string {
	lines := bytes.Split([]byte(s), []byte("\n"))
	if len(lines) <= n {
		return s
	}
	return string(bytes.Join(lines[len(lines)-n:], []byte("\n")))
}

func sampleLoop(ctx context.Context, dest, diskDev string, every time.Duration) ([]Snapshot, cpuTicks, diskTicks, error) {
	cpu0, err := readCPU()
	if err != nil {
		return nil, cpuTicks{}, diskTicks{}, err
	}
	disk0, err := readDisk(diskDev)
	if err != nil {
		return nil, cpuTicks{}, diskTicks{}, err
	}
	var (
		samples []Snapshot
		prevCPU = cpu0
		tick    = time.NewTicker(every)
	)
	defer tick.Stop()
	record := func() error {
		cpu, err := readCPU()
		if err != nil {
			return err
		}
		disk, err := readDisk(diskDev)
		if err != nil {
			return err
		}
		avail, err := rootAvail()
		if err != nil {
			return err
		}
		var destN uint64
		if dest != "" && dest != "/" {
			destN, _, err = dirBytes(dest)
			if err != nil {
				destN = 0
			}
		}
		samples = append(samples, Snapshot{
			At:              time.Now(),
			IOWaitPct:       iowaitPct(prevCPU, cpu),
			SectorsRead:     disk.sectorsRead,
			SectorsWritten:  disk.sectorsWritten,
			RootAvailBytes:  avail,
			DestBytes:       destN,
			MemAvailableKiB: memAvailableKiB(),
		})
		prevCPU = cpu
		return nil
	}
	if err := record(); err != nil {
		return nil, cpu0, disk0, err
	}
	for {
		select {
		case <-ctx.Done():
			_ = record()
			return samples, cpu0, disk0, nil
		case <-tick.C:
			if err := record(); err != nil {
				return samples, cpu0, disk0, err
			}
		}
	}
}

type PhaseOpts struct {
	Name      string
	Dest      string
	FFmpeg    string
	Input     string
	DiskDev   string
	AsUser    string
	Realtime  bool
	RunFor    time.Duration
	Tmpfs     bool
	TmpfsSize string
	UID, GID  int
	HealthURL string
	NFSMount  string
}

func runPhase(ctx context.Context, o PhaseOpts) (PhaseResult, error) {
	res := PhaseResult{Name: o.Name, Dest: o.Dest, RealtimeThrottle: o.Realtime}
	if err := os.MkdirAll(o.Dest, 0o750); err != nil {
		return res, err
	}
	if o.Tmpfs {
		if err := mountTmpfs(o.Dest, o.TmpfsSize, o.UID, o.GID); err != nil {
			return res, err
		}
		defer unmount(o.Dest)
	}
	if err := emptyDir(o.Dest); err != nil {
		return res, err
	}
	if o.AsUser != "" && o.AsUser != "root" {
		if err := os.Chown(o.Dest, o.UID, o.GID); err != nil && !o.Tmpfs {
			return res, err
		}
	}

	avail0, err := rootAvail()
	if err != nil {
		return res, err
	}
	destAvail0, _ := destAvail(o.Dest)
	res.FSType = findmntFSType(o.Dest)
	nfsMount := o.NFSMount
	if nfsMount == "" {
		nfsMount = o.Dest
	}
	nfs0 := readNFSSnap(nfsMount)

	sampleCtx, stopSample := context.WithCancel(ctx)
	defer stopSample()
	waitHealth, stopHealth := startHealth(sampleCtx, o.HealthURL)
	defer stopHealth()
	type sampleOut struct {
		samples []Snapshot
		cpu0    cpuTicks
		disk0   diskTicks
		err     error
	}
	ch := make(chan sampleOut, 1)
	go func() {
		s, c, d, e := sampleLoop(sampleCtx, o.Dest, o.DiskDev, time.Second)
		ch <- sampleOut{s, c, d, e}
	}()

	ffCtx, stopFF := context.WithCancel(ctx)
	defer stopFF()
	exit, tail, wall, ffErr := runFFmpeg(ffCtx, o.FFmpeg, o.Input, o.Dest, o.Realtime, o.RunFor, o.AsUser)
	stopSample()
	out := <-ch
	health := waitHealth()
	if out.err != nil {
		return res, out.err
	}

	cpu1, err := readCPU()
	if err != nil {
		return res, err
	}
	disk1, err := readDisk(o.DiskDev)
	if err != nil {
		return res, err
	}
	avail1, err := rootAvail()
	if err != nil {
		return res, err
	}
	destAvail1, _ := destAvail(o.Dest)
	destN, files, _ := dirBytes(o.Dest)
	var maxWA float64
	for _, s := range out.samples {
		if s.IOWaitPct > maxWA {
			maxWA = s.IOWaitPct
		}
	}

	res.WallSeconds = wall
	res.FFmpegExit = exit
	res.IOWaitPct = iowaitPct(out.cpu0, cpu1)
	res.IOWaitPctMax = maxWA
	res.SdaMiBRead = mibSectors(disk1.sectorsRead - out.disk0.sectorsRead)
	res.SdaMiBWritten = mibSectors(disk1.sectorsWritten - out.disk0.sectorsWritten)
	res.DestMiB = mib(destN)
	res.RootAvailDeltaMiB = (float64(avail1) - float64(avail0)) / 1024 / 1024
	res.RootAvailAfterMiB = mib(avail1)
	res.DestAvailDeltaMiB = (float64(destAvail1) - float64(destAvail0)) / 1024 / 1024
	res.DestAvailAfterMiB = mib(destAvail1)
	res.Files = files
	res.Samples = out.samples
	res.FFmpegTail = tail
	res.Health = &health
	if nfs1 := readNFSSnap(nfsMount); nfs0.Found || nfs1.Found {
		d := nfsDelta(nfs0, nfs1)
		res.NFS = &d
	}

	_ = emptyDir(o.Dest)
	if files == 0 && ffErr != nil {
		return res, fmt.Errorf("ffmpeg wrote no segments (%s): %w\n%s", exit, ffErr, tail)
	}
	return res, nil
}

func idlePhase(ctx context.Context, diskDev, healthURL string, runFor time.Duration) (PhaseResult, error) {
	res := PhaseResult{Name: "idle", Dest: "/", FSType: findmntFSType("/")}
	sampleCtx, stop := context.WithCancel(ctx)
	defer stop()
	waitHealth, stopHealth := startHealth(sampleCtx, healthURL)
	defer stopHealth()
	type sampleOut struct {
		samples []Snapshot
		cpu0    cpuTicks
		disk0   diskTicks
		err     error
	}
	ch := make(chan sampleOut, 1)
	go func() {
		s, c, d, e := sampleLoop(sampleCtx, "/", diskDev, time.Second)
		ch <- sampleOut{s, c, d, e}
	}()
	select {
	case <-ctx.Done():
		stop()
	case <-time.After(runFor):
		stop()
	}
	out := <-ch
	health := waitHealth()
	if out.err != nil {
		return res, out.err
	}
	cpu1, err := readCPU()
	if err != nil {
		return res, err
	}
	disk1, err := readDisk(diskDev)
	if err != nil {
		return res, err
	}
	avail, _ := rootAvail()
	var maxWA float64
	for _, s := range out.samples {
		if s.IOWaitPct > maxWA {
			maxWA = s.IOWaitPct
		}
	}
	res.WallSeconds = runFor.Seconds()
	res.IOWaitPct = iowaitPct(out.cpu0, cpu1)
	res.IOWaitPctMax = maxWA
	res.SdaMiBRead = mibSectors(disk1.sectorsRead - out.disk0.sectorsRead)
	res.SdaMiBWritten = mibSectors(disk1.sectorsWritten - out.disk0.sectorsWritten)
	res.RootAvailAfterMiB = mib(avail)
	res.Samples = out.samples
	res.Health = &health
	return res, nil
}
