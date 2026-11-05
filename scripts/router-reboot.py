#!/usr/bin/env python3
"""Reboot the LAN router (Huawei WS7100-20 / HiLink) from proxmox-dev.

Runs on proxmox-dev (the router is only reachable from the LAN). Use
`make router-status` / `make reboot-router`; see docs/runbooks/router-reboot.md.

  status   log in, print router uptime and Tailscale paths, log out
  reboot   status + reboot, wait for the router, print Tailscale paths again

The password is read with sops from secrets/router/secrets.yaml (or stdin with
--password-stdin) and is never printed or written to disk. One login attempt
per run: the router locks the account after three failures, so this script
never retries a rejected proof.
"""

import argparse
import concurrent.futures
import datetime
import hashlib
import hmac
import http.client
import json
import os
import re
import secrets
import shutil
import ssl
import subprocess
import sys
import time

ROUTER = os.environ.get("ROUTER_HOST", "192.168.3.1")
# Self-signed cert (CN mediarouter.home, valid to 2044). Pin it so a LAN
# impostor cannot collect the SCRAM proof.
CERT_SHA256 = os.environ.get(
    "ROUTER_CERT_SHA256",
    "1F:A3:36:00:11:FF:1B:FD:CE:DA:9A:AC:95:3D:2B:22:28:43:99:8C:53:AA:7C:26:76:A4:44:6B:1D:C9:48:86",
).replace(":", "").upper()
SOPS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "secrets.yaml")
SOPS_SSH_KEY = "/etc/ssh/ssh_host_ed25519_key"
# Nightly work: 02:00 Postgres backup, 03:00 GitLab backup, 03:30 upgrades,
# 04:00-05:00 guest reboot slots (docs/runbooks/updates.md).
QUIET_START = datetime.time(1, 30)
QUIET_END = datetime.time(5, 30)
REBOOT_DOWN_WAIT = 90
REBOOT_UP_WAIT = 420


class RouterError(Exception):
    pass


def log(msg):
    print(msg, flush=True)


# --- HTTPS client with a pinned certificate -------------------------------


class Router:
    def __init__(self):
        self.cookies = {}
        self.csrf = None
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        self.ctx = ctx

    def request(self, method, path, body=None, timeout=20):
        conn = http.client.HTTPSConnection(ROUTER, 443, timeout=timeout, context=self.ctx)
        try:
            conn.connect()
            der = conn.sock.getpeercert(binary_form=True)
            if hashlib.sha256(der).hexdigest().upper() != CERT_SHA256:
                raise RouterError("router certificate does not match the pinned fingerprint")
            headers = {"_ResponseFormat": "JSON"}
            data = None
            if body is not None:
                data = json.dumps(body).encode()
                headers["Content-Type"] = "application/json; charset=utf-8"
            if self.cookies:
                headers["Cookie"] = "; ".join(f"{k}={v}" for k, v in self.cookies.items())
            conn.request(method, path, body=data, headers=headers)
            resp = conn.getresponse()
            raw = resp.read()
            for hdr, val in resp.getheaders():
                if hdr.lower() == "set-cookie":
                    name, _, rest = val.partition("=")
                    self.cookies[name.strip()] = rest.split(";", 1)[0]
            return resp.status, raw
        finally:
            conn.close()

    def refresh_csrf_from_page(self):
        status, raw = self.request("GET", "/html/index.html")
        text = raw.decode("utf-8", "replace")
        param = re.search(r'name="csrf_param"\s+content="([^"]+)"', text)
        token = re.search(r'name="csrf_token"\s+content="([^"]+)"', text)
        if status != 200 or not param or not token:
            raise RouterError(f"cannot read CSRF token from /html/index.html (HTTP {status})")
        self.csrf = {"csrf_param": param.group(1), "csrf_token": token.group(1)}

    def post(self, path, data=None):
        body = {"csrf": self.csrf}
        if data is not None:
            body["data"] = data
        status, raw = self.request("POST", path, body)
        try:
            res = json.loads(raw.decode("utf-8", "replace"))
        except ValueError:
            res = {}
        if isinstance(res, dict) and res.get("csrf_param"):
            self.csrf = {"csrf_param": res["csrf_param"], "csrf_token": res["csrf_token"]}
        return status, res

    def deviceinfo(self):
        status, raw = self.request("GET", "/api/system/deviceinfo", timeout=5)
        if status != 200:
            raise RouterError(f"deviceinfo HTTP {status}")
        return json.loads(raw.decode("utf-8", "replace"))


# --- SCRAM login (mirrors /vuex/store.js; CryptoJS HMAC arguments are
# (message, key), so the key is the label/auth message, not the secret) -----


def _hm(key, msg):
    return hmac.new(key, msg, hashlib.sha256).digest()


def scram_proof(password, salt_hex, iterations, first_nonce, final_nonce):
    salt = bytes.fromhex(salt_hex)
    auth = f"{first_nonce},{final_nonce},{final_nonce}".encode()
    salted = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, iterations, 32)
    client_key = _hm(b"Client Key", salted)
    server_key = _hm(b"Server Key", salted)
    stored = hashlib.sha256(client_key).digest()
    sig = _hm(auth, stored)
    proof = bytes(a ^ b for a, b in zip(client_key, sig)).hex()
    return proof, _hm(auth, server_key).hex(), server_key


def login(router, username, password):
    router.refresh_csrf_from_page()
    first_nonce = secrets.token_hex(32)
    res = {}
    for _ in range(3):
        _, res = router.post(
            "/api/system/user_login_nonce",
            {"username": username, "firstnonce": first_nonce},
        )
        if res.get("err") == 0:
            break
        time.sleep(1)
    if res.get("err") != 0:
        raise RouterError(f"user_login_nonce rejected: err={res.get('err')} errcode={res.get('errcode')}")
    proof, server_sig, server_key = scram_proof(
        password, res["salt"], int(res["iterations"]), first_nonce, res["servernonce"]
    )
    # One attempt only: a wrong proof counts toward the three-strike lockout.
    _, res = router.post(
        "/api/system/user_login_proof",
        {"clientproof": proof, "finalnonce": res["servernonce"]},
    )
    if res.get("err") != 0:
        raise RouterError(
            "login rejected: err=%s count=%s waitTime=%s. Not retrying."
            % (res.get("err"), res.get("count"), res.get("waitTime"))
        )
    if res.get("serversignature") != server_sig:
        raise RouterError("router server signature mismatch; refusing to continue")
    pub_sig = _hm(server_key, bytes.fromhex(res["rsan"])).hex()
    if res.get("rsapubkeysignature") != pub_sig:
        raise RouterError("router public-key signature mismatch; refusing to continue")


def logout(router):
    try:
        router.post("/api/system/user_logout")
    except Exception:  # noqa: BLE001 - best effort, the session expires anyway
        pass


# --- secrets ---------------------------------------------------------------


def read_credentials(args):
    if args.password_stdin:
        return args.username, sys.stdin.read().rstrip("\n")
    # Transient systemd units do not have the Nix profile on PATH.
    path = os.environ.get("PATH", "") + ":/nix/var/nix/profiles/default/bin"
    sops_bin = shutil.which("sops", path=path)
    nix_bin = shutil.which("nix", path=path)
    if sops_bin:
        sops = [sops_bin]
    elif nix_bin:
        sops = [nix_bin, "--extra-experimental-features", "nix-command flakes",
                "shell", "nixpkgs#sops", "--command", "sops"]
    else:
        raise RouterError("neither sops nor nix is installed")
    env = dict(os.environ)
    if os.path.exists(SOPS_SSH_KEY):
        env.setdefault("SOPS_AGE_SSH_PRIVATE_KEY_FILE", SOPS_SSH_KEY)

    def extract(key):
        out = subprocess.run(
            sops + ["-d", "--extract", f'["{key}"]', args.sops_file],
            capture_output=True, env=env, check=False,
        )
        if out.returncode != 0:
            raise RouterError(f"sops could not read {key} from {args.sops_file}")
        return out.stdout.decode()

    return extract("router_username"), extract("router_password")


# --- Tailscale paths -------------------------------------------------------


def tailscale_peers():
    out = subprocess.run(["tailscale", "status", "--json"], capture_output=True, text=True, check=False)
    if out.returncode != 0:
        return []
    status = json.loads(out.stdout)
    return sorted(
        p["HostName"] for p in status.get("Peer", {}).values()
        if p.get("Online") and not p.get("ExitNode")
    )


def ping_peer(peer):
    out = subprocess.run(
        ["tailscale", "ping", "--c", "4", "--timeout", "4s", peer],
        capture_output=True, text=True, check=False,
    )
    last = None
    for line in out.stdout.splitlines():
        m = re.match(r"pong from \S+ \([^)]*\) via (\S+) in (\S+)", line)
        if m:
            last = m.groups()
    if not last:
        return peer, "no reply", False
    via, rtt = last
    direct = not via.startswith("DERP")
    return peer, f"{via} {rtt}", direct


def tailscale_paths(label):
    peers = tailscale_peers()
    log(f"Tailscale paths {label}:")
    if not peers:
        log("  (no online peers or tailscale unavailable)")
        return {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(ping_peer, peers))
    for peer, via, direct in results:
        log("  %-28s %-6s %s" % (peer, "direct" if direct else "RELAY", via))
    return {peer: direct for peer, _, direct in results}


# --- guards ----------------------------------------------------------------


def in_quiet_window(now):
    return QUIET_START <= now.time() <= QUIET_END


def wait_for_reboot(before_uptime):
    log("Waiting for the router to go down...")
    deadline = time.time() + REBOOT_DOWN_WAIT
    went_down = False
    while time.time() < deadline:
        try:
            Router().deviceinfo()
        except Exception:  # noqa: BLE001 - unreachable is the signal we want
            went_down = True
            break
        time.sleep(2)
    if not went_down:
        raise RouterError("router still answering after the reboot request; check by hand")
    started = time.time()
    log("Router is down. Waiting for it to return...")
    while time.time() - started < REBOOT_UP_WAIT:
        time.sleep(5)
        try:
            up = Router().deviceinfo().get("UpTime")
        except Exception:  # noqa: BLE001
            continue
        if isinstance(up, int) and up < before_uptime:
            log(f"Router is back after {int(time.time() - started)}s (uptime {up}s).")
            return
    raise RouterError(f"router did not return within {REBOOT_UP_WAIT}s")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["status", "reboot"])
    ap.add_argument("--force", action="store_true", help="reboot inside the 01:30-05:30 window")
    ap.add_argument("--dry-run", action="store_true", help="reboot: log in and check, but do not reboot")
    ap.add_argument("--sops-file", default=SOPS_FILE)
    ap.add_argument("--username", default="admin", help="only with --password-stdin")
    ap.add_argument("--password-stdin", action="store_true")
    args = ap.parse_args()

    now = datetime.datetime.now()
    if args.command == "reboot" and in_quiet_window(now) and not args.force and not args.dry_run:
        log(
            f"Refusing: it is {now:%H:%M} and 01:30-05:30 holds the backups, "
            "nightly upgrades and guest reboot slots. Use --force to override."
        )
        return 2

    try:
        info = Router().deviceinfo()
        before_uptime = int(info["UpTime"])
        log(f"Router {info.get('custinfo', {}).get('CustDeviceName', '?')} up {before_uptime // 3600}h "
            f"({before_uptime}s), serial {info.get('SerialNumber')}.")
        username, password = read_credentials(args)
        router = Router()
        login(router, username, password)
        del password
        log("Login OK.")
        tailscale_paths("before")
        if args.command == "status" or args.dry_run:
            logout(router)
            log("No reboot requested." if args.command == "status" else "Dry run: not rebooting.")
            return 0
        status, res = router.post("/api/service/reboot.cgi")
        if status != 200:
            raise RouterError(f"reboot request returned HTTP {status}")
        log(f"Reboot requested (response err={res.get('err', res.get('errcode'))}).")
        wait_for_reboot(before_uptime)
        log("Giving WAN and Tailscale 30s to settle...")
        time.sleep(30)
        after = {}
        for attempt in range(6):
            after = tailscale_paths(f"after (try {attempt + 1}/6)")
            if after and all(after.values()):
                break
            time.sleep(20)
        relayed = sorted(p for p, ok in after.items() if not ok)
        if relayed:
            log("Still relayed or unreachable: " + ", ".join(relayed))
            log("Next: systemctl restart tailscaled on the affected node (docs/runbooks/router-reboot.md).")
            return 1
        log("All online peers are direct.")
        return 0
    except (RouterError, OSError) as exc:
        log(f"ERROR: {exc}")
        return 1


if __name__ == "__main__":
    code = main()
    print(f"EXIT={code}", flush=True)
    sys.exit(code)
