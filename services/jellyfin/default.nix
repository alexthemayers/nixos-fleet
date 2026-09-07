{
  config,
  pkgs,
  lib,
  ...
}:
let
  nfsBase = import ../../config/nfs-mount.nix "jellyfin" [ ];
  # Media is read-heavy; large r/w sizes and async keep sequential reads off the NAS fast.
  nfsMediaOpts = nfsBase ++ [
    "rsize=1048576"
    "wsize=1048576"
    "async"
    "noatime"
  ];
  # Config/metadata share this dataset — avoid async so library DB writes are not buffered unsafely.
  nfsConfigOpts = nfsBase ++ [
    "rsize=1048576"
    "wsize=1048576"
    "noatime"
  ];
  # Transcode/HLS cache: original architecture, same opts as media (async, 1 MiB r/w).
  nfsCacheOpts = nfsMediaOpts;

  runtimeRoot = "/run/jellyfin/live";
  runtimeOf = dest: runtimeRoot + lib.removePrefix "/var/lib/jellyfin" dest;

  # Overlay NFS state with files from this repo. Destinations are inside the
  # BindPaths sandbox (/var/lib/jellyfin is the config NFS share). Copied to
  # /run then bound read-write: Jellyfin rewrites encoding.xml on start
  # (EncoderAppPathDisplay) and dies if that path is a read-only store file.
  managedFiles = [
    {
      src = ./config/system.xml;
      dest = "/var/lib/jellyfin/config/system.xml";
    }
    {
      src = ./config/encoding.xml;
      dest = "/var/lib/jellyfin/config/encoding.xml";
    }
    {
      src = ./config/branding.xml;
      dest = "/var/lib/jellyfin/config/branding.xml";
    }
    {
      src = ./config/database.xml;
      dest = "/var/lib/jellyfin/config/database.xml";
    }
    {
      src = ./config/xbmcmetadata.xml;
      dest = "/var/lib/jellyfin/config/xbmcmetadata.xml";
    }
    {
      src = ./config/logging.json;
      dest = "/var/lib/jellyfin/config/logging.json";
    }
    {
      src = ./plugins/Jellyfin.Plugin.AniDB.xml;
      dest = "/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.AniDB.xml";
    }
    {
      src = ./plugins/Jellyfin.Plugin.MusicBrainz.xml;
      dest = "/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.MusicBrainz.xml";
    }
    {
      src = ./plugins/Jellyfin.Plugin.Omdb.xml;
      dest = "/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.Omdb.xml";
    }
    {
      src = ./plugins/Jellyfin.Plugin.StudioImages.xml;
      dest = "/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.StudioImages.xml";
    }
    {
      src = ./plugins/Jellyfin.Plugin.Tmdb.xml;
      dest = "/var/lib/jellyfin/plugins/configurations/Jellyfin.Plugin.Tmdb.xml";
    }
    {
      src = ./libraries/Anime/options.xml;
      dest = "/var/lib/jellyfin/root/default/Anime/options.xml";
    }
    {
      src = ./libraries/Anime/anime.mblink;
      dest = "/var/lib/jellyfin/root/default/Anime/anime.mblink";
    }
    {
      src = ./libraries/Movies/options.xml;
      dest = "/var/lib/jellyfin/root/default/Movies/options.xml";
    }
    {
      src = ./libraries/Movies/movies.mblink;
      dest = "/var/lib/jellyfin/root/default/Movies/movies.mblink";
    }
    {
      src = ./libraries/Documentaries/options.xml;
      dest = "/var/lib/jellyfin/root/default/Documentaries/options.xml";
    }
    {
      src = ./libraries/Documentaries/documentaries.mblink;
      dest = "/var/lib/jellyfin/root/default/Documentaries/documentaries.mblink";
    }
    {
      src = ./libraries/Music/options.xml;
      dest = "/var/lib/jellyfin/root/default/Music/options.xml";
    }
    {
      src = ./libraries/Music/music.mblink;
      dest = "/var/lib/jellyfin/root/default/Music/music.mblink";
    }
    {
      src = ./libraries/Shows/options.xml;
      dest = "/var/lib/jellyfin/root/default/Shows/options.xml";
    }
    {
      src = ./libraries/Shows/series.mblink;
      dest = "/var/lib/jellyfin/root/default/Shows/series.mblink";
    }
  ];

  networkDest = "/var/lib/jellyfin/config/network.xml";
  ssoDest = "/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml";

  copyManaged = lib.concatMapStringsSep "\n" (f: ''
    mkdir -p "$(dirname ${runtimeOf f.dest})"
    cp ${f.src} ${runtimeOf f.dest}
  '') managedFiles;

  renderScript = pkgs.writeShellScript "jellyfin-render-config" ''
    set -euo pipefail
    resolve_v4() {
      ${pkgs.getent}/bin/getent ahostsv4 "$1" \
        | ${pkgs.gawk}/bin/awk '{print $1; exit}'
    }
    caddy=$(resolve_v4 xcloud-caddy)
    if [ -z "$caddy" ]; then
      echo "jellyfin-render-config: failed to resolve xcloud-caddy ($caddy)" >&2
      exit 1
    fi
    umask 022
    rm -rf ${runtimeRoot}
    mkdir -p ${runtimeRoot}
    ${copyManaged}
    mkdir -p "$(dirname ${runtimeOf networkDest})" "$(dirname ${runtimeOf ssoDest})"
    ${pkgs.gnused}/bin/sed \
      -e "s/__PROXY_XCLOUD_CADDY__/$caddy/" \
      ${./config/network.xml} > ${runtimeOf networkDest}
    cp ${config.sops.templates."jellyfin-sso-auth.xml".path} ${runtimeOf ssoDest}
    chown -R jellyfin:jellyfin ${runtimeRoot}
    find ${runtimeRoot} -type f -exec chmod 0644 {} +
    chmod 0440 ${runtimeOf ssoDest}
  '';

  overlayBinds = map (f: "${runtimeOf f.dest}:${f.dest}") managedFiles ++ [
    "${runtimeOf networkDest}:${networkDest}"
    "${runtimeOf ssoDest}:${ssoDest}"
  ];
in
{
  fileSystems."/mnt/nfs/media" = {
    device = "truenas-scale:/mnt/hdd/media";
    fsType = "nfs";
    options = nfsMediaOpts;
  };

  fileSystems."/mnt/nfs/jellyfin/config" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/config";
    fsType = "nfs";
    options = nfsConfigOpts;
  };

  fileSystems."/mnt/nfs/jellyfin/cache" = {
    device = "truenas-scale:/mnt/ssd/jellyfin/cache";
    fsType = "nfs";
    options = nfsCacheOpts;
  };

  services.jellyfin = {
    enable = true;
    # openFirewall also opens the DLNA/auto-discovery ports on every interface.
    # Clients reach Jellyfin through Caddy over the tailnet on 8096.
    openFirewall = false;
    # Default cacheDir is /var/cache/jellyfin; BindPaths maps the SSD NFS dataset there.
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    8096 # Jellyfin (edge Caddy reverse_proxy)
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-compute-runtime
      vpl-gpu-rt
    ];
  };
  fleet.waitForHost.jellyfin.host = "truenas-scale";
  # Render resolves xcloud-caddy over MagicDNS. After a
  # hypervisor reboot tailscaled is up before that name answers, getent
  # exits 2, and jellyfin.service stays down (ServiceDown + EndpointDown).
  fleet.waitForHost.jellyfin-render-caddy = {
    host = "xcloud-caddy";
    forServices = [ "jellyfin-render-config.service" ];
  };

  sops.secrets."jellyfin/sso_oid_secret" = {
    owner = "jellyfin";
    group = "jellyfin";
    restartUnits = [ "jellyfin.service" ];
  };

  sops.templates."jellyfin-sso-auth.xml" = {
    owner = "jellyfin";
    group = "jellyfin";
    mode = "0440";
    restartUnits = [ "jellyfin.service" ];
    content =
      builtins.replaceStrings
        [ "@OID_SECRET@" ]
        [
          config.sops.placeholder."jellyfin/sso_oid_secret"
        ]
        (builtins.readFile ./plugins/SSO-Auth.xml);
  };

  systemd.services.jellyfin-render-config = {
    description = "Render declarative Jellyfin config into /run/jellyfin/live";
    after = [
      "tailscaled.service"
      "network-online.target"
    ];
    wants = [
      "tailscaled.service"
      "network-online.target"
    ];
    before = [ "jellyfin.service" ];
    requiredBy = [ "jellyfin.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = renderScript;
    };
  };

  systemd.services.jellyfin = {
    after = [ "jellyfin-render-config.service" ];
    requires = [ "jellyfin-render-config.service" ];
    unitConfig.RequiresMountsFor = [
      "/mnt/nfs/media"
      "/mnt/nfs/jellyfin/config"
      "/mnt/nfs/jellyfin/cache"
    ];

    serviceConfig = {
      BindPaths = [
        "/mnt/nfs/jellyfin/config:/var/lib/jellyfin"
        "/mnt/nfs/jellyfin/cache:/var/cache/jellyfin"
        "/mnt/nfs/media:/media"
      ]
      ++ overlayBinds;
      SupplementaryGroups = [
        "render"
        "video"
      ];
      TimeoutStopSec = "15s";
      Restart = "on-failure";
      RestartSec = "10s";
    };

    environment = {
      JELLYFIN_PublishedServerUrl = "https://jellyfin.alexmayers.co.za";
    };
  };
}
