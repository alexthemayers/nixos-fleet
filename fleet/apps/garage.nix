{
  # Garage is not running. The host name has to be in the inventory.
  # The zvol ssd/garage-iscsi is the remaining copy of the old blocks.
  host = "proxmox-observability-debian";
  port = 3902;
  docs = "docs/services/garage.md";
  dashboard = "fleet-garage.json";
  module = null;
}
