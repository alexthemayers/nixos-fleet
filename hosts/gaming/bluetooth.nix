{ pkgs, lib, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
        Enable = "Source,Sink,Media,Socket";
        # Required for seamless Xbox controller connection and reconnection
        FastConnectable = true;
        Privacy = "device";
      };
    };
  };

  # Advanced Linux Bluetooth driver for Xbox One Wireless Controllers
  hardware.xpadneo.enable = true;
}
