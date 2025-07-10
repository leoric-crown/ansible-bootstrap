#!/bin/bash
set -euo pipefail

SKIP_ANSIBLE=0

# Parse args
for arg in "$@"; do
  case "$arg" in
    --skip-ansible|-s)
      SKIP_ANSIBLE=1
      shift
      ;;
    *)
      echo "Unknown argument: $arg"
      exit 1
      ;;
  esac
done

trap 'echo "❌ Error on line $LINENO"' ERR

# Cache sudo credentials at script start
echo "[+] Caching sudo credentials..."
sudo -v

# Detach the keepalive loop’s stdin *and* capture its PID
while true; do sudo -n true; sleep 60; done \
  2>/dev/null </dev/null &
SUDO_LOOP_PID=$!

# Ensure the loop is killed on script exit
trap 'kill "$SUDO_LOOP_PID"' EXIT

ANSIBLEDIR="$HOME/ansible"
SCRIPTSDIR="$HOME/scripts"

SSH_KEY_PATH="$HOME/.ssh/id_leoric_ed25519_github"
SSH_PUB_PATH="${SSH_KEY_PATH}.pub"

DOTFILESREPO="git@github.com:leoric-crown/dotfiles.git"
ANSIBLEREPO="git@github.com:leoric-crown/ansible.git"
SCRIPTSREPO="git@github.com:leoric-crown/leoric-scripts.git"

ANSIBLEBRANCH="main"
SCRIPTBRANCH="main"

# Detect OS
OS_TYPE="$(uname -s)"
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""

sync_repo() {
  local url=$1 dir=$2 branch=$3
  if [ ! -d "$dir/.git" ]; then
    git clone --depth 1 --branch "$branch" "$url" "$dir"
  else
    git -C "$dir" fetch origin "$branch"
    git -C "$dir" checkout "$branch"
    git -C "$dir" reset --hard "origin/$branch"
  fi
}

prompt_yes_no() {
  read -rp "$1 [y/N] " ans < /dev/tty
  [[ $ans =~ ^[Yy]$ ]]
}

if [[ "$OS_TYPE" == "Darwin" ]]; then
  # macOS
  if ! command -v brew &>/dev/null; then
    echo "[+] Homebrew not found; installing..."
    /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH (Apple Silicon vs Intel)
    eval "\$($(brew --prefix)/bin/brew shellenv)"
  fi
  PACKAGE_MANAGER="brew"
  INSTALL_CMD="brew install"
  UPDATE_CMD="brew update"
elif [[ -f /etc/os-release ]]; then
  # Linux: detect package manager
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      PACKAGE_MANAGER="apt"
      INSTALL_CMD="sudo apt-get install -y"
      UPDATE_CMD="sudo apt-get update"
      ;;
    fedora|rhel|centos)
      PACKAGE_MANAGER="dnf"
      INSTALL_CMD="sudo dnf install -y"
      UPDATE_CMD="sudo dnf makecache --refresh"
      ;;
    arch)
      PACKAGE_MANAGER="pacman"
      INSTALL_CMD="sudo pacman -S --noconfirm"
      UPDATE_CMD="sudo pacman -Sy"
      ;;
    *)(
      echo "❌ Unsupported Linux distribution: $ID" >&2
      exit 1
      )
      ;;
  esac
else
  echo "❌ Unsupported OS: $OS_TYPE" >&2
  echo "Supported OS: macOS, Linux (Fedora, Ubuntu, Debian, Arch)"
  exit 1
fi

echo "🚀 Starting bootstrap process..."

echo "Found package manager: $PACKAGE_MANAGER"
echo "Found install command: $INSTALL_CMD"
echo "Found update command: $UPDATE_CMD"

echo "[+] Updating package list..."
$UPDATE_CMD

install_if_missing() {
  local pkg="$1"
  if ! command -v "$pkg" &>/dev/null; then
    echo "[+] Installing $pkg..."
    $INSTALL_CMD "$pkg"
  else
    echo "[✓] $pkg already installed."
  fi
}

# Ensure required commands are installed
install_if_missing git
install_if_missing curl
install_if_missing sudo

for cmd in git curl sudo; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ $cmd is required but not installed. Please install it manually first."
    exit 1
  fi
done

cd "$HOME"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"

# Run in a subshell with `set +e` so errors never bubble out
(
  set +e

  # Only try gsettings if it exists and there's a session bus
  if command -v gsettings &>/dev/null && [ -S "/run/user/$(id -u)/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    echo "[+] Setting dark theme..."
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  fi
)

# Ensure Ansible is installed
install_if_missing ansible

# Install GitHub CLI (gh)
install_if_missing gh

# Ensure chezmoi is installed
echo "[+] Ensuring chezmoi is installed/up-to-date..."
curl -fsLS get.chezmoi.io | sh


echo "[+] Setting up SSH key for GitHub..."

# Generate the SSH key if it doesn't exist
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[+] Generating new SSH key at $SSH_KEY_PATH..."
  ssh-keygen -t ed25519 -C "leoric@$(hostname)" -f "$SSH_KEY_PATH" -N ""
else
  echo "[✓] SSH key already exists at $SSH_KEY_PATH"
fi

# Add to ssh-agent
if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
  echo "[+] Starting new ssh-agent..."
  eval "$(ssh-agent -s)" >/dev/null
fi

# Add the key if not already loaded
if ! ssh-add -l 2>/dev/null | grep -q "$SSH_KEY_PATH"; then
  echo "[+] Adding SSH key to agent: $SSH_KEY_PATH"
  ssh-add "$SSH_KEY_PATH"
else
  echo "[✓] SSH key already loaded in agent"
fi

# Ensure SSH config for GitHub uses this key
SSH_CONFIG_ENTRY=$(cat <<EOF
Host github.com
  HostName github.com
  User git
  IdentityFile $SSH_KEY_PATH
  IdentitiesOnly yes
EOF
)

mkdir -p ~/.ssh
touch ~/.ssh/config
chmod 600 ~/.ssh/config
if ! grep -q "$SSH_KEY_PATH" ~/.ssh/config 2>/dev/null; then
  echo "[+] Adding SSH config for github.com..."
  echo "$SSH_CONFIG_ENTRY" >> ~/.ssh/config
else
  echo "[✓] SSH config for github.com already set"
fi
echo "[✓] SSH config for github.com set. Key fingerprint: $(ssh-keygen -lf "$SSH_PUB_PATH")"

# Ensure Git is using SSH
git config --global url."git@github.com:".insteadOf "https://github.com/"

# Ensure GitHub CLI is authenticated
echo "[+] Checking GitHub authentication..."
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol ssh --web

# Add GitHub to known_hosts
if command -v ssh-keyscan >/dev/null 2>&1; then
  grep -q github.com ~/.ssh/known_hosts 2>/dev/null || ssh-keyscan github.com >> ~/.ssh/known_hosts
else
  echo "⚠️  ssh-keyscan not available; skipping GitHub host key preloading"
fi

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
  git clone --depth 1 --branch "$ANSIBLEBRANCH" \
    "$ANSIBLEREPO" "$ANSIBLEDIR"
else
  echo "[✓] $ANSIBLEDIR already exists, skipping clone."
fi

# Scripts repo
echo "[+] Cloning leoric-scripts repo (branch: $SCRIPTBRANCH)…"
if [ ! -d "$SCRIPTSDIR/.git" ]; then
  git clone --depth 1 --branch "$SCRIPTBRANCH" \
    "$SCRIPTSREPO" "$SCRIPTSDIR"
else
  echo "[✓] $SCRIPTSDIR already exists, skipping clone."
fi

if [ -d "$ANSIBLEDIR/.git" ]; then
  sync_repo "$ANSIBLEREPO" "$ANSIBLEDIR" "$ANSIBLEBRANCH"
fi
if [ -d "$SCRIPTSDIR/.git" ]; then
  sync_repo "$SCRIPTSREPO" "$SCRIPTSDIR" "$SCRIPTBRANCH"
fi

# Ansible provisioning
if [[ "$SKIP_ANSIBLE" -eq 0 ]]; then
  if [[ "$OS_TYPE" == "Linux" ]]; then
    echo "[+] Running Ansible provisioning..."
    export ANSIBLE_INVENTORY_USER="${USER:-$(whoami)}"
    export ANSIBLE_INVENTORY_USER_DIR="$HOME"
    ansible-playbook -i "$ANSIBLEDIR/inventory.yml" "$ANSIBLEDIR/playbook.yml" --ask-become-pass
  else
    echo "[✓] Skipping Ansible provisioning (not Fedora/Linux, Ubuntu and macOS not tested yet)"
  fi
else
  echo "⏭️ Skipping Ansible provisioning (skipped by user)"
fi

# Apply chezmoi config
echo "[+] Running chezmoi config..."
# Revert the git config change we made above
# Ansible set our config up so it sources the chezmoi file
git config --global --unset url."git@github.com:".insteadOf
chezmoi apply

# Helper scripts
GH_KEYS_SCRIPT="$SCRIPTSDIR/ssh/add-gh-ssh-keys.bash"
PI_KEYS_SCRIPT="$SCRIPTSDIR/ssh/add-pi-ssh-keys.bash"
PIHOLE_SCRIPT="$SCRIPTSDIR/linux/sync-pihole-hosts.bash"
MNT_SHARED_SCRIPT="$SCRIPTSDIR/linux/fedora/mnt_shared.bash"
BITLOCKER_SCRIPT="$SCRIPTSDIR/linux/bitlocker/bitlocker-setup.bash"
# BRIDGE_SCRIPT="$SCRIPTSDIR/linux/fedora/br0.bash" # TODO

echo "[+] Running optional helper scripts..."

# Build helper lookup
declare -A HELPERS=(
  ["Add SSH keys to GitHub"]="$GH_KEYS_SCRIPT"
  ["Add SSH keys to Pis"]="$PI_KEYS_SCRIPT"
  ["Sync PiHole hosts"]="$PIHOLE_SCRIPT"
  ["Mount Samba share"]="$MNT_SHARED_SCRIPT"
  ["Set up BitLocker mounts"]="$BITLOCKER_SCRIPT"
)
# ["Set up br0 bridge interface"]="$BRIDGE_SCRIPT" # TODO


# Declare the order we want
ORDER=(
  "Add SSH keys to GitHub"
  "Add SSH keys to Pis"
  "Sync PiHole hosts"
  "Mount Samba share"
  "Set up BitLocker mounts"
)
# "Set up br0 bridge interface" # TODO


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
echo "Private Internet Access (PIA) VPN isn't automated."
echo "You'll need to grab the installer yourself."

# Open the URL and background it
nohup xdg-open "https://www.privateinternetaccess.com/download" &>/dev/null &
sleep 0.3
nohup xdg-open "https://www.privateinternetaccess.com/download/linux-vpn" &>/dev/null &

# Prompt user to download
echo "[+] Please download the PIA installer to ~/Downloads and press Enter to continue, or type 'N' to skip installation:"
read -rp "..." response < /dev/tty

# Skip if response starts with N/n
if [[ "$response" =~ ^[Nn] ]]; then
  echo "[⏩] Skipping PIA installation."
else
  # Find and run the installer
  shopt -s nullglob
  installers=( "$HOME/Downloads"/pia-linux-*.run )
  shopt -u nullglob
  if (( ${#installers[@]} )); then
    echo "[+] Installing PIA from ${installers[0]}…"
    chmod +x "${installers[0]}"
    set +e  # Allow the script to continue even if the installer fails
    bash "${installers[0]}"
    install_exit=$?
    set -e
    if [[ $install_exit -ne 0 ]]; then
      echo "⚠️  PIA installer exited with code $install_exit (continuing anyway)"
    fi
    rm "${installers[0]}"
  else
    echo "❌ No PIA installer found—make sure you downloaded it to ~/Downloads"
  fi
fi
echo

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
echo

if [[ "$PACKAGE_MANAGER" != "apt" ]]; then
  # Make sure fastfetch is installed
  install_if_missing fastfetch
  echo "[+] Displaying system info with fastfetch"
  fastfetch
  echo
else
  # Fall back to neofetch
  install_if_missing neofetch
  echo "[+] Displaying system info with neofetch"
  neofetch
  echo
fi


# Suggest NVIDIA drivers installation
echo "If you are running an NVIDIA GPU, consider installing the NVIDIA drivers using the script:"
echo "          $SCRIPTSDIR/linux/fedora/nvidia_drivers.bash (only tested on Fedora 42+)"
echo "Or go to:"
echo "          https://www.nvidia.com/en-us/drivers/ for Windows installs"
echo
echo "For good measure, do this after rebooting and upgrading kernel."
echo

# Suggest COSMIC DE installation
echo "If you want to install Cosmic DE on Fedora 41+, use:"
echo "		sudo dnf install @cosmic-desktop-environment"
echo "See https://copr.fedorainfracloud.org/coprs/ryanabx/cosmic-epoch/ for more details"
echo

echo "✓ Done! To apply your new login shell and desktop entries, log out and back in (or reboot)."
echo
echo "Enjoy your new workstation!"
echo

exit 0
