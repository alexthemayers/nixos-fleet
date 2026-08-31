{ ... }:
{
  # Allow arm64 emulation for execution of build steps that require arm64 instructions
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking.hostName = "proxmox-applications-2";
}
