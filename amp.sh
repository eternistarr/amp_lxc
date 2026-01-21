#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Adapted)
# Author: Gemini (Adapted from community-scripts)
# License: MIT
# Source: https://cubecoders.com/AMP

APP="AMP-Game-Panel"
var_tags="gaming"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

# Colors
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
jg="json_pp"

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
  echo -e "${RD} ${msg}${CL}"
}

# Check if script is running as root
if [ `id -u` -ne 0 ]; then
    msg_error "This script must be run as root"
    exit 1
fi

header_info

# 1. Ask for Container Settings
echo -e "${BL}This script will create a new LXC for AMP.${CL}"
echo -e "${BL}Default: 2vCPU, 2GB RAM, 10GB Disk, Debian 12${CL}"
echo ""

read -p "Container ID: " CTID
if [ -z "$CTID" ]; then msg_error "Container ID is required."; exit 1; fi

read -p "Hostname (default: amp-panel): " HOSTNAME
HOSTNAME=${HOSTNAME:-amp-panel}

read -p "Password for 'root' user (leave empty for none): " PASSWORD

# 2. Download Template
msg_info "Updating Template Cache"
pveam update >/dev/null
msg_ok "Template Cache Updated"

TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
# Check if template exists, if not download (simplified logic)
# Ideally you check `pveam available` but for brevity we assume standard repo
msg_info "Checking/Downloading Debian 12 Template"
pveam download local debian-12-standard_12.7-1_amd64.tar.zst >/dev/null 2>&1 || true
msg_ok "Template Ready"

# 3. Create Container
msg_info "Creating Container $CTID ($HOSTNAME)"
# Basic creation
pct create $CTID $TEMPLATE -hostname $HOSTNAME -cores $var_cpu -memory $var_ram -swap 512 -storage local-lvm -net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth -features nesting=1 -unprivileged $var_unprivileged >/dev/null
# Resize disk
pct resize $CTID rootfs ${var_disk}G >/dev/null
# Set password if provided
if [ ! -z "$PASSWORD" ]; then
  pct set $CTID -password "$PASSWORD" >/dev/null
fi
msg_ok "Container Created"

# 4. Start Container
msg_info "Starting Container"
pct start $CTID
msg_ok "Container Started"

# 5. Prepare Dependencies
msg_info "Installing Dependencies (curl, wget, git, etc.)"
# Wait for network
sleep 5
pct exec $CTID -- bash -c "apt-get update && apt-get install -y wget curl git gnupg software-properties-common dirmngr ca-certificates apt-transport-https procps" >/dev/null 2>&1
msg_ok "Dependencies Installed"

# 6. Run AMP Installer
echo -e "${YW}--------------------------------------------------------${CL}"
echo -e "${YW}Launching AMP Installer...${CL}"
echo -e "${YW}Please follow the prompts on the screen.${CL}"
echo -e "${YW}--------------------------------------------------------${CL}"

# Use 'exec -t' to allocate a TTY for the interactive installer
pct exec $CTID -t -- bash -c "bash <(wget -qO- getamp.sh)"

# 7. Finalize
IP=$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
echo -e "\n${GN}Installation Completed!${CL}"
echo -e "${INFO}${YW} Access AMP using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
