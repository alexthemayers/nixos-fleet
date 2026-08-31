#!/bin/sh
# Managed by Ansible — do not edit manually. See ansible/roles/pve_nag/
# Removes the "No valid subscription" dialog from the Proxmox VE web interface.

PROXMOXLIB="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"

if [ -f "$PROXMOXLIB" ]; then
    if grep -q "No valid sub" "$PROXMOXLIB" && ! grep -q "void({ //" "$PROXMOXLIB"; then
        sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" "$PROXMOXLIB"
        systemctl restart pveproxy.service
        echo "Proxmox subscription nag removed."
    else
        echo "Subscription nag already removed or not present."
    fi
fi
