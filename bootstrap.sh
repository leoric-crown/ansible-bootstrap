#!/bin/bash
set -euo pipefail

ANSIBLEDIR="$HOME/ansible"

# Ensure GitHub CLI is authenticated
echo "[+] Checking GitHub authentication..."
gh auth status >/dev/null 2>&1 || gh auth login

echo "[+] Cloning dotfiles with chezmoi..."
chezmoi init --apply git@github.com:leoric-crown/dotfiles.git || {
  echo "⚠️ SSH clone failed. Trying HTTPS fallback..."
  chezmoi init --apply https://github.com/leoric-crown/dotfiles.git
}

echo "[+] Cloning ansible repo..."
[ -d "$ANSIBLEDIR" ] || gh repo clone leoric-crown/ansible "$ANSIBLEDIR" || {
  echo "⚠️ SSH clone failed. Trying HTTPS fallback..."
  git clone https://github.com/leoric-crown/ansible.git "$ANSIBLEDIR"
}

echo "[+] Running Ansible provisioning..."
cd "$ANSIBLEDIR"
ansible-playbook -i inventory.yml playbook.yml
