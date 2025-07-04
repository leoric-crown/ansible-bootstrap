# 🚀 bootstrap-ansible

Provision Fedora workstations in minutes using GitHub + Ansible + chezmoi.

This script automates:

- ✅ GitHub CLI login
- ✅ Cloning your private [dotfiles](https://github.com/leoric-crown/dotfiles) via chezmoi
- ✅ Cloning and applying your [ansible](https://github.com/leoric-crown/ansible) provisioning repo
- ✅ Fully unattended workstation setup

---

## ⚡ Usage

Run this on a freshly installed Fedora system:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leoric-crown/ansible-bootstrap/main/bootstrap.sh)
```
