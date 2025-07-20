#!/usr/bin/env bash
set -euo pipefail

# NixOS Bootstrap Installation Script for Colmena/Flake Management
# Usage: curl -sSL https://raw.githubusercontent.com/logandonley/nixos-scripts/main/install.sh | bash

# Configuration variables (can be overridden via environment)
: ${DISK:="/dev/sda"}
: ${HOSTNAME:="nixos"}
: ${SWAP_SIZE:="8G"}
: ${BOOT_SIZE:="512M"}
: ${USE_UEFI:="true"}
: ${TIMEZONE:="America/New_York"}
: ${LOCALE:="en_US.UTF-8"}
: ${GITHUB_USER:="logandonley"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

confirm() {
    read -p "$1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
fi

# Fetch SSH keys from GitHub
log "Fetching SSH keys from GitHub for user: $GITHUB_USER"
SSH_KEYS=$(curl -sSL "https://github.com/${GITHUB_USER}.keys") || error "Failed to fetch SSH keys from GitHub"
if [[ -z "$SSH_KEYS" ]]; then
    error "No SSH keys found for GitHub user: $GITHUB_USER"
fi
log "Found $(echo "$SSH_KEYS" | wc -l) SSH key(s)"

# Display configuration
log "NixOS Bootstrap Configuration:"
log "  Disk: $DISK"
log "  Hostname: $HOSTNAME"
log "  Boot Size: $BOOT_SIZE"
log "  Swap Size: $SWAP_SIZE"
log "  UEFI Mode: $USE_UEFI"
log "  Timezone: $TIMEZONE"
log "  Locale: $LOCALE"
log "  GitHub User: $GITHUB_USER"

# Confirm before proceeding
if ! confirm "This will DESTROY all data on $DISK. Continue?"; then
    log "Installation cancelled"
    exit 0
fi

# Partition the disk
log "Partitioning $DISK..."
if [[ "$USE_UEFI" == "true" ]]; then
    parted "$DISK" -- mklabel gpt
    parted "$DISK" -- mkpart ESP fat32 1MiB "$BOOT_SIZE"
    parted "$DISK" -- set 1 esp on
    parted "$DISK" -- mkpart primary linux-swap "$BOOT_SIZE" "$SWAP_SIZE"
    parted "$DISK" -- mkpart primary ext4 "$SWAP_SIZE" 100%
    
    BOOT_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"
else
    parted "$DISK" -- mklabel msdos
    parted "$DISK" -- mkpart primary ext4 1MiB "$BOOT_SIZE"
    parted "$DISK" -- set 1 boot on
    parted "$DISK" -- mkpart primary linux-swap "$BOOT_SIZE" "$SWAP_SIZE"
    parted "$DISK" -- mkpart primary ext4 "$SWAP_SIZE" 100%
    
    BOOT_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"
fi

# Wait for device nodes to appear
sleep 2

# Format partitions
log "Formatting partitions..."
if [[ "$USE_UEFI" == "true" ]]; then
    mkfs.fat -F 32 -n BOOT "$BOOT_PART"
else
    mkfs.ext4 -L BOOT "$BOOT_PART"
fi
mkswap -L SWAP "$SWAP_PART"
mkfs.ext4 -L NIXOS "$ROOT_PART"

# Mount partitions
log "Mounting partitions..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot
swapon "$SWAP_PART"

# Generate NixOS configuration
log "Generating NixOS configuration..."
nixos-generate-config --root /mnt

# Create minimal configuration for Colmena bootstrap
log "Creating minimal bootstrap configuration..."
cat > /mnt/etc/nixos/configuration.nix <<EOF
{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # Boot loader
  boot.loader = {
EOF

if [[ "$USE_UEFI" == "true" ]]; then
    cat >> /mnt/etc/nixos/configuration.nix <<EOF
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
EOF
else
    cat >> /mnt/etc/nixos/configuration.nix <<EOF
    grub = {
      enable = true;
      device = "$DISK";
    };
EOF
fi

cat >> /mnt/etc/nixos/configuration.nix <<EOF
  };

  # Hostname
  networking.hostName = "$HOSTNAME";

  # Time zone and locale
  time.timeZone = "$TIMEZONE";
  i18n.defaultLocale = "$LOCALE";

  # Network configuration (Hetzner Cloud specific)
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;
  
  # Enable SSH with key-only authentication
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Root SSH keys from GitHub
  users.users.root.openssh.authorizedKeys.keys = [
EOF

# Add each SSH key as a separate line
while IFS= read -r key; do
    if [[ -n "$key" ]]; then
        echo "    \"$key\"" >> /mnt/etc/nixos/configuration.nix
    fi
done <<< "$SSH_KEYS"

cat >> /mnt/etc/nixos/configuration.nix <<EOF
  ];

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # Minimal packages for bootstrap
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
  ];

  # Enable flakes for Colmena
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System version
  system.stateVersion = "25.05";
}
EOF

# Install NixOS
log "Installing NixOS (this will take a while)..."
nixos-install --no-root-passwd

# Create a marker file for Colmena
echo "$HOSTNAME" > /mnt/etc/hostname

log "Bootstrap installation complete!"
log ""
log "Next steps:"
log "  1. Reboot the server"
log "  2. SSH to root@<server-ip>"
log ""
log "The server will reboot in 10 seconds..."

sleep 10
reboot
