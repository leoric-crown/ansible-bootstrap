#!/bin/bash
set -euo pipefail

trap 'echo "❌ Error on line $LINENO"' ERR

ANSIBLEDIR="$HOME/ansible"
SCRIPTDIR="$HOME/scripts"

ANSIBLEBRANCH="main"
SCRIPTBRANCH="main"


install_if_missing() {
  local package="$1"
  # if ! dnf list --installed "$package" &>/dev/null; then
  if ! rpm -q "$package" &> /dev/null; then
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

echo "[+] Initializing chezmoi…"
if [ -d "$HOME/.local/share/chezmoi" ]; then
  echo "[✓] chezmoi already initialized"
else
  echo "[+] First‐time init of chezmoi"
  chezmoi init https://github.com/leoric-crown/dotfiles.git
fi

echo "[+] Cloning ansible repo (branch: $ANSIBLEBRANCH)..."
if [ ! -d "$ANSIBLEDIR/.git" ]; then
  git clone --branch "$ANSIBLEBRANCH" \
    https://github.com/leoric-crown/ansible.git "$ANSIBLEDIR"
else
  echo "[✓] $ANSIBLEDIR already exists, skipping clone."
fi

if [ -d "$ANSIBLEDIR/.git" ]; then
  echo "[+] Updating ansible repo..."
  git -C "$ANSIBLEDIR" checkout "$ANSIBLEBRANCH"
  git -C "$ANSIBLEDIR" pull --ff-only
fi

echo "[+] Cloning leoric-scripts repo (branch: $SCRIPTBRANCH)..."
if [ ! -d "$SCRIPTDIR/.git" ]; then
  git clone --branch "$SCRIPTBRANCH" \
    https://github.com/leoric-crown/leoric-scripts.git "$SCRIPTDIR"
else
  echo "[✓] $SCRIPTDIR already exists, skipping clone."
fi

if [ -d "$SCRIPTDIR/.git" ]; then
  echo "[+] Updating leoric-scripts repo..."
  git -C "$SCRIPTDIR" checkout "$SCRIPTBRANCH"
  git -C "$SCRIPTDIR" pull --ff-only
fi

echo "[+] Running Ansible provisioning..."
export ANSIBLE_INVENTORY_USER="${USER:-$(whoami)}"
export ANSIBLE_INVENTORY_USER_DIR="/home/$ANSIBLE_INVENTORY_USER"
ansible-playbook -i "$ANSIBLEDIR/inventory.yml" "$ANSIBLEDIR/playbook.yml" --ask-become-pass

KEY_SCRIPT="$SCRIPTDIR/github/add-gh-ssh-keys.bash"
MNT_SHARED_SCRIPT="$SCRIPTDIR/linux/fedora/mnt_shared.bash"
BITLOCKER_SCRIPT="$SCRIPTDIR/linux/bitlocker/bitlocker-setup.bash"
PIHOLE_SCRIPT="$SCRIPTDIR/linux/sync-pihole-hosts.bash"

echo "[+] Adding SSH keys to GitHub..."

if [ -f "$KEY_SCRIPT" ]; then
  chmod +x "$KEY_SCRIPT"
  bash "$KEY_SCRIPT"
else
  echo "❌  SSH key upload script not found at $KEY_SCRIPT"
fi

prompt_yes_no() {
  read -rp "$1 [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]]
}

echo "[+] Running optional helper scripts..."

# helper description and path
declare -A HELPERS=(
  ["Mount shared drive"]    = "$MNT_SHARED_SCRIPT"
  ["Set up BitLocker mounts"] = "$BITLOCKER_SCRIPT"
  ["Sync PiHole hosts"]      = "$PIHOLE_SCRIPT"
)

prompt_yes_no() {
  read -rp "$1 [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]]
}

for desc in "${!HELPERS[@]}"; do
  path="${HELPERS[$desc]}"
  if [ -f "$path" ]; then
    if prompt_yes_no "Do you want to ${desc}?"; then
      echo "[+] ${desc}..."
      chmod +x "$path"
      bash "$path"
    else
      echo "⏭️  Skipping ${desc}."
    fi
  else
    echo "⚠️  ${desc} script not found at $path — skipping"
  fi
done

# Prompt for manual PIA installation
echo "Private Internet Access (PIA) VPN is not installed automatically."
echo "You'll need to download the latest Linux installer manually."
echo "Do you want to open the page now? [y/N]"
if prompt_yes_no; then
  xdg-open "https://www.privateinternetaccess.com/download/linux-vpn" >/dev/null 2>&1 || {
    echo "Failed to open browser. Please open the following URL manually:"
    echo "   https://www.privateinternetaccess.com/download/linux-vpn"
  }
fi
echo

echo "Please download and install the appropriate .deb or .run file for your system."
echo "Do you want to open the page now? [y/N]"
if prompt_yes_no; then
  xdg-open "https://www.privateinternetaccess.com/download/linux-vpn" >/dev/null 2>&1 || {
    echo "Failed to open browser. Please open the following URL manually:"
    echo "   https://www.privateinternetaccess.com/download/linux-vpn"
  }
fi
echo

# Suggest GNOME extensions
echo "If running GNOME Desktop Environment, consider installing the 'Dash to Dock' and 'system-monitor-next' GNOME extensions."
echo "Dash to Dock: https://extensions.gnome.org/extension/307/dash-to-dock/"
echo "system-monitor-next: https://extensions.gnome.org/extension/3010/system-monitor-next/"
echo

# Suggest NVIDIA drivers installation
echo "If you are running an NVIDIA GPU, consider installing the NVIDIA drivers using the script:"
echo "For good measure, do this after rebooting."
echo "          $SCRIPTDIR/linux/fedora/nvidia_drivers.bash (Fedora)"
echo "Or go to:"
echo "          https://www.nvidia.com/en-us/drivers/ for Windows installs"
echo

echo "✓ Done! To apply your new login shell and desktop entries, log out and back in, or run:"
echo "    exec \$SHELL -l"
echo
echo "Enjoy your new workstation!"
echo

