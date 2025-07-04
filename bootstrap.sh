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
chezmoi init git@github.com:leoric-crown/dotfiles.git || {
  echo "⚠️ SSH init failed. Trying HTTPS fallback..."
  chezmoi init https://github.com/leoric-crown/dotfiles.git
}

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
export ANSIBLE_INVENTORY_USER_DIR="${HOME:-/home/$ANSIBLE_INVENTORY_USER}"
ansible-playbook -i "$ANSIBLEDIR/inventory.yml" "$ANSIBLEDIR/playbook.yml" --ask-become-pass
