{ config, pkgs, ... }:
{

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
