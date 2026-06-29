# Prometheus Blackbox Exporter Service Configuration

This document describes the deployment and configuration details of the **Prometheus Blackbox Exporter** service in the
`nixos-fleet` infrastructure.

## Overview

The Prometheus Blackbox Exporter probes network endpoints over HTTP, HTTPS, DNS, TCP, and ICMP. In this fleet, it is
deployed on the **`rpi4`** node.

## Networking and Ports

- **Internal Port**: `9115` (TCP)
- **Scraping Target**: Scraped by the central Prometheus instance on `proxmox-observability:9090` via endpoint
  `rpi4:9115/probe`.

## Secrets Management

- **`oauth2-proxy/blackbox_token`**: A token shared with the Caddy reverse proxy to bypass SSO protection. It is
  retrieved from SOPS and written to the configuration template `blackbox.yml`.

## Configurations

- **Bypass Token Injection**: To allow monitoring of endpoints protected by Keycloak/`oauth2-proxy`, the Blackbox
  Exporter injects the `X-Blackbox-Token` header into HTTPS requests:
  ```yaml
  headers:
    X-Blackbox-Token: "<SOPS_DECRYPTED_TOKEN>"
  ```
  Caddy reads this header and permits scraping without redirection to the SSO login page.
- **Probe Modules**:
    - `http_2xx`: Probes websites using GET requests over HTTP/1.1 and HTTP/2.0, accepting any 2xx response status code.
    - `icmp`: Probes hosts using standard ping requests for network latency monitoring.
- **Permissions**: Systemd config adds `keys` as a supplementary group to the `prometheus-blackbox-exporter` service to
  allow reading the decrypted SOPS file.
