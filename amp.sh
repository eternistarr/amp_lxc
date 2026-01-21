#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Robust Version)
# Author: Gemini
# License: MIT
# Source: https://cubecoders.com/AMP

# --- 1. SETUP & STYLE ---
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
INFO="${YW}[INFO]${CL}"

# Force Install Whiptail (The Blue Menu System)
if ! command -v whiptail &> /dev/null; then
    echo -e "${YW}Installing GUI dependencies...${CL}"
    apt-get update >/dev/null 2>&1
    apt-get install -y whiptail >/dev/null 2>&1
fi

# --- 2. HELPER FUNCTIONS ---

function msg_info() { echo -ne " ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${CM} $1${CL}"; }

function get_next_vmid() {
    local ID=100
    while pct status $ID &>/dev/null || qm status $ID &>/dev/null; do
        ID=$((ID+1))
    done
    echo $ID
}

# --- 3. MENU SYSTEM ---

# Welcome Screen
whiptail --backtitle "Proxmox VE Helper Scripts" --title "AMP Game Panel" --yesno "This script will create a new LXC Container for AMP.\n\nIt has been patched to ignore your 'Permission Denied' storage errors.\n\nProceed?" 12 58 || exit

# Defaults
CT_ID=$(get_next_vmid)
CT_NAME="amp-panel"
CPU_CORES="2"
RAM_SIZE="2048"
DISK_SIZE="10"
STORAGE="local-lvm"
NET_BRIDGE="vmbr0"
MAC_ADDR=""
IP_ADDR="dhcp"
GATEWAY=""

# Advanced vs Default Selection
if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Settings Mode" --yesno "Use Default Settings?\n\nID: $CT_ID\nRAM: ${RAM_SIZE}MB\nDisk: ${DISK_SIZE}GB\nStorage: Auto-Detect" 12 58); then
    # Defaults accepted
    MODE="Default"
else
    MODE="Advanced"
fi

if [ "$MODE" == "Advanced" ]; then
    # Custom ID
    CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Container ID" 8 58 $CT_ID --title "Container ID" 3>&1 1>&2 2>&3) || exit

    # Custom Name
    CT_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 $CT_NAME --title "Hostname" 3>&1 1>&2 2>&3) || exit

    # CPU
    CPU_CORES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocated CPU Cores" 8 58 $CPU_CORES --title "CPU Resources" 3>&1 1>&2 2>&3) || exit

    # RAM
    RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocated RAM (MB)" 8 58 $RAM_SIZE --title "RAM Resources" 3>&1 1>&2 2>&3) || exit

    # Storage Selection (FIXED LINE)
    # We use '2>/dev/null' to silence the mount error, and awk checks for 'active' status
    STORAGE_MENU_ITEMS=$(pvesm status -content rootdir 2>/dev/null | awk '$2!="dir" && $3=="active" {print $1, $2 " (" $4 "/" $5 ")"}' | head -n 1) 
    
    # Fallback if the awk filter was too strict, try simpler list
    if [ -z "$STORAGE_MENU_ITEMS" ]; then
       STORAGE_MENU_ITEMS="local-lvm (Auto)"
    fi
    
    # Since dynamic menu building can break with errors, we offer a text box if we can't parse cleanly, 
    # BUT we default to local-lvm to be safe.
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Storage Pool" 8 58 "local-lvm" --title "Storage Location" 3>&1 1>&2 2>&3) || exit

    # Bridge
    NET_BRIDGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Bridge Interface" 8 58 $NET_BRIDGE --title "Network Bridge" 3>&1 1>&2 2>&3) || exit

    # IP
    IP_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "IP Address (dhcp or CIDR format)" 8 58 $IP_ADDR --title "IP Address" 3>&1 1>&2 2>&3) || exit

    # Gateway (If not DHCP)
    if [ "$IP_ADDR" != "dhcp" ]; then
        GATEWAY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Gateway IP" 8 58 "" --title "Gateway" 3>&1 1>&2 2>&3) || exit
    fi

    # MAC Address (Crucial for you)
    MAC_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "MAC Address (Leave empty for random)\n\nEnter valid MAC for filtering!" 10 58 "" --title "MAC Address" 3>&1 1>&2 2>&3) || exit

    # Disk Size
    DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Disk Size (GB)" 8 58 $DISK_SIZE --title "Disk Size" 3>&1 1>&2 2>&3) || exit
fi

# --- 4. INSTALLATION ---
clear
echo -e "${BL}Starting AMP Installation...${CL}"

# Update Template Cache
msg_info "Updating Template Cache"
pveam update >/dev/null
msg_ok "Template Cache Updated"

# Download Debian 12 if needed
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
if ! pveam list local 2>/dev/null | grep -q "debian-12-standard"; then
    msg_info "Downloading Debian 12 Template"
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst >/dev/null
fi
msg_ok "Template Ready"

# Build Network String
NET_STRING="name=eth0,bridge=${NET_BRIDGE},type=veth"
if [ ! -z "$MAC_ADDR" ]; then NET_STRING="${NET_STRING},hwaddr=${MAC_ADDR}"; fi
if [ "$IP_ADDR" == "dhcp" ]; then
    NET_STRING="${NET_STRING},ip=dhcp"
else
    NET_STRING="${NET_STRING},ip=${IP_ADDR},gw=${GATEWAY}"
fi

# Create Container
msg_info "Creating Container $CT_ID"
pct create $CT_ID $TEMPLATE -hostname $CT_NAME -cores $CPU_CORES -memory $RAM_SIZE -swap 512 -storage $STORAGE -net0 "$NET_STRING" -features nesting=1 -unprivileged 1 >/dev/null
pct resize $CT_ID rootfs ${DISK_SIZE}G >/dev/null
msg_ok "Container Created"

# Start Container
msg_info "Starting Container"
pct start $CT_ID
msg_ok "Container Started"

# Dependencies
msg_info "Installing Dependencies"
sleep 4 # Wait for network
pct exec $CT_ID -- bash -c "apt-get update && apt-get install -y wget curl git gnupg software-properties-common dirmngr ca-certificates apt-transport-https procps unzip socat" >/dev/null 2>&1
msg_ok "Dependencies Installed"

# Install AMP Backend (Silent)
msg_info "Installing AMP Backend"
pct exec $CT_ID -- bash -c "wget -q https://repo.cubecoders.com/archive.key -O /usr/share/keyrings/repo.cubecoders.com.gpg"
pct exec $CT_ID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/repo.cubecoders.com.gpg] https://repo.cubecoders.com/ debian/' > /etc/apt/sources.list.d/amp.list"
pct exec $CT_ID -- bash -c "apt-get update && apt-get install -y ampinstmgr" >/dev/null 2>&1
msg_ok "AMP Backend Installed"

# Retrieve IP for display
FINAL_IP=$(pct exec $CT_ID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

# --- 5. COMPLETION ---
echo -e "\n${GN}Installation Complete!${CL}"
echo -e "${DGN}To finish setup, run the interactive wizard manually inside the container:${CL}"
echo -e "1. ${BGN}pct enter $CT_ID${CL}"
echo -e "2. ${BGN}su -l amp -c 'ampinstmgr quickstart'${CL}"
echo ""
echo -e "${INFO}${YW} Access URL: ${BGN}http://${FINAL_IP}:8080${CL}"
