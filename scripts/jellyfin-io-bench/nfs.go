package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
	"syscall"
)

const (
	nfsSuperMagic    = 0x6969
	tmpfsMagic       = 0x01021994
	ext4Magic        = 0xEF53
	xfsMagic         = 0x58465342
	autofsSuperMagic = 0x0187
)

type NFSSnap struct {
	NormalRead  uint64 `json:"normal_read"`
	NormalWrite uint64 `json:"normal_write"`
	ServerRead  uint64 `json:"server_read"`
	ServerWrite uint64 `json:"server_write"`
	WriteOps    uint64 `json:"write_ops"`
	CommitOps   uint64 `json:"commit_ops"`
	ReadPlusOps uint64 `json:"read_plus_ops"`
	Sends       uint64 `json:"xprt_sends"`
	Recvs       uint64 `json:"xprt_recvs"`
	BadXIDs     uint64 `json:"xprt_bad_xids"`
	Found       bool   `json:"found"`
}

type MountInfo struct {
	Target     string  `json:"target"`
	Source     string  `json:"source,omitempty"`
	FSType     string  `json:"fstype"`
	Options    string  `json:"options,omitempty"`
	ServerAddr string  `json:"server_addr,omitempty"`
	Tailscale  bool    `json:"server_is_tailscale"`
	AvailMiB   float64 `json:"avail_mib,omitempty"`
	SizeMiB    float64 `json:"size_mib,omitempty"`
}

func destAvail(path string) (uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, err
	}
	return uint64(st.Bavail) * uint64(st.Bsize), nil
}

func destSize(path string) (uint64, uint64, error) {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return 0, 0, err
	}
	return uint64(st.Blocks) * uint64(st.Bsize), uint64(st.Bavail) * uint64(st.Bsize), nil
}

func findmntFSType(path string) string {
	var st syscall.Statfs_t
	if err := syscall.Statfs(path, &st); err != nil {
		return "unknown"
	}
	switch st.Type {
	case tmpfsMagic:
		return "tmpfs"
	case ext4Magic:
		return "ext4"
	case xfsMagic:
		return "xfs"
	case nfsSuperMagic:
		return "nfs"
	case autofsSuperMagic:
		return "autofs"
	default:
		return fmt.Sprintf("magic=0x%x", st.Type)
	}
}

func parseProcMounts(target string) (MountInfo, error) {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return MountInfo{Target: target}, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	var last MountInfo
	found := false
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 4 {
			continue
		}
		if fields[1] != target {
			continue
		}
		info := MountInfo{
			Target:  target,
			Source:  fields[0],
			FSType:  fields[2],
			Options: fields[3],
		}
		for _, opt := range strings.Split(fields[3], ",") {
			k, v, ok := strings.Cut(opt, "=")
			if !ok || k != "addr" {
				continue
			}
			info.ServerAddr = v
			info.Tailscale = strings.HasPrefix(v, "100.")
		}
		last = info
		found = true
	}
	if !found {
		return MountInfo{Target: target, FSType: findmntFSType(target)}, fmt.Errorf("not in /proc/mounts")
	}
	total, avail, err := destSize(target)
	if err == nil {
		last.SizeMiB = mib(total)
		last.AvailMiB = mib(avail)
	}
	return last, nil
}

func readNFSSnap(mountpoint string) NFSSnap {
	f, err := os.Open("/proc/self/mountstats")
	if err != nil {
		return NFSSnap{}
	}
	defer f.Close()
	want := " mounted on " + mountpoint + " with fstype nfs"
	sc := bufio.NewScanner(f)
	in := false
	var snap NFSSnap
	for sc.Scan() {
		line := sc.Text()
		if strings.HasPrefix(line, "device ") {
			if in {
				break
			}
			in = strings.Contains(line, want)
			continue
		}
		if !in {
			continue
		}
		line = strings.TrimSpace(line)
		switch {
		case strings.HasPrefix(line, "bytes:"):
			nums := uintFields(strings.TrimSpace(strings.TrimPrefix(line, "bytes:")))
			if len(nums) >= 6 {
				snap.NormalRead = nums[0]
				snap.NormalWrite = nums[1]
				snap.ServerRead = nums[4]
				snap.ServerWrite = nums[5]
				snap.Found = true
			}
		case strings.HasPrefix(line, "xprt:"):
			nums := uintFields(line)
			// xprt: proto port bind connect connect_idle idle sends recvs bad_xids ...
			if len(nums) >= 7 {
				snap.Sends = nums[5]
				snap.Recvs = nums[6]
			}
			if len(nums) >= 8 {
				snap.BadXIDs = nums[7]
			}
		case strings.HasPrefix(line, "WRITE:"):
			nums := uintFields(line)
			if len(nums) >= 1 {
				snap.WriteOps = nums[0]
			}
		case strings.HasPrefix(line, "COMMIT:"):
			nums := uintFields(line)
			if len(nums) >= 1 {
				snap.CommitOps = nums[0]
			}
		case strings.HasPrefix(line, "READ_PLUS:"):
			nums := uintFields(line)
			if len(nums) >= 1 {
				snap.ReadPlusOps = nums[0]
			}
		}
	}
	return snap
}

func uintFields(s string) []uint64 {
	var out []uint64
	for _, f := range strings.Fields(s) {
		n, err := strconv.ParseUint(f, 10, 64)
		if err != nil {
			continue
		}
		out = append(out, n)
	}
	return out
}

func nfsDelta(a, b NFSSnap) NFSSnap {
	return NFSSnap{
		NormalRead:  b.NormalRead - a.NormalRead,
		NormalWrite: b.NormalWrite - a.NormalWrite,
		ServerRead:  b.ServerRead - a.ServerRead,
		ServerWrite: b.ServerWrite - a.ServerWrite,
		WriteOps:    b.WriteOps - a.WriteOps,
		CommitOps:   b.CommitOps - a.CommitOps,
		ReadPlusOps: b.ReadPlusOps - a.ReadPlusOps,
		Sends:       b.Sends - a.Sends,
		Recvs:       b.Recvs - a.Recvs,
		BadXIDs:     b.BadXIDs - a.BadXIDs,
		Found:       a.Found && b.Found,
	}
}
