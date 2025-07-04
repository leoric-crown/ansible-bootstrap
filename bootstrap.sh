#!/bin/bash
set -euo pipefail

ANSIBLEDIR="$HOME/ansible"
SCRIPTDIR="$HOME/scripts"

ANSIBLEBRANCH="main"
SCRIPTBRANCH="main"


install_if_missing() {
  local package="$1"
  if ! dnf list --installed "$package" &>/dev/null; then
    echo "[+] Installing $package..."
    sudo dnf install -y "$package"
  else
    echo "[✓] $package is already installed."
  fi
}

echo "🚀 Starting bootstrap process..."

# Ensure Ansible is installed
install_if_missing ansible
# Ensure GitHub CLI is installed
install_if_missing gh
# Ensure chezmoi is installed
echo "[+] Ensuring chezmoi is installed/up-to-date..."
curl -fsLS get.chezmoi.io | sh


# Ensure GitHub CLI is authenticated
echo "[+] Checking GitHub authentication..."
gh auth status >/dev/null 2>&1 || gh auth login

echo "[+] Initializing chezmoi..."
chezmoi init https://github.com/leoric-crown/dotfiles.git

echo "[+] Cloning ansible repo..."
[ -d "$ANSIBLEDIR" ] || gh repo clone leoric-crown/ansible "$ANSIBLEDIR" || {
  echo "⚠️ SSH clone failed. Trying HTTPS fallback..."
  git clone https://github.com/leoric-crown/ansible.git "$ANSIBLEDIR"
}

if [ -d "$ANSIBLEDIR/.git" ]; then
  echo "[+] Updating ansible repo..."
  git -C "$ANSIBLEDIR" checkout "$ANSIBLEBRANCH"
  git -C "$ANSIBLEDIR" pull --ff-only
fi

echo "[+] Cloning leoric-scripts repo..."
[ -d "$SCRIPTDIR" ] || gh repo clone leoric-crown/leoric-scripts "$SCRIPTDIR" || {
  echo "⚠️ SSH clone failed. Trying HTTPS fallback..."
  git clone https://github.com/leoric-crown/leoric-scripts.git "$SCRIPTDIR"
}

if [ -d "$SCRIPTDIR/.git" ]; then
  echo "[+] Updating leoric-scripts repo..."
  git -C "$SCRIPTDIR" checkout "$SCRIPTBRANCH"
  git -C "$SCRIPTDIR" pull --ff-only
fi

echo "[+] Running Ansible provisioning..."
export ANSIBLE_INVENTORY_USER="${USER:-$(whoami)}"
export ANSIBLE_INVENTORY_USER_DIR="/home/$ANSIBLE_INVENTORY_USER"
ansible-playbook -i "$ANSIBLEDIR/inventory.yml" "$ANSIBLEDIR/playbook.yml" --ask-become-pass

echo "[+] Adding SSH keys to GitHub..."
chmod +x "$SCRIPTDIR/github/add-gh-ssh-keys.bash"
bash "$SCRIPTDIR/github/add-gh-ssh-keys.bash"

echo "Do you want to mount the shared drive? [y/N]"
read -r response
if [[ "$response" == [yY] ]]; then
  echo "[+] Mounting shared drive..."
  chmod +x "$SCRIPTDIR/linux/fedora/mnt_shared.bash"
  bash "$SCRIPTDIR/linux/fedora/mnt_shared.bash"
fi

echo "Do you want to set up bitlocker mounts on dual boot machine with Win10/11? [y/N]"
read -r response
if [[ "$response" == [yY] ]]; then
  echo "[+] Setting up bitlocker mounts..."
  chmod +x "$SCRIPTDIR/linux/bitlocker/bitlocker-setup.bash"
  bash "$SCRIPTDIR/linux/bitlocker/bitlocker-setup.bash"
fi

echo "Do you want to sync PiHole hosts? [y/N]"
read -r response
if [[ "$response" == [yY] ]]; then
  echo "[+] Syncing PiHole hosts..."
  chmod +x "$SCRIPTDIR/linux/sync-pihole-hosts.bash"
  bash "$SCRIPTDIR/linux/sync-pihole-hosts.bash"
fi