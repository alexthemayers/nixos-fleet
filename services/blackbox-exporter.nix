{ config, pkgs, ... }: {
  sops.secrets."oauth2-proxy/blackbox_token" = { };

  sops.templates."blackbox.yml" = {
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
            
        icmp:
          prober: icmp
          timeout: 5s
    '';
    owner = "prometheus-blackbox-exporter";
    group = "prometheus-blackbox-exporter";
  };

  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;
    configFile = config.sops.templates."blackbox.yml".path;
    enableConfigCheck = false;
  };
}
