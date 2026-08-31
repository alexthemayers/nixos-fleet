package main

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type cpuTicks struct {
	iowait uint64
	total  uint64
}

type diskTicks struct {
	sectorsRead    uint64
	sectorsWritten uint64
}

type Snapshot struct {
	At              time.Time `json:"at"`
	IOWaitPct       float64   `json:"iowait_pct"`
	SectorsRead     uint64    `json:"sectors_read"`
	SectorsWritten  uint64    `json:"sectors_written"`
	RootAvailBytes  uint64    `json:"root_avail_bytes"`
	DestBytes       uint64    `json:"dest_bytes"`
	MemAvailableKiB uint64    `json:"mem_available_kib"`
}

type PhaseResult struct {
	Name              string         `json:"name"`
	Dest              string         `json:"dest"`
	FSType            string         `json:"fstype"`
	RealtimeThrottle  bool           `json:"realtime_throttle"`
	WallSeconds       float64        `json:"wall_seconds"`
	FFmpegExit        string         `json:"ffmpeg_exit"`
	IOWaitPct         float64        `json:"iowait_pct"`
	IOWaitPctMax      float64        `json:"iowait_pct_max"`
	SdaMiBRead        float64        `json:"sda_mib_read"`
	SdaMiBWritten     float64        `json:"sda_mib_written"`
	DestMiB           float64        `json:"dest_mib"`
	RootAvailDeltaMiB float64        `json:"root_avail_delta_mib"`
	RootAvailAfterMiB float64        `json:"root_avail_after_mib"`
	DestAvailDeltaMiB float64        `json:"dest_avail_delta_mib"`
	DestAvailAfterMiB float64        `json:"dest_avail_after_mib"`
	NFS               *NFSSnap       `json:"nfs_delta,omitempty"`
	Health            *HealthSummary `json:"health,omitempty"`
	Files             int            `json:"files"`
	Samples           []Snapshot     `json:"samples,omitempty"`
	FFmpegTail        string         `json:"ffmpeg_tail,omitempty"`
}

func readCPU() (cpuTicks, error) {
	f, err := os.Open("/proc/stat")
	if err != nil {
		return cpuTicks{}, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if !sc.Scan() {
		return cpuTicks{}, fmt.Errorf("empty /proc/stat")
	}
	fields := strings.Fields(sc.Text())
	// cpu user nice system idle iowait irq softirq steal guest guest_nice
	if len(fields) < 6 || fields[0] != "cpu" {
		return cpuTicks{}, fmt.Errorf("unexpected /proc/stat: %q", sc.Text())
	}
	var total uint64
	for _, f := range fields[1:] {
		n, err := strconv.ParseUint(f, 10, 64)
		if err != nil {
			return cpuTicks{}, err
		}
		total += n
	}
	iowait, err := strconv.ParseUint(fields[5], 10, 64)
	if err != nil {
		return cpuTicks{}, err
	}
	return cpuTicks{iowait: iowait, total: total}, nil
}

func readDisk(dev string) (diskTicks, error) {
	b, err := os.ReadFile("/sys/block/" + dev + "/stat")
	if err != nil {
		return diskTicks{}, err
	}
	fields := strings.Fields(string(b))
	if len(fields) < 7 {
		return diskTicks{}, fmt.Errorf("short diskstat for %s", dev)
	}
	read, err := strconv.ParseUint(fields[2], 10, 64)
	if err != nil {
		return diskTicks{}, err
	}
	written, err := strconv.ParseUint(fields[6], 10, 64)
	if err != nil {
		return diskTicks{}, err
	}
	return diskTicks{sectorsRead: read, sectorsWritten: written}, nil
}

func rootAvail() (uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs("/", &st); err != nil {
		return 0, err
	}
	return uint64(st.Bavail) * uint64(st.Bsize), nil
}

func dirBytes(root string) (uint64, int, error) {
	var size uint64
	var files int
	err := filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		size += uint64(info.Size())
		files++
		return nil
	})
	return size, files, err
}

func memAvailableKiB() uint64 {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if !strings.HasPrefix(line, "MemAvailable:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			return 0
		}
		n, _ := strconv.ParseUint(fields[1], 10, 64)
		return n
	}
	return 0
}

func iowaitPct(a, b cpuTicks) float64 {
	dt := b.total - a.total
	if dt == 0 {
		return 0
	}
	return 100 * float64(b.iowait-a.iowait) / float64(dt)
}

func mib(bytes uint64) float64 {
	return float64(bytes) / 1024 / 1024
}

func mibSectors(sectors uint64) float64 {
	return float64(sectors) * 512 / 1024 / 1024
}
