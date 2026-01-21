#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Adapted)
# Author: Gemini
# License: MIT
# Source: https://cubecoders.com/AMP

# --- Defaults ---
APP="AMP-Game-Panel"
var_tags="gaming"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"
var_storage="local-lvm"
var_bridge="vmbr0"
var_mac=""
var_ip="dhcp"
var_gateway=""
var_vlan=""
var_mtu=""

# --- Styling ---
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

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

function msg_error() {
  local msg="$1"
  echo -e "${CROSS} ${msg}${CL}"
}

# --- Main Logic ---

if [ `id -u` -ne 0 ]; then
    msg_error "This script must be run as root"
    exit 1
fi

header_info

echo -e "${BL}This script will create a new LXC for AMP.${CL}"
echo -e "${DGN}Defaults: ${var_cpu}vCPU, ${var_ram}MB RAM, ${var_disk}GB Disk, ${var_os} ${var_version}${CL}"

# --- Prompt for Mode ---
while true; do
    read -p "Use Default Settings? (y/n): " yn
    case $yn in
        [Yy]* ) ADVANCED=false; break;;
        [Nn]* ) ADVANCED=true; break;;
        * ) echo "Please answer yes or no.";;
    esac
done

# --- ID & Hostname (Always Required) ---
while true; do
    read -p "Container ID: " CTID
    if [ -z "$CTID" ]; then
        echo "Container ID cannot be empty."
    elif pct status $CTID &>/dev/null; then
        echo "ID $CTID is already in use."
    else
        break
    fi
done

read -p "Hostname (default: amp-panel): " HOSTNAME
HOSTNAME=${HOSTNAME:-amp-panel}

# --- Advanced Settings Loop ---
if [ "$ADVANCED" = true ]; then
    echo -e "\n${BL}--- Advanced Configuration ---${CL}"
    
    read -p "CPU Cores (Default: ${var_cpu}): " input_cpu
    var_cpu=${input_cpu:-$var_cpu}
    
    read -p "RAM in MB (Default: ${var_ram}): " input_ram
    var_ram=${input_ram:-$var_ram}
    
    read -p "Disk Size in GB (Default: ${var_disk}): " input_disk
    var_disk=${input_disk:-$var_disk}
    
    read -p "Storage Pool (Default: ${var_storage}): " input_storage
    var_storage=${input_storage:-$var_storage}
    
    read -p "Bridge (Default: ${var_bridge}): " input_bridge
    var_bridge=${input_bridge:-$var_bridge}
    
    read -p "MAC Address (Leave empty for random): " input_mac
    var_mac=${input_mac:-$var_mac}
    
    read -p "IPv4 Address (Default: dhcp, or CIDR e.g. 192.168.1.50/24): " input_ip
    var_ip=${input_ip:-$var_ip}
    
    if [ "$var_ip" != "dhcp" ]; then
        read -p "Gateway IP: " input_gateway
        var_gateway=${input_gateway:-$var_gateway}
    fi

    read -p "VLAN Tag (Leave empty for none): " input_vlan
    var_vlan=${input_vlan:-$var_vlan}
fi

# --- Build Network String ---
# We build the net0 string based on inputs to ensure MAC filtering works
NET_STRING="name=eth0,bridge=${var_bridge},type=veth"

if [ ! -z "$var_mac" ]; then
    NET_STRING="${NET_STRING},hwaddr=${var_mac}"
fi

if [ "$var_ip" == "dhcp" ]; then
    NET_STRING="${NET_STRING},ip=dhcp"
else
    NET_STRING="${NET_STRING},ip=${var_ip},gw=${var_gateway}"
fi

if [ ! -z "$var_vlan" ]; then
    NET_STRING="${NET_STRING},tag=${var_vlan}"
fi

# --- Execution ---
echo -e "\n${BL}--- Installation ---${CL}"

# 1. Template
msg_info "Updating Template Cache"
pveam update >/dev/null
msg_ok "Template Cache Updated"

TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
msg_info "Checking Debian 12 Template"
if ! pveam list local | grep -q "debian-12-standard"; then
    msg_info "Downloading Debian 12 Template"
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst >/dev/null
fi
msg_ok "Template Ready"

# 2. Create Container
msg_info "Creating Container $CTID ($HOSTNAME)"
pct create $CTID $TEMPLATE -hostname $HOSTNAME -cores $var_cpu -memory $var_ram -swap 512 -storage $var_storage -net0 "$NET_STRING" -features nesting=1 -unprivileged $var_unprivileged >/dev/null
pct resize $CTID rootfs ${var_disk}G >/dev/null
msg_ok "Container Created"

# 3. Start
msg_info "Starting Container"
pct start $CTID
msg_ok "Container Started"

# 4. Install Dependencies
msg_info "Installing Prerequisites (curl, git, java, deps)"
sleep 4 # Wait for network
pct exec $CTID -- bash -c "apt-get update && apt-get install -y wget curl git gnupg software-properties-common dirmngr ca-certificates apt-transport-https procps unzip socat" >/dev/null 2>&1
msg_ok "Prerequisites Installed"

# 5. Install AMP Backend (Non-Interactive)
msg_info "Adding CubeCoders Repository"
pct exec $CTID -- bash -c "wget -q https://repo.cubecoders.com/archive.key -O /usr/share/keyrings/repo.cubecoders.com.gpg"
pct exec $CTID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/repo.cubecoders.com.gpg] https://repo.cubecoders.com/ debian/' > /etc/apt/sources.list.d/amp.list"
pct exec $CTID -- bash -c "apt-get update" >/dev/null 2>&1
msg_ok "Repository Added"

msg_info "Installing AMP Manager"
pct exec $CTID -- bash -c "apt-get install -y ampinstmgr" >/dev/null 2>&1
msg_ok "AMP Manager Installed"

# 6. Final Steps
IP_ADDR=$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

echo -e "\n${GN}Installation Phase 1 Completed!${CL}"
echo -e "${DGN}To finish the setup, you must run the quickstart wizard manually inside the container.${CL}"
echo -e "${DGN}This prevents the 'unknown option: t' error.${CL}"
echo ""
echo -e "1. Enter the container:     ${BGN}pct enter $CTID${CL}"
echo -e "2. Run the setup wizard:    ${BGN}su -l amp -c 'ampinstmgr quickstart'${CL}"
echo ""
echo -e "${INFO}${YW} Once finished, AMP will be reachable at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP_ADDR}:8080${CL}"
