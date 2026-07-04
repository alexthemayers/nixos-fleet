# Workstation Profile: `gaming`

This document details the configuration, drivers, and desktop environment settings specific to the personal workstation
**`gaming`** defined in the [hosts/gaming/](file:///Users/alex/code/nixos-fleet/hosts/gaming) directory.

---

## ⚙️ Hardware and Kernel Optimizations

The workstation uses an AMD processor and graphics card. Dedicated settings are applied
in [configuration.nix](file:///Users/alex/code/nixos-fleet/hosts/gaming/configuration.nix)
and [amdgpu.nix](file:///Users/alex/code/nixos-fleet/hosts/gaming/amdgpu.nix) to optimize performance:

1. **AMD CPU Telemetry & Power:**
    * **Kernel Parameters:** Configured with `amd_pstate=guided` for hardware-guided CPU frequency scaling.
    * **Zenpower Driver:** Blacklists the standard `k10temp` module and loads the `zenpower` out-of-tree module (
      `boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ]`). This provides detailed voltage and
      temperature reporting for Ryzen processors.
    * **Governor:** Uses `schedutil` as the CPU frequency governor.
2. **AMD GPU Driver & Vulkan Tuning:**
    * Loads the `amdgpu` kernel module and configures the X server driver.
    * **RADV Driver Enforcement:** Explicitly sets the environment variable `AMD_VULKAN_ICD = "RADV"`. This forces the
      system to compile Vulkan pipelines using Mesa's community-developed RADV driver (which offers better performance
      and compatibility with DXVK/Steam) rather than AMDVLK.
    * **LACT Daemon:** Integrates **LACT** (Linux AMD Controller) to monitor temperatures, manage fan curves, and adjust
      GPU clocks. The daemon is run as systemd service `lactd.service`.

---

## 🖥️ Desktop and User Experience

* **Display Manager:** SDDM configured to run natively on Wayland (
  `services.displayManager.sddm.wayland.enable = true`).
* **Desktop Environment:** KDE Plasma 6. To maintain a clean installation, native applications like the Elisa music
  player and plasma-browser-integration are excluded.
* **User Isolation:** User `alex` is granted low-level hardware permissions by mapping to the following groups: `video`,
  `audio`, `cpu`, `input`, and `gamemode`.

### Custom Keyboard Mapping (`keyd`)

To streamline text editing and vim navigation, the keyboard mapping daemon `keyd` is configured globally
in [alex.nix](file:///Users/alex/code/nixos-fleet/hosts/gaming/alex.nix):

- Captures all keyboards (`ids = [ "*" ]`).
- Remaps **CapsLock** to function as **Escape** in the main layout.

---

## 🎮 Compatibility & Gaming Runtimes

Workstation-specific packages and gaming runtimes are managed
in [gaming.nix](file:///Users/alex/code/nixos-fleet/hosts/gaming/gaming.nix):

* **Steam Integration:** Globally enabled using NixOS's default steam helper (`programs.steam.enable = true`).
* **Performance Overlays:** Installs Feral Interactive's **GameMode** daemon (allocating scheduling priorities during
  gameplay) and **MangoHud** (Vulkan performance overlay).
* **Wine compatibility layers:** Configured with native Wine packages (`wineWow64Packages.waylandFull` and
  `wineWow64Packages.staging`) and Winetricks to run non-native applications.
* **AppImage Handling:** Enables **AppImage** integration with `binfmt = true` registering the runner globally. This
  allows the system to execute downloaded AppImage binaries directly like standard executables.
