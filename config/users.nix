{ config, pkgs, ... }:

{
  services = {
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = [ 22 ];
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "yes";
        X11Forwarding = false;
      };
    };
  };
  users = {
    users.alex = {
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNU3LlO+b/kYovYE8CYSa2gExOw0hdCytCiziwIf3a6DVGGLsLELOwTcrUCr+ysnU6nUQT2JPrJCowB/wXx5X0Rcxv6+ZG/WxSukT858PEjKKt6nHp84NhsltidMLOw4kDL257M7CAXhMhVXvxW369jhYNM54tT/Tl2pMPKk0AeVd+RJGkJCjVAvmvX9W1YeggWYx9RgDYHlS3u4l0kTOpNVZQ+8SWeuPqsg52r7bh9biA3snb63UUaOSSgCQAKXS11S1SLu7XcYjk9A8vIqMbFGeu738/sn4THOn7Nq10hvbqQH9jIt4sfSq7LcQF8xXponv2P1PbYxYFsFWqABTBQXtrrQTpP+mlK2/eruuQRLcrNrmEoX05pCzZ2utGJh0mxLbIeMBRRc68CuFq0wxpCmPRjhPapLCM73ZPf26TEwS0dgHzQkX0ZJDOUBXyzBrniIdDV5KG52Fo4o7pM6i6t+BGQtVM9pqoGQOQGOsNq862n+liRQ8r3MjgDc9rxPHcs5ieA6RT4k9OnBW+UGiDx3W32iuyfc92WUm3Kdrj8+lfWnz6805cKt1UPUU0vK6tl4wZq64TdF2aBkllulTUP8ecLx0r/Mdw6ulXkA3rmj6wE6dJ3kigYGhOHWkck3AGQI9CX8EyjeGO3V4MVOx+BQpyqwtjKHefe9SjBcYHYQ== a.mayers102@gmail.com"
      ];
      isNormalUser = true;
      description = "alex";
      extraGroups = [
        "wheel"
        "docker"
        "render" # TODO: move to jellyfin
      ];
      shell = pkgs.zsh;
      packages = with pkgs; [ ];
    };
    users.root = {
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNU3LlO+b/kYovYE8CYSa2gExOw0hdCytCiziwIf3a6DVGGLsLELOwTcrUCr+ysnU6nUQT2JPrJCowB/wXx5X0Rcxv6+ZG/WxSukT858PEjKKt6nHp84NhsltidMLOw4kDL257M7CAXhMhVXvxW369jhYNM54tT/Tl2pMPKk0AeVd+RJGkJCjVAvmvX9W1YeggWYx9RgDYHlS3u4l0kTOpNVZQ+8SWeuPqsg52r7bh9biA3snb63UUaOSSgCQAKXS11S1SLu7XcYjk9A8vIqMbFGeu738/sn4THOn7Nq10hvbqQH9jIt4sfSq7LcQF8xXponv2P1PbYxYFsFWqABTBQXtrrQTpP+mlK2/eruuQRLcrNrmEoX05pCzZ2utGJh0mxLbIeMBRRc68CuFq0wxpCmPRjhPapLCM73ZPf26TEwS0dgHzQkX0ZJDOUBXyzBrniIdDV5KG52Fo4o7pM6i6t+BGQtVM9pqoGQOQGOsNq862n+liRQ8r3MjgDc9rxPHcs5ieA6RT4k9OnBW+UGiDx3W32iuyfc92WUm3Kdrj8+lfWnz6805cKt1UPUU0vK6tl4wZq64TdF2aBkllulTUP8ecLx0r/Mdw6ulXkA3rmj6wE6dJ3kigYGhOHWkck3AGQI9CX8EyjeGO3V4MVOx+BQpyqwtjKHefe9SjBcYHYQ== a.mayers102@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBWtDD746/XNq+8pWKb5I2MMEi6QarWmu0UNl7be7akX gitlab-ci-deploy"
      ];
      shell = pkgs.zsh;
    };
  };
}
