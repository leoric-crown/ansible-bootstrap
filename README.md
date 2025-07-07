# 🚀 bootstrap-ansible

Provision Ubuntu/Fedora workstations in minutes using GitHub + Ansible + chezmoi.

This script automates:

- ✅ GitHub CLI login
- ✅ Cloning your private [dotfiles](https://github.com/leoric-crown/dotfiles) via chezmoi
- ✅ Cloning and applying your [ansible](https://github.com/leoric-crown/ansible) provisioning repo
- ✅ Mostly unattended workstation setup

---

## ⚡ Usage

Run this on a freshly installed Ubuntu/Fedora system:

```bash
wget -qO- "https://raw.githubusercontent.com/leoric-crown/ansible-bootstrap/main/bootstrap.bash?nocache=$(date +%s)" | bash
```
