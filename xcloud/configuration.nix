{ modulesPath, config, lib, pkgs, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
  ];

  # allow unfree packages to be installed
  nixpkgs.config = { allowUnfree = true; };

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  networking = {
    hostName = "nixos-xcloud"; # Define your hostname.
    firewall.enable = true;
  };

  # Set your time zone.
  time.timeZone = "Africa/Johannesburg";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # UNCOMMENT this to enable docker
  # virtualisation.docker.enable = true;

  programs.fish.enable = true;

  security.sudo.wheelNeedsPassword = false;

  services = {
    openssh = {
      enable = true;
      settings.PasswordAuthentication = false;
    };

    iperf3.enable = true;
    # UNCOMMENT this to enable headscale
    # headscale.enable = true;

    # UNCOMMENT this to enable a prometheus node exporter
    prometheus.exporters.node.enable = true;

    # UNCOMMENT this to enable homeassistant-satellite - it's prob necessary to add more configuration here
    # homeassistant-satellite.enable = true;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal

    # UNCOMMENT the following to install these packages systemwide
    # pkgs.jq
    pkgs.neovim
    pkgs.btop
  ];

  users.users = {

    root = {
      # change this to your ssh key
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNU3LlO+b/kYovYE8CYSa2gExOw0hdCytCiziwIf3a6DVGGLsLELOwTcrUCr+ysnU6nUQT2JPrJCowB/wXx5X0Rcxv6+ZG/WxSukT858PEjKKt6nHp84NhsltidMLOw4kDL257M7CAXhMhVXvxW369jhYNM54tT/Tl2pMPKk0AeVd+RJGkJCjVAvmvX9W1YeggWYx9RgDYHlS3u4l0kTOpNVZQ+8SWeuPqsg52r7bh9biA3snb63UUaOSSgCQAKXS11S1SLu7XcYjk9A8vIqMbFGeu738/sn4THOn7Nq10hvbqQH9jIt4sfSq7LcQF8xXponv2P1PbYxYFsFWqABTBQXtrrQTpP+mlK2/eruuQRLcrNrmEoX05pCzZ2utGJh0mxLbIeMBRRc68CuFq0wxpCmPRjhPapLCM73ZPf26TEwS0dgHzQkX0ZJDOUBXyzBrniIdDV5KG52Fo4o7pM6i6t+BGQtVM9pqoGQOQGOsNq862n+liRQ8r3MjgDc9rxPHcs5ieA6RT4k9OnBW+UGiDx3W32iuyfc92WUm3Kdrj8+lfWnz6805cKt1UPUU0vK6tl4wZq64TdF2aBkllulTUP8ecLx0r/Mdw6ulXkA3rmj6wE6dJ3kigYGhOHWkck3AGQI9CX8EyjeGO3V4MVOx+BQpyqwtjKHefe9SjBcYHYQ== a.mayers102@gmail.com"
      ];
    };

    # UNCOMMENT the following to enable the nixos user
    # nixos = {
    #   isNormalUser = true; 
    #   shell = pkgs.fish; 
    #   description = "nixos user"; 
    #   extraGroups = [ 
    #     "networkmanager" 
    #     "wheel" 
    #     "docker"
    #   ]; 
    #   openssh.authorizedKeys.keys = [
    #     "CHANGE"
    #   ];
    # };

  };

  system.stateVersion = "25.11";
}
