{ config, ... }:
{
  # Set the default secrets file to the host-specific secrets file.
  # This guarantees that a host can only access its own secrets.
  sops.defaultSopsFile = ./../secrets + "/${config.networking.hostName}/secrets.yaml";
  sops.defaultSopsFormat = "yaml";
}
