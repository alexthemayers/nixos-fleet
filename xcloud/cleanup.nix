{ config, pkgs, ... }:

{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    # Delete generations older than 7 days
    options = "--delete-older-than 7d";
  };

  # Optional: Optimizes the store by hard-linking duplicate files
  # This runs every time a store path is added.
  nix.settings.auto-optimise-store = true;
}
