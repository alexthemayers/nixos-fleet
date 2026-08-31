{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    intel-gpu-tools
    nvtopPackages.intel
    libva-utils
  ];

  security.rtkit.enable = true;

  boot.kernelParams = [
    "snd-hda-intel.dmic_detect=0"
    "module_blacklist=i915"
    "xe.force_probe=7d67"
  ];

  networking.hostName = "proxmox-applications-1";
}
