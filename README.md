# Arch-GKuba Post-Install

A personal post-install script for Arch-based systems, including CachyOS. It
installs selected package groups and can configure the CoolerControl service.

Run it as your regular user. The script uses `sudo` only for system package,
service, and configuration changes. It does not need to be started from a root
shell.

## Interactive setup

Running without an action starts the wizard:

```bash
./post-install.sh
```

The wizard always includes the core package group, then asks whether to install
the listed Extra Desktop Apps and the CoolerControl/MSI sensor group. It shows a
summary and asks before applying changes. It updates the system, installs the
selected packages, ensures `paru` is installed through pacman, and refreshes the
font cache. Package manager confirmation prompts are skipped after you approve
the wizard plan. It does not clone or build paru from an external repository.

The optional groups are:

- **Extra Desktop Apps:** Discord, Ghostty, Obsidian, Vivaldi,
  Spotify Launcher, and Solaar.
- **CoolerControl and MSI sensor support:** CoolerControl, its daemon,
  `liquidctl`, and `nct6687d-dkms-git` from the AUR. The CoolerControl profile
  is downloaded from the DESetupLinux repository, the daemon is enabled, and
  an existing `/etc/coolercontrol/config.toml` is backed up before replacement.

## Run one package group

The script accepts these three public actions. Each action updates the system
and installs only its named group; the cooling action also installs the AUR
sensor driver and applies the CoolerControl profile.

```bash
./post-install.sh installCorePackages
./post-install.sh installExtraDesktopApps
./post-install.sh installCooling
```

Show usage with:

```bash
./post-install.sh --help
```

The lower-level package and system helpers are internal implementation details
and are not supported command-line actions.

## Core packages

Git, curl, unzip, 7zip, Neovim, Fastfetch, fzf, and Fira Code.

Package lists are kept near the top of `post-install.sh`, grouped by package
manager. The script currently maps the groups to pacman and the MSI sensor
package to the AUR.

## Dotfiles

The separate dotfiles repository and setup script are available at
[github.com/gkuba/dotfiles](https://github.com/gkuba/dotfiles). Local hosts-file
entries are managed by that dotfiles setup, not by this post-install script.
