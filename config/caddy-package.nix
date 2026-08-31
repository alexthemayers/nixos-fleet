{ pkgs }:
pkgs.caddy.withPlugins {
  plugins = [
    "github.com/corazawaf/coraza-caddy/v2@v2.5.0"
    "github.com/mholt/caddy-l4@v0.1.1"
    "github.com/mholt/caddy-ratelimit@v0.1.1-0.20260612195517-5625512f24f6"
  ];
  hash = "sha256-Zo+LbslsZ80Ceijf25ZzVmSzWlEisi6EgGTvfxuN5fI=";
}
