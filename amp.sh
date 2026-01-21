#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Clone)
# Author: Gemini
# License: MIT

# --- Variables ---
APP="AMP-Game-Panel"
var_tags="gaming"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

# --- Styles ---
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

# --- Functions ---

function header_info {
  clear
  cat << "EOF"
    ___  ___  _______ 
   / _ \ |  \/  | ___ \
  / /_\ \| .  . | |_/ /
  |  _  || |\/| |  __/ 
  | | | || |  | | |    
  \_| |_/\_|  |_/_|    
                       
  AMP Game Panel - CubeCoders
EOF
}

function msg_info() {
  local msg="$1"
  echo -ne " ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${CM} ${msg}${CL}"
}

# 1. Get Next Free ID
function get_next_id() {
    local ID=100
    while pct status $ID &>/dev/null || qm status $ID &>/dev/null; do
        ID=$((ID+1))
    done
    echo $ID
}

# 2. Get Valid Storage Pools
function get_storage_list() {
    # Returns a list formatted for whiptail: "ID" "Type (Free space)"
    pvesm status -content rootdir | awk 'NR>1 {print $1, $2"("$6")"}'
}

# --- Main Script ---

if [ `id -u` -ne 0 ]; then
    echo -e "${RD}This script must be run as root${CL}"
    exit 1
fi

# Dependency check for whiptail
if ! command -v whiptail &> /dev/null; then
    echo "Installing whiptail..."
    apt-get install -y whiptail >/dev/null 2>&1
fi

header_info

# Initialize Defaults
CTID=$(get_next_id)
HOSTNAME="amp-panel"
STORAGE="local-lvm"
MAC_ADDR=""
BRIDGE="vmbr0"
NET_IP="dhcp"
GATEWAY=""

# --- TUI: Standard vs Advanced ---
if (whiptail --title "AMP Installation" --yesno "This will create a new LXC for AMP.\n\nDefault Settings:\nCT ID: $CTID\nCPU: $var_cpu\nRAM: $var_ram MB\nDisk: $var_disk GB\nStorage: Auto\n\nProceed with defaults?" 12 58); then
    # User chose YES - Defaults
    ADVANCED=false
else
    # User chose NO - Advanced
    ADVANCED=true
fi

# --- TUI: Advanced Settings ---
if [ "$ADVANCED" = true ]; then
    # 1. Container ID
    CTID=$(whiptail --inputbox "Set Container ID" 8 58 $CTID --title "Container ID" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 2. Hostname
    HOSTNAME=$(whiptail --inputbox "Set Hostname" 8 58 "amp-panel" --title "Hostname" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 3. CPU
    var_cpu=$(whiptail --inputbox "CPU Cores" 8 58 "$var_cpu" --title "CPU Cores" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 4. RAM
    var_ram=$(whiptail --inputbox "RAM (MB)" 8 58 "$var_ram" --title "RAM Size" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 5. Disk Size
    var_disk=$(whiptail --inputbox "Disk Size (GB)" 8 58 "$var_disk" --title "Disk Size" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 6. Storage Selection
    STORAGE_LIST=$(get_storage_list)
    # Using eval to handle the spaces in the storage list correctly for whiptail
    STORAGE=$(eval whiptail --menu \"Select Storage Pool\" 15 60 5 $STORAGE_LIST 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 7. Bridge
    BRIDGE=$(whiptail --inputbox "Bridge Interface" 8 58 "vmbr0" --title "Network Bridge" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 8. IP Address
    NET_IP=$(whiptail --inputbox "IPv4 Address (dhcp or CIDR e.g. 192.168.1.5/24)" 8 58 "dhcp" --title "IP Address" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi

    # 9. Gateway (only if not DHCP)
    if [ "$NET_IP" != "dhcp" ]; then
        GATEWAY=$(whiptail --inputbox "Gateway IP" 8 58 "" --title "Gateway" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then exit; fi
    fi

    # 10. MAC Address (Crucial for you)
    MAC_ADDR=$(whiptail --inputbox "MAC Address (Leave empty for random)" 8 58 "" --title "MAC Filtering" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then exit; fi
fi

# --- Summary ---
header_info
echo -e "${DGN}Creating Container with settings:${CL}"
echo -e "ID: ${CTID} | Hostname: ${HOSTNAME}"
echo -e "CPU: ${var_cpu} | RAM: ${var_ram} | Disk: ${var_disk}G | Storage: ${STORAGE}"
if [ ! -z "$MAC_ADDR" ]; then echo -e "MAC: ${MAC_ADDR}"; fi
echo -e "-------------------------------------"

# --- Installation ---

# 1. Update Templates
msg_info "Updating Template Cache"
pveam update >/dev/null
msg_ok "Template Cache Updated"

# 2. Check/Download Debian 12
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
if ! pveam list local | grep -q "debian-12-standard"; then
    msg_info "Downloading Debian 12 Template"
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst >/dev/null
fi

# 3. Construct Network String
NET_STRING="name=eth0,bridge=${BRIDGE},type=veth"
if [ ! -z "$MAC_ADDR" ]; then NET_STRING="${NET_STRING},hwaddr=${MAC_ADDR}"; fi
if [ "$NET_IP" == "dhcp" ]; then
    NET_STRING="${NET_STRING},ip=dhcp"
else
    NET_STRING="${NET_STRING},ip=${NET_IP},gw=${GATEWAY}"
fi

# 4. Create Container
msg_info "Creating Container $CTID"
pct create $CTID $TEMPLATE -hostname $HOSTNAME -cores $var_cpu -memory $var_ram -swap 512 -storage $STORAGE -net0 "$NET_STRING" -features nesting=1 -unprivileged $var_unprivileged >/dev/null
pct resize $CTID rootfs ${var_disk}G >/dev/null
msg_ok "Container Created"

# 5. Start Container
msg_info "Starting Container"
pct start $CTID
msg_ok "Container Started"

# 6. Install Dependencies
msg_info "Installing Dependencies"
sleep 4 # Allow network up
pct exec $CTID -- bash -c "apt-get update && apt-get install -y wget curl git gnupg software-properties-common dirmngr ca-certificates apt-transport-https procps unzip socat" >/dev/null 2>&1
msg_ok "Dependencies Installed"

# 7. Install AMP (Silent Mode)
msg_info "Installing AMP Backend"
pct exec $CTID -- bash -c "wget -q https://repo.cubecoders.com/archive.key -O /usr/share/keyrings/repo.cubecoders.com.gpg"
pct exec $CTID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/repo.cubecoders.com.gpg] https://repo.cubecoders.com/ debian/' > /etc/apt/sources.list.d/amp.list"
pct exec $CTID -- bash -c "apt-get update && apt-get install -y ampinstmgr" >/dev/null 2>&1
msg_ok "AMP Backend Installed"

# 8. Final Message
IP=$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

echo -e "\n${GN}Installation Complete!${CL}"
echo -e "${DGN}To finish setup, please run the interactive wizard inside the container:${CL}"
echo -e "1. ${BGN}pct enter $CTID${CL}"
echo -e "2. ${BGN}su -l amp -c 'ampinstmgr quickstart'${CL}"
echo ""
echo -e "${INFO}${YW} Access URL: ${BGN}http://${IP}:8080${CL}"
