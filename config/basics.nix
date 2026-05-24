{ config, pkgs, ... }:
{
  users.defaultUserShell = pkgs.zsh;
  programs = {
    starship = {
      enable = true;
      settings = {
        # Add a visual indicator for your vi mode state
        character = {
          success_symbol = "[❯](bold green)";
          error_symbol = "[❯](bold red)";
          vimcmd_symbol = "[❮](bold yellow)";
        };
      };
    };
    zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      histSize = 50000;
      setOptions = [
        "HIST_IGNORE_DUPS"
        "HIST_IGNORE_SPACE"
        "HIST_FCNTL_LOCK"
        "SHARE_HISTORY"
      ];
      interactiveShellInit = ''
        source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
      '';
      shellAliases = {
        ll = "ls -l";
      };
      promptInit = ''
        # Initialize completion system with caching for speed
        autoload -Uz compinit
        compinit -C

        # Enable menu-style selection for completions
        zstyle ':completion:*' menu select
        source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme
        source /etc/powerlevel10k/p10k.zsh

        # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
        # Initialization code that may require console input (password prompts, [y/n]
        # confirmations, etc.) must go above this block; everything else may go below.
        # double single quotes ('\') to escape the dollar char
        if [[ -r "''${XDG_CACHE_HOME:-''$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-''$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '';
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
        theme = "powerlevel10k/powerlevel10k";
      };
    };
    fzf = {
      fuzzyCompletion = true;
      keybindings = true;
    };
    neovim = {
      enable = true;
      defaultEditor = true;
    };
  };
  system.userActivationScripts.zshrc = "touch .zshrc"; # to avoid being prompted to generate the config for first time
  environment.systemPackages = with pkgs; [
    zsh-completions
    zsh-powerlevel10k
    zsh-vi-mode
  ];
}
