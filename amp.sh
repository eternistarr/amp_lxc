#!/usr/bin/env bash

# Copyright (c) 2025 community-scripts ORG (Ported for AMP)
# Author: Gemini (Ported from bvdberg01)
# License: MIT
# Source: https://cubecoders.com/AMP

# --- Application Settings ---
APP="AMP"
var_tags="gaming"
var_cpu="2"
var_ram="2048"
var_disk="10"
var_os="debian"
var_version="12"
var_unprivileged="1"

# --- Styles & Colors ---
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
TAB="  "

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

# --- Infrastructure Functions (Replicating build.func) ---

function check_root() {
  if [[ `id -u` -ne 0 ]]; then
    msg_error "Must be run as root!"
    exit 1
  fi
}

function check_deps() {
  if ! command -v whiptail &> /dev/null; then
    msg_info "Installing whiptail (required for GUI)"
    apt-get update >/dev/null 2>&1
    apt-get install -y whiptail >/dev/null 2>&1
    msg_ok "Installed whiptail"
  fi
}

function get_next_vmid() {
  local ID=100
  while pct status $ID &>/dev/null || qm status $ID &>/dev/null; do
    ID=$((ID+1))
  done
  echo $ID
}

function variables() {
  CTID=$(get_next_vmid)
  HOSTNAME="amp-panel"
  STORAGE="local-lvm"
  MAC=""
  BRIDGE="vmbr0"
  NET="dhcp"
  GATEWAY=""
  VLAN=""
  MTU=""

  # The "Default vs Advanced" Menu
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Settings" --yesno "This will create a new LXC for ${APP}.\n\nDefault Settings:\nCT ID: $CTID\nCPU: ${var_cpu}\nRAM: ${var_ram}MB\nDisk: ${var_disk}GB\n\nProceed with defaults?" 14 58); then
    # User chose Default (Yes)
    return
  else
    # User chose Advanced (No) - Open the full menu
    
    # 1. CT ID
    CTID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Container ID" 8 58 $CTID --title "Container ID" 3>&1 1>&2 2>&3) || exit
    
    # 2. Hostname
    HOSTNAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 $HOSTNAME --title "Hostname" 3>&1 1>&2 2>&3) || exit
    
    # 3. Resources
    var_cpu=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "CPU Cores" 8 58 $var_cpu --title "CPU" 3>&1 1>&2 2>&3) || exit
    var_ram=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "RAM (MB)" 8 58 $var_ram --title "RAM" 3>&1 1>&2 2>&3) || exit
    var_disk=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Disk Size (GB)" 8 58 $var_disk --title "Disk" 3>&1 1>&2 2>&3) || exit
    
    # 4. Storage (Dynamic List)
    STORAGE_MENU=$(pvesm status -content rootdir | awk 'NR>1 {print $1, $2 " (" $4 "/" $5 ")"}' | tr '\n' ' ')
    STORAGE=$(eval whiptail --backtitle "Proxmox VE Helper Scripts" --menu \"Select Storage Pool\" 15 60 5 $STORAGE_MENU 3>&1 1>&2 2>&3) || exit
    
    # 5. Network
    BRIDGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Bridge" 8 58 $BRIDGE --title "Bridge" 3>&1 1>&2 2>&3) || exit
    NET=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "IPv4 (dhcp or CIDR)" 8 58 $NET --title "IP Address" 3>&1 1>&2 2>&3) || exit
    
    if [ "$NET" != "dhcp" ]; then
      GATEWAY=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Gateway IP" 8 58 "" --title "Gateway" 3>&1 1>&2 2>&3) || exit
    fi
    
    # 6. MAC Address (For your filtering)
    MAC=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "MAC Address (Leave empty for random)" 8 58 "" --title "MAC Address" 3>&1 1>&2 2>&3) || exit
    
    # 7. VLAN
    VLAN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "VLAN Tag (Leave empty for none)" 8 58 "" --title "VLAN" 3>&1 1>&2 2>&3) || exit
  fi
}

function build_container() {
  msg_info "Updating Template Cache"
  pveam update >/dev/null
  msg_ok "Template Cache Updated"

  TEMPLATE_SEARCH="debian-12-standard"
  msg_info "Checking for Debian 12 Template"
  TEMPLATE=$(pveam list local | grep "$TEMPLATE_SEARCH" | sort | tail -n 1 | awk '{print $1}')
  
  if [ -z "$TEMPLATE" ]; then
    msg_info "Downloading Debian 12 Template"
    pveam download local debian-12-standard_12.7-1_amd64.tar.zst >/dev/null
    TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
  fi
  msg_ok "Template Ready"

  # Build Network String
  NET_STRING="name=eth0,bridge=${BRIDGE},type=veth"
  if [ ! -z "$MAC" ]; then NET_STRING="${NET_STRING},hwaddr=${MAC}"; fi
  if [ "$NET" == "dhcp" ]; then
    NET_STRING="${NET_STRING},ip=dhcp"
  else
    NET_STRING="${NET_STRING},ip=${NET},gw=${GATEWAY}"
  fi
  if [ ! -z "$VLAN" ]; then NET_STRING="${NET_STRING},tag=${VLAN}"; fi

  msg_info "Creating Container $CTID ($HOSTNAME)"
  pct create $CTID $TEMPLATE -hostname $HOSTNAME -cores $var_cpu -memory $var_ram -swap 512 -storage $STORAGE -net0 "$NET_STRING" -features nesting=1 -unprivileged $var_unprivileged >/dev/null
  pct resize $CTID rootfs ${var_disk}G >/dev/null
  msg_ok "Container Created"

  msg_info "Starting Container"
  pct start $CTID
  msg_ok "Container Started"
  
  msg_info "Waiting for Container to Initialize"
  sleep 5 # Give it a moment for IP and network
  msg_ok "Container Online"
}

function install_script() {
  msg_info "Installing Dependencies (curl, git, java, deps)"
  pct exec $CTID -- bash -c "apt-get update >/dev/null 2>&1 && apt-get install -y wget curl git gnupg software-properties-common dirmngr ca-certificates apt-transport-https procps unzip socat" >/dev/null 2>&1
  msg_ok "Dependencies Installed"

  msg_info "Adding CubeCoders Repository"
  pct exec $CTID -- bash -c "wget -q https://repo.cubecoders.com/archive.key -O /usr/share/keyrings/repo.cubecoders.com.gpg"
  pct exec $CTID -- bash -c "echo 'deb [signed-by=/usr/share/keyrings/repo.cubecoders.com.gpg] https://repo.cubecoders.com/ debian/' > /etc/apt/sources.list.d/amp.list"
  pct exec $CTID -- bash -c "apt-get update" >/dev/null 2>&1
  msg_ok "Repository Added"

  msg_info "Installing AMP Manager"
  pct exec $CTID -- bash -c "apt-get install -y ampinstmgr" >/dev/null 2>&1
  msg_ok "AMP Manager Installed"
}

# --- Main Execution ---

check_root
check_deps
header_info
variables
build_container
install_script

# --- Final Output ---
IP=$(pct exec $CTID ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been initialized!${CL}"
echo -e "${INFO}${YW} To finish the setup, you must run the wizard manually:${CL}"
echo -e "  1. Enter the container:  ${BGN}pct enter $CTID${CL}"
echo -e "  2. Switch to 'amp' user: ${BGN}su -l amp${CL}"
echo -e "  3. Run the wizard:       ${BGN}ampinstmgr quickstart${CL}"
echo -e ""
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${BGN}http://${IP}:8080${CL}"
