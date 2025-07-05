#!/bin/bash
set -euo pipefail

trap 'echo "❌ Error on line $LINENO"' ERR

ANSIBLEDIR="$HOME/ansible"
SCRIPTSDIR="$HOME/scripts"

DOTFILESREPO="https://github.com/leoric-crown/dotfiles.git"
ANSIBLEREPO="https://github.com/leoric-crown/ansible.git"
SCRIPTSREPO="https://github.com/leoric-crown/leoric-scripts.git"

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

cd "$HOME"
export PATH="$HOME/.local/bin:$PATH"

# Set dark theme
echo "[+] Setting dark theme..."

# Run in a subshell with `set +e` so errors never bubble out
(
  set +e

  # Only try gsettings if it exists and there's a session bus
  if command -v gsettings &>/dev/null && [ -S "/run/user/$(id -u)/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"

    # These may still fail, but we swallow any error
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' \
      || echo "⚠️  Could not set GTK theme, skipping"
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' \
      || echo "⚠️  Could not set color scheme, skipping"
  else
    echo "⚠️  gsettings or DBus session not available; skipping GTK dark theme"
  fi
)

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
if [ -d "$HOME/.local/share/chezmoi" ]; then
  echo "[✓] chezmoi already initialized"
else
  echo "[+] First-time init of chezmoi"
  chezmoi init "$DOTFILESREPO"
fi

# Ansible repo
echo "[+] Cloning ansible repo (branch: $ANSIBLEBRANCH)…"
if [ ! -d "$ANSIBLEDIR/.git" ]; then
  git clone --branch "$ANSIBLEBRANCH" \
    "$ANSIBLEREPO" "$ANSIBLEDIR"
else
  echo "[✓] $ANSIBLEDIR already exists, skipping clone."
fi

if [ -d "$ANSIBLEDIR/.git" ]; then
  echo "[+] Force-syncing ansible repo to origin/$ANSIBLEBRANCH…"
  git -C "$ANSIBLEDIR" fetch origin "$ANSIBLEBRANCH"
  git -C "$ANSIBLEDIR" checkout "$ANSIBLEBRANCH"
  git -C "$ANSIBLEDIR" reset --hard "origin/$ANSIBLEBRANCH"
fi

# Scripts repo
echo "[+] Cloning leoric-scripts repo (branch: $SCRIPTBRANCH)…"
if [ ! -d "$SCRIPTSDIR/.git" ]; then
  git clone --branch "$SCRIPTBRANCH" \
    "$SCRIPTSREPO" "$SCRIPTSDIR"
else
  echo "[✓] $SCRIPTSDIR already exists, skipping clone."
fi

if [ -d "$SCRIPTSDIR/.git" ]; then
  echo "[+] Force-syncing leoric-scripts repo to origin/$SCRIPTBRANCH…"
  git -C "$SCRIPTSDIR" fetch origin "$SCRIPTBRANCH"
  git -C "$SCRIPTSDIR" checkout "$SCRIPTBRANCH"
  git -C "$SCRIPTSDIR" reset --hard "origin/$SCRIPTBRANCH"
fi

# Ansible provisioning
echo "[+] Running Ansible provisioning..."
export ANSIBLE_INVENTORY_USER="${USER:-$(whoami)}"
export ANSIBLE_INVENTORY_USER_DIR="/home/$ANSIBLE_INVENTORY_USER"
ansible-playbook -i "$ANSIBLEDIR/inventory.yml" "$ANSIBLEDIR/playbook.yml" --ask-become-pass

# Helper scripts
KEY_SCRIPT="$SCRIPTSDIR/github/add-gh-ssh-keys.bash"
MNT_SHARED_SCRIPT="$SCRIPTSDIR/linux/fedora/mnt_shared.bash"
BITLOCKER_SCRIPT="$SCRIPTSDIR/linux/bitlocker/bitlocker-setup.bash"
PIHOLE_SCRIPT="$SCRIPTSDIR/linux/sync-pihole-hosts.bash"

prompt_yes_no() {
  read -rp "$1 [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]]
}

echo "[+] Running optional helper scripts..."

# Build helper lookup
declare -A HELPERS=(
  ["Add SSH keys to GitHub"]="$KEY_SCRIPT"
  ["Mount shared drive"]="$MNT_SHARED_SCRIPT"
  ["Set up BitLocker mounts"]="$BITLOCKER_SCRIPT"
  ["Sync PiHole hosts"]="$PIHOLE_SCRIPT"
)

# Declare the order we want
ORDER=(
  "Add SSH keys to GitHub"
  "Mount shared drive"
  "Set up BitLocker mounts"
  "Sync PiHole hosts"
)

# Iterate in that exact order
for desc in "${ORDER[@]}"; do
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
echo "Private Internet Access (PIA) VPN isn’t automated."
echo "You’ll need to grab the Linux installer yourself."

echo "Private Internet Access (PIA) VPN isn’t automated."
echo "You’ll need to grab the Linux installer yourself."

if prompt_yes_no "Open the PIA download page now?"; then
  if ! xdg-open "https://www.privateinternetaccess.com/download/linux-vpn"; then
    echo "❌ Could not open browser—please visit:"
    echo "    https://www.privateinternetaccess.com/download/linux-vpn"
  fi

  if prompt_yes_no "Once you've downloaded to ~/Downloads, install it now?"; then
    # Enable nullglob so the pattern disappears if nothing matches
    shopt -s nullglob
    installers=( "$HOME/Downloads"/pia-linux-*.run )
    shopt -u nullglob

    if [ ${#installers[@]} -eq 0 ]; then
      echo "❌ No PIA installer found in ~/Downloads; skipping installation."
    else
      PIA_RUN="${installers[0]}"
      echo "[+] Installing PIA from $PIA_RUN…"
      chmod +x "$PIA_RUN"
      bash "$PIA_RUN"
      echo "[+] Removing PIA installer…"
      rm "$PIA_RUN"
    fi
  else
    echo "⏭️  Skipping PIA installation."
  fi
else
  echo "⏭️  Skipping PIA download page."
fi


# Suggest GNOME extensions
echo "If running GNOME Desktop Environment, consider installing the 'Dash to Dock' and 'system-monitor-next' GNOME extensions."
echo "Dash to Dock: https://extensions.gnome.org/extension/307/dash-to-dock/"
echo "system-monitor-next: https://extensions.gnome.org/extension/3010/system-monitor-next/"
if prompt_yes_no "Do you want to open their pages?"; then
  xdg-open "https://extensions.gnome.org/extension/307/dash-to-dock/"  >/dev/null 2>&1
  xdg-open "https://extensions.gnome.org/extension/3010/system-monitor-next/"  >/dev/null 2>&1
else
  echo "⏭️  Skipping GNOME extensions pages."
fi

# Make sure fastfetch is installed
install_if_missing fastfetch

# Now safely run fastfetch
echo "[+] Displaying system info with fastfetch"
fastfetch

# Suggest NVIDIA drivers installation
echo "If you are running an NVIDIA GPU, consider installing the NVIDIA drivers using the script:"
echo "          $SCRIPTSDIR/linux/fedora/nvidia_drivers.bash (Fedora)"
echo "Or go to:"
echo "          https://www.nvidia.com/en-us/drivers/ for Windows installs"
echo
echo "For good measure, do this after rebooting and upgrading kernel."
echo

echo "✓ Done! To apply your new login shell and desktop entries, log out and back in, or run:"
echo "    exec \$SHELL -l"
echo
echo "Enjoy your new workstation!"
echo

exit 0
