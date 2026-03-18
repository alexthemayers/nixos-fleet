# Auto-generated using compose2nix v0.3.3-pre.
{ pkgs, lib, config, ... }:

{
  # Runtime
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
  };

  # Enable container name DNS for all Podman networks.
  networking.firewall.interfaces = let
    matchAll = if !config.networking.nftables.enable then "podman+" else "podman*";
  in {
    "${matchAll}".allowedUDPPorts = [ 53 ];
  };

  virtualisation.oci-containers.backend = "podman";

  # Containers
  virtualisation.oci-containers.containers."app-jellyfin" = {
    image = "jellyfin/jellyfin";
    environment = {
      "JELLYFIN_PublishedServerUrl" = "https://jellyfin.alexmayers.co.za";
    };
    volumes = [
      "/mnt/code/docker-compose/jellyfin/logging.json:/config/_data/config/logging.json:rw"
      "jellyfin_jellyfin-cache:/cache:rw"
      "jellyfin_jellyfin-config:/config:rw"
      "jellyfin_media:/media:rw,Z"
    ];
    dependsOn = [
      "jellyfin"
    ];
    user = "root:303";
    log-driver = "journald";
    extraOptions = [
      "--device=/dev/dri:/dev/dri:rwm"
      "--network=container:jellyfin"
    ];
  };
  systemd.services."podman-app-jellyfin" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-volume-jellyfin_jellyfin-cache.service"
      "podman-volume-jellyfin_jellyfin-config.service"
      "podman-volume-jellyfin_media.service"
    ];
    requires = [
      "podman-volume-jellyfin_jellyfin-cache.service"
      "podman-volume-jellyfin_jellyfin-config.service"
      "podman-volume-jellyfin_media.service"
    ];
    partOf = [
      "podman-compose-jellyfin-root.target"
    ];
    wantedBy = [
      "podman-compose-jellyfin-root.target"
    ];
  };
  virtualisation.oci-containers.containers."jellyfin" = {
    image = "tailscale/tailscale:latest";
    environment = {
      "TS_AUTHKEY" = "tskey-client-kJ3Uj8bGGK11CNTRL-BCUoC9DtMkZziHALzA6akZ6WnTYNMkir";
      "TS_ENABLE_HEALTH_CHECK" = "true";
      "TS_EXTRA_ARGS" = "--advertise-tags=tag:jellyfin";
      "TS_LOCAL_ADDR_PORT" = "127.0.0.1:41234";
      "TS_SERVE_CONFIG" = "/config/jellyfin.json";
      "TS_STATE_DIR" = "/var/lib/tailscale";
    };
    volumes = [
      "/dev/net/tun:/dev/net/tun:rw"
      "/mnt/code/docker-compose/jellyfin/config:/config:rw"
      "/mnt/code/docker-compose/jellyfin/ts-jellyfin/state:/var/lib/tailscale:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=net_admin"
      "--cap-add=sys_module"
      "--health-cmd=[\"wget\", \"--spider\", \"-q\", \"http://127.0.0.1:41234/healthz\"]"
      "--health-interval=1m0s"
      "--health-retries=3"
      "--health-start-period=10s"
      "--health-timeout=10s"
      "--hostname=jellyfin"
      "--network-alias=tailscale"
      "--network=jellyfin_default"
    ];
  };
  systemd.services."podman-jellyfin" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-jellyfin_default.service"
    ];
    requires = [
      "podman-network-jellyfin_default.service"
    ];
    partOf = [
      "podman-compose-jellyfin-root.target"
    ];
    wantedBy = [
      "podman-compose-jellyfin-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-jellyfin_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f jellyfin_default";
    };
    script = ''
      podman network inspect jellyfin_default || podman network create jellyfin_default
    '';
    partOf = [ "podman-compose-jellyfin-root.target" ];
    wantedBy = [ "podman-compose-jellyfin-root.target" ];
  };

  # Volumes
  systemd.services."podman-volume-jellyfin_jellyfin-cache" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect jellyfin_jellyfin-cache || podman volume create jellyfin_jellyfin-cache --opt=device=:/mnt/ssd/jellyfin/cache --opt=o=addr=truenas-scale.bee-phrygian.ts.net,rw,nfsvers=4.1 --opt=type=nfs
    '';
    partOf = [ "podman-compose-jellyfin-root.target" ];
    wantedBy = [ "podman-compose-jellyfin-root.target" ];
  };
  systemd.services."podman-volume-jellyfin_jellyfin-config" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect jellyfin_jellyfin-config || podman volume create jellyfin_jellyfin-config --opt=device=:/mnt/ssd/jellyfin/config --opt=o=addr=truenas-scale.bee-phrygian.ts.net,rw,nfsvers=4.1 --opt=type=nfs
    '';
    partOf = [ "podman-compose-jellyfin-root.target" ];
    wantedBy = [ "podman-compose-jellyfin-root.target" ];
  };
  systemd.services."podman-volume-jellyfin_media" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect jellyfin_media || podman volume create jellyfin_media --opt=device=:/mnt/hdd/media --opt=o=addr=truenas-scale.bee-phrygian.ts.net,rw,nfsvers=4.1 --opt=type=nfs
    '';
    partOf = [ "podman-compose-jellyfin-root.target" ];
    wantedBy = [ "podman-compose-jellyfin-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-jellyfin-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
