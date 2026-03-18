{ config, lib, pkgs, ... }: {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Bootloader.
  boot.loader.grub.enable = true;
  boot.loader.grub.devices = [ "/dev/sda" ];

  security.rtkit.enable = true;
  system.autoUpgrade.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ 
    "snd-hda-intel.dmic_detect=0"
#    "module_blacklist=xe"
#    "i915.force_probe=!7d67"
#    "xe.force_probe=7d67"
  ];
  # boot.extraModulePackages = [ pkgs.i915-sriov ];

  # hardware graphics extra packages
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      vpl-gpu-rt
      libvdpau-va-gl
      intel-media-driver
      intel-compute-runtime
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [ intel-vaapi-driver ];
  };
  hardware.enableAllFirmware = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];


  networking.hostName = "nixos"; # Define your hostname.
  networking.nftables.enable = true;
  networking.nftables.tables.mangle = {
    family = "ip";
    content = ''
      chain output {
        type filter hook output priority mangle; policy accept;
        oifname "tailscale0" tcp flags syn tcp option maxseg size set 1232
      }
    '';
  };
  time.timeZone = "Africa/Johannesburg";
  i18n.defaultLocale = "en_GB.UTF-8";


  services = {
    tailscale.enable = true;

    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      banner = ''
      This box is owned by Alex Mayers a.mayers102@gmail.com
      '';
      ports = [ 22 ];
      settings = {
        PasswordAuthentication = true;
	PermitRootLogin = "yes";
        X11Forwarding = false;
      };
    };
  };

  users = {
    users.alex = {
      isNormalUser = true;
      description = "alex";
      extraGroups = [ "wheel" "docker" "render" ];
      shell = pkgs.zsh;
      packages = with pkgs; [
        speedtest-cli

        # utility
      ];
    };

    users.containers = {
      isSystemUser = true;
      group = "render";
      description = "container runner";
      extraGroups = [ "docker" "render" ];
      shell = pkgs.zsh;
      uid = 3000;
      # packages = with pkgs; [];
    };

    users.root = {
      shell = pkgs.zsh;
    };
  };


  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
  };

  environment.systemPackages = with pkgs; [
    neovim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
    pkgs.nixfmt-rfc-style
    gnumake
    tmux
    btop
    python3Full
    jq
    tree
    traceroute
    mtr
    inetutils
    intel-gpu-tools
  ];

  networking.firewall = {
    # enable the firewall
    enable = true;
  
    # always allow traffic from your Tailscale network
    trustedInterfaces = [ "tailscale0" ];
  
    # allow the Tailscale UDP port through the firewall
    allowedUDPPorts = [ config.services.tailscale.port ];
  
    # let you SSH in over the public internet
    allowedTCPPorts = [ 22 8096 ];
  };

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ll = "ls -l";
        update = "nix-channel --update";
        upgrade = "nixos-rebuild switch --upgrade --flake /etc/nixos/";
      };
      ohMyZsh = {
        enable = true;
        plugins = [ "git" "docker" "kubectl" "nmap" "ruby" "rust" "systemd" ];
        theme = "robbyrussell";
      };
      shellInit = ''
        bindkey -v
      '';
    };


    neovim = {
      enable = true;
      defaultEditor = true;
      configure = {
        packages.all.start = with pkgs.vimPlugins; [
          nvim-treesitter.withAllGrammars # to install all grammars (including nix)
        ];
      };
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };


# fileSystems."/mnt/code" = {
#   device = "truenas-scale.bee-phrygian.ts.net:/mnt/ssd/code";
#   fsType = "nfs";
#   options = [ "rw" "nfsvers=4.1" ];
# };
  fileSystems."/mnt/code" = {
    device = "truenas-scale.bee-phrygian.ts.net:/mnt/ssd/code";
    fsType = "nfs";
    options = [
      "rw"
      "nfsvers=4.1"
      "x-systemd.automount"
      "x-systemd.idle-timeout=1m"
      "nofail"
      "noatime"
    ];
  };


  system.stateVersion = "24.11"; # Did you read the comment?
}
