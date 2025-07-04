#!/bin/bash
set -euo pipefail

ANSIBLEDIR="$HOME/ansible"
SCRIPTDIR="$HOME/scripts"

# Ensure gh, ansible, and chezmoi are installed
if ! command -v gh &> /dev/null; then
  echo "[+] Installing GitHub CLI..."
  sudo dnf install -y gh
fi

if ! command -v ansible-playbook &> /dev/null; then
  echo "[+] Installing Ansible..."
  sudo dnf install -y ansible
fi

if ! command -v chezmoi &> /dev/null; then
  echo "[+] Installing chezmoi..."
  curl -fsLS get.chezmoi.io | sh
fi

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

echo "[+] Cloning leoric-scripts repo..."
[ -d "$SCRIPTDIR" ] || gh repo clone leoric-crown/leoric-scripts "$SCRIPTDIR" || {
  echo "⚠️ SSH clone failed. Trying HTTPS fallback..."
  git clone https://github.com/leoric-crown/leoric-scripts.git "$SCRIPTDIR"
}

echo "[+] Running Ansible provisioning..."
cd "$ANSIBLEDIR"
ansible-playbook -i inventory.yml playbook.yml
