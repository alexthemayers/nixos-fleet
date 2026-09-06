{ config, pkgs, ... }: {
  sops.secrets."oauth2-proxy/blackbox_token" = { };

  sops.templates."blackbox.yml" = {
    restartUnits = [ "prometheus-blackbox-exporter.service" ];
    content = ''
      modules:
        http_2xx:
          prober: http
          timeout: 5s
          http:
            valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
            valid_status_codes: []  # Automatically accepts any 2xx code
            method: GET
            headers:
              X-Blackbox-Token: "${config.sops.placeholder."oauth2-proxy/blackbox_token"}"
    '';
    owner = "root";
    group = "keys";
    mode = "0440";
  };

  systemd.services.prometheus-blackbox-exporter.serviceConfig.SupplementaryGroups = [ "keys" ];

  services.prometheus.exporters.blackbox = {
    enable = true;
    configFile = config.sops.templates."blackbox.yml".path;
    enableConfigCheck = false;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    9115 # blackbox exporter (Prometheus scrape; proxmox-observability-1)
  ];
}
