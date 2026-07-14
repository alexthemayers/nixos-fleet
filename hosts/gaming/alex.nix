{ pkgs, ... }:
{
  users.users.alex = {
    packages = with pkgs; [
      firefox
      reaper
      jetbrains.idea
      spotify
      vlc
      zoom-us
    ];
  };
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            capslock = "esc";
          };
        };
      };
    };
  };
}
