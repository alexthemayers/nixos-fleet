package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

type WriteProbe struct {
	User  string `json:"user"`
	Path  string `json:"path"`
	OK    bool   `json:"ok"`
	Owner string `json:"owner,omitempty"`
	Error string `json:"error,omitempty"`
}

type SystemdUnit struct {
	Name           string `json:"name"`
	LoadState      string `json:"load_state,omitempty"`
	ActiveState    string `json:"active_state,omitempty"`
	IdleTimeout    string `json:"idle_timeout,omitempty"`
	What           string `json:"what,omitempty"`
	RequiresMounts string `json:"requires_mounts_for,omitempty"`
	Error          string `json:"error,omitempty"`
}

type ProbeReport struct {
	CachePathXML   string        `json:"cache_path_xml,omitempty"`
	CacheMount     MountInfo     `json:"cache_mount"`
	TrueNAS        DNSLookup     `json:"truenas_scale"`
	JellyfinActive string        `json:"jellyfin_active,omitempty"`
	JellyfinHTTP   HTTPPath      `json:"jellyfin_http"`
	Writes         []WriteProbe  `json:"writes"`
	Units          []SystemdUnit `json:"units"`
	Notes          []string      `json:"notes"`
}

var cachePathRE = regexp.MustCompile(`<CachePath>([^<]*)</CachePath>`)

func readCachePathXML(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	m := cachePathRE.FindSubmatch(b)
	if len(m) < 2 {
		return ""
	}
	return string(m[1])
}

func systemctlShow(unit string, props ...string) (map[string]string, error) {
	args := append([]string{"show", unit, "--no-pager"}, "--property="+strings.Join(props, ","))
	out, err := exec.Command("systemctl", args...).CombinedOutput()
	res := map[string]string{}
	for _, line := range strings.Split(string(out), "\n") {
		k, v, ok := strings.Cut(line, "=")
		if ok {
			res[k] = v
		}
	}
	if err != nil {
		return res, fmt.Errorf("%s: %s", err, strings.TrimSpace(string(out)))
	}
	return res, nil
}

func probeWriteInfo(dir, user string) WriteProbe {
	p := filepath.Join(dir, ".io-bench-write-"+user)
	_ = os.Remove(p)
	out := WriteProbe{User: user, Path: p}
	var cmd *exec.Cmd
	if user == "root" || user == "" {
		cmd = exec.Command("sh", "-c", "echo ok > \"$1\" && stat -c 'uid=%u gid=%g' \"$1\"", "sh", p)
	} else {
		cmd = exec.Command("runuser", "-u", user, "--", "sh", "-c", "echo ok > \"$1\" && stat -c 'uid=%u gid=%g' \"$1\"", "sh", p)
	}
	b, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(b))
	_ = os.Remove(p)
	if err != nil {
		out.Error = text
		if out.Error == "" {
			out.Error = err.Error()
		}
		return out
	}
	out.OK = true
	out.Owner = text
	return out
}

func runProbe(ctx context.Context, cacheDir, healthURL, xmlPath string) ProbeReport {
	rep := ProbeReport{}
	rep.CachePathXML = readCachePathXML(xmlPath)
	mnt, err := parseProcMounts(cacheDir)
	rep.CacheMount = mnt
	if err != nil {
		rep.Notes = append(rep.Notes, "cache mount: "+err.Error()+"; fstype="+mnt.FSType)
	}

	rep.TrueNAS = lookupSystem(ctx, "truenas-scale")
	for _, a := range rep.TrueNAS.Addrs {
		if strings.HasPrefix(a, "100.") {
			rep.Notes = append(rep.Notes,
				"truenas-scale resolves to Tailscale "+a+" (NFSv4 follows MagicDNS; this is not the LAN SSD path).")
			break
		}
	}

	if mnt.Tailscale {
		rep.Notes = append(rep.Notes,
			"NFS clientaddr/addr is Tailscale. Guest iowait on this mount includes userspace tailscaled and MTU 1280, not just ZFS SSD latency.")
	}

	if mnt.FSType == "ext4" || mnt.FSType == "xfs" {
		rep.Notes = append(rep.Notes,
			"cache path is the VM disk stub, not NFS. Mount truenas-scale:/mnt/ssd/jellyfin/cache before measuring the original architecture.")
	}

	if b, err := exec.Command("systemctl", "is-active", "jellyfin").CombinedOutput(); err == nil || len(b) > 0 {
		rep.JellyfinActive = strings.TrimSpace(string(b))
	}
	rep.JellyfinHTTP = fetchHTTPS(ctx, healthURL)

	rep.Writes = []WriteProbe{
		probeWriteInfo(cacheDir, "root"),
		probeWriteInfo(cacheDir, "jellyfin"),
	}
	for _, w := range rep.Writes {
		if w.User == "jellyfin" && !w.OK {
			rep.Notes = append(rep.Notes,
				"jellyfin uid cannot write the NFS cache (leftover uid 3000 from the old containers user). BindPaths would not make transcodes work until the dataset is chowned.")
		}
	}

	for _, u := range []string{
		"mnt-nfs-jellyfin-cache.mount",
		"mnt-nfs-jellyfin-cache.automount",
		"jellyfin.service",
	} {
		props, err := systemctlShow(u, "LoadState", "ActiveState", "TimeoutIdleUSec", "What", "RequiresMountsFor", "FragmentPath")
		su := SystemdUnit{Name: u}
		if err != nil {
			su.Error = err.Error()
			su.LoadState = props["LoadState"]
		} else {
			su.LoadState = props["LoadState"]
			su.ActiveState = props["ActiveState"]
			su.IdleTimeout = props["TimeoutIdleUSec"]
			su.What = props["What"]
			su.RequiresMounts = props["RequiresMountsFor"]
		}
		rep.Units = append(rep.Units, su)
		if u == "mnt-nfs-jellyfin-cache.automount" && props["LoadState"] == "not-found" {
			rep.Notes = append(rep.Notes,
				"systemd automount for the cache is not in the running generation (ad-hoc mount only). Next deploy of apps-1 installs it.")
		}
		if u == "mnt-nfs-jellyfin-cache.automount" && props["LoadState"] == "loaded" &&
			props["TimeoutIdleUSec"] != "" && props["TimeoutIdleUSec"] != "infinity" && props["TimeoutIdleUSec"] != "0" {
			rep.Notes = append(rep.Notes,
				"cache automount idle-timeout="+props["TimeoutIdleUSec"]+". A quiet cache unmounts; the next transcode remounts. RequiresMountsFor means a remount failure takes Jellyfin down.")
		}
	}

	if rep.CachePathXML != "" && rep.CachePathXML != "/var/cache/jellyfin" && rep.CachePathXML != cacheDir {
		rep.Notes = append(rep.Notes,
			"system.xml CachePath="+rep.CachePathXML+" does not match the bind dest /var/cache/jellyfin. Jellyfin will ignore --cachedir and may fail to start.")
	}
	if mnt.FSType == "nfs" && mnt.AvailMiB > 0 {
		rep.Notes = append(rep.Notes,
			fmt.Sprintf("SSD cache dataset has %.0f MiB free (not the 6.5 GiB VM root).", mnt.AvailMiB))
	}
	return rep
}
