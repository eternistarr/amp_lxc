#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Clone)
# Author: Gemini
# License: MIT
# Source: https://cubecoders.com/AMP

# --- 1. PRE-CHECKS & STYLING ---
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

# Check Root
if [[ `id -u` -ne 0 ]]; then
    echo -e "${RD}Error: This script must be run as root.${CL}"
    exit 1
fi

# Auto-Install Whiptail (GUI) if missing
if ! command -v whiptail &> /dev/null; then
    echo -e "${YW}Installing GUI dependencies...${CL}"
    apt-get update >/dev/null 2>&1
    apt-get install -y whiptail >/dev/null 2>&1
fi

# --- 2. HELPER FUNCTIONS ---

function msg_info() { echo -ne " ${YW}$1...${CL}"; }
function msg_ok() { echo -e "${CM} $1${CL}"; }

# Find next free Container ID
function get_next_vmid() {
    local ID=100
    while pct status $ID &>/dev/null || qm status $ID &>/dev/null; do
        ID=$((ID+1))
    done
    echo $ID
}

# --- 3. MENU INTERFACE ---

# Welcome
whiptail --backtitle "Proxmox VE Helper Scripts" --title "AMP Game Panel" --yesno "This script will create a new LXC Container for AMP.\n\nProceed?" 10 58 || exit

# Defaults
CT_ID=$(get_next_vmid)
HOSTNAME="amp-panel"
CPU_CORES="2"
RAM_SIZE="2048"
DISK_SIZE="10"
STORAGE="local-lvm"
NET_BRIDGE="vmbr0"
MAC_ADDR=""
IP_ADDR="dhcp"
GATEWAY=""

# Mode Selection
if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Settings" --yesno "Use Default Settings?\n\nID: $CT_ID\nRAM: ${RAM_SIZE}MB\nDisk: ${DISK_SIZE}GB\nStorage: Auto-Detect (local-lvm)" 14 58); then
    MODE="Default"
else
    MODE="Advanced"
fi

# Advanced Configuration
if [ "$MODE" == "Advanced" ]; then
    # 1. Container ID
    CT_ID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Container ID" 8 58 $CT_ID --title "Container ID" 3>&1 1>&2 2>&3) || exit

    # 2. Hostname
    HOSTNAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 $HOSTNAME --title "Hostname" 3>&1 1>&2 2>&3) || exit

    # 3. CPU
    CPU_CORES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocated CPU Cores" 8 58 $CPU_CORES --title "CPU Resources" 3>&1 1>&2 2>&3) || exit

    # 4. RAM
    RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocated RAM (MB)" 8 58 $RAM_SIZE --title "RAM Resources" 3>&1 1>&2 2>&3) || exit

    # 5. Storage (Dynamic Scanning)
    # This scans your Proxmox storage and creates a menu list
    STORAGE_MENU=$(pvesm status -content rootdir | awk 'NR>1 {print $1, $2 " (" $4 "/" $5 ")"}' | tr '\n' ' ')
    STORAGE=$(eval whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pool" --menu \"Select Storage Location\" 15 60 5 $STORAGE_MENU 3>&1 1>&2 2>&3) || exit

    # 6. Disk Size
    DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Disk Size (GB)" 8 58 $DISK_SIZE --title "Disk Size" 3>&1 1>&2 2>&3) || exit

    # 7. Bridge
    NET_BRIDGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Bridge Interface" 8 58 $NET_BRIDGE --title "Network Bridge" 3>&1 1>&2 2>&3) || exit

    # 8. IP
    IP_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "IP Address (dhcp or CIDR)" 8 58 $IP_ADDR --title "IP Address" 3>&1 1>&2 2>&3) || exit

    # 9. Gateway
    if [ "$IP_ADDR" != "dhcp" ]; then
        GATEWAY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Gateway IP" 8 58 "" --title "Gateway" 3>&1 1>&2 2>&3) || exit
    fi

    # 10. MAC Address (For Filtering)
    MAC_ADDR=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "MAC Address (Leave empty for random)\n\nExample: AA:BB:CC:11:22:33" 10 58 "" --title "MAC Address" 3>&1 1>&2 2>&3) || exit
fi

# --- 4. INSTALLATION ---
clear
echo -e "${BL}Starting AMP Installation...${CL}"

# Update Templates
msg_info "Updating Template Cache"
pveam update >/dev/null
msg_ok "Template Cache Updated"

# Check/Download Debian 12
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
if ! pveam list local | grep -q "debian-12-standard"; then
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
pct create $CT_ID $TEMPLATE -hostname $HOSTNAME -cores $CPU_CORES -memory $RAM_SIZE -swap 512 -storage $STORAGE -net0 "$NET_STRING" -features nesting=1 -unprivileged 1 >/dev/null
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

# Get Final IP
FINAL_IP=$(pct exec $CT_ID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

# --- 5. FINISHING UP ---
echo -e "\n${GN}Installation Phase 1 Complete!${CL}"
echo -e "${DGN}To finish the setup securely, please run the following two commands:${CL}"
echo -e ""
echo -e "1. Enter the container:     ${BGN}pct enter $CT_ID${CL}"
echo -e "2. Run the setup wizard:    ${BGN}su -l amp -c 'ampinstmgr quickstart'${CL}"
echo -e ""
echo -e "${INFO}${YW} Once completed, access AMP at: ${BGN}http://${FINAL_IP}:8080${CL}"
