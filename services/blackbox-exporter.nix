{ config, pkgs, ... }: {
  services.prometheus.exporters.blackbox = {
    enable = true;
    port = 9115;

    configFile = pkgs.writeText "blackbox.yml" ''
      modules:
        http_2xx:
          prober: http
          timeout: 5s
          http:
            valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
            valid_status_codes: []  # Automatically accepts any 2xx code
            method: GET
            
        icmp:
          prober: icmp
          timeout: 5s
    '';
  };
}
