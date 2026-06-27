{ config, pkgs, ... }:
{
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
  };

  security.audit = {
    enable = true;
    backlogLimit = 8192;
    rules = [
      "-i" # Ignore missing files in watches

      # Track authentication & identity modification
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/gshadow -p wa -k identity"
      # Track privilege escalation configurations (sudoers)
      "-w /etc/sudoers -p wa -k privilege_escalation"
      "-w /etc/sudoers.d -p wa -k privilege_escalation"

      # Track system logins, logouts, and failed logins
      "-w /var/log/lastlog -p wa -k logins"
      "-w /var/run/utmp -p wa -k logins"
      "-w /var/log/wtmp -p wa -k logins"
      "-w /var/log/btmp -p wa -k logins"

      # Track critical network configuration files
      "-w /etc/hosts -p wa -k network"
      "-w /etc/resolv.conf -p wa -k network"
      "-w /etc/nixos -p wa -k nixos_config"

      # Track kernel parameters and module loading/unloading
      "-w /etc/sysctl.conf -p wa -k kernel_params"
      "-w /etc/sysctl.d -p wa -k kernel_params"
      "-a always,exit -F arch=b64 -S init_module -S delete_module -S finit_module -k module_load"

      # Track permission/ownership changes
      "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k perm_mod"
      "-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -k perm_mod"

      # Track privilege execution system calls
      "-a always,exit -F arch=b64 -S setuid -S setgid -S setresuid -S setresgid -k privilege_escalation"
    ];
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.fwupd.refresh-remote" &&
          subject.user == "fwupd-refresh") {
        return polkit.Result.YES;
      }
    });
  '';
}
