{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    neovim
    wget
    gnumake
    tmux
    jq
    tree
    iperf3
    mtr
    inetutils
    pciutils
  ];
  environment.etc."skel/.zshrc".text = ''
    # Managed by NixOS
    # This file prevents the zsh newuser install prompt.
    bindkey -v
  '';

  programs = {
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      shellAliases = {
        ll = "ls -l";
      };
      ohMyZsh = {
        enable = true;
        plugins = [
          "git"
          "docker"
          "kubectl"
          "nmap"
          "ruby"
          "rust"
          "systemd"
        ];
        theme = "robbyrussell";
      };
      shellInit = ''
        bindkey -v
      '';
    };

    neovim = {
      enable = true;
      defaultEditor = true;
    };
  };

}
