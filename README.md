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

To download and run the current script directly from a Bash-compatible terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-GKuba/main/post-install.sh)
```

The wizard offers these optional selections:

- **Extra Desktop Apps:** Discord, Ghostty, Obsidian, Vivaldi,
  Spotify Launcher, and Solaar.
- **CoolerControl and MSI sensor support:** CoolerControl, its daemon,
  `liquidctl`, and `nct6687d-dkms-git` from the AUR. The CoolerControl profile
  is downloaded from the DESetupLinux repository, the daemon is enabled, and
  an existing `/etc/coolercontrol/config.toml` is backed up before replacement.
- **Desktop environment items:** wallpapers and cursor themes from DESetupLinux.
  Choose either or both when prompted; skip this option on headless systems.
- **KDE Plasma configuration:** installs Oxygen and Ghostty, applies Breeze Dark
  with the Violet-Noir accent, sets Ghostty as the default terminal, and binds
  Super+X and Ctrl+Alt+T to Ghostty. It also allows legacy X11 apps to receive
  mouse-button events for PTT, enables Num Lock when Plasma starts, and configures an hourly
  all-screen wallpaper slideshow when `~/Pictures/Wallpapers` exists. When that
  folder contains PNGs, it also selects one at random for Plasma Login Manager and
  uses that image for the Plasma lock screen. These settings are applied after
  package installation and desktop asset copying.
  Selecting it automatically adds the Empty-Butterfly-Purple cursor theme if it
  was not selected under Desktop Environment Items. Existing KDE configuration
  files are backed up in `~/.dotfiles-backup/` before changes are made.
- **Noctalia shell for KDE:** installs the `noctalia` package and downloads its
  `config.toml` and Violet-Noir palette from DESetupLinux into a temporary
  staging directory. The script expands the `@HOME@` wallpaper path before
  installing the config. Existing Noctalia files are backed up; GUI overrides
  in `~/.local/state/noctalia/settings.toml` are preserved and may take precedence.
  It creates a KDE autostart entry, starts Noctalia to verify initialization,
  then removes Plasma panels through Plasma's scripting interface while keeping
  desktop containments.

Before making changes, the wizard summarizes the selected actions and asks for
confirmation. It then updates the system and installs the selected packages.
After approval, package manager confirmation prompts are skipped. `paru` is
installed from configured pacman repositories only when CoolerControl's AUR
sensor driver is selected. CachyOS provides it in its configured repositories;
on stock Arch, install `paru` first because this script does not bootstrap an
AUR helper. Font cache refresh is handled by the dotfiles setup when it installs
Fira Code.

Shell tools and the optional Zsh login-shell change are handled by the
[dotfiles setup](https://github.com/gkuba/dotfiles), which supports both Arch
and Debian-family systems. This post-install script does not install Neovim,
Fira Code, or the dotfiles-managed shell tools: Zsh, Starship, fzf, eza,
Fastfetch, Git, curl, 7zip, unzip, and iproute2.

## Run an action directly

Each package action updates the system and installs its named group. The
cooling action also installs the AUR sensor driver and applies the CoolerControl
profile. `installDesktopAssets` prompts you to choose wallpapers, cursors, or
both, then copies them into the matching user directories without removing
unrelated files. This action does not update packages.

```bash
./post-install.sh installExtraDesktopApps
./post-install.sh installCooling
./post-install.sh installDesktopAssets
```

Run the script without an action to use the full interactive wizard.

Show usage with:

```bash
./post-install.sh --help
```

The lower-level package and system helpers are internal implementation details
and are not supported command-line actions.

## Package ownership

Neovim, Fira Code, and shell tools are installed by the separate dotfiles
setup. Optional desktop and cooling packages are listed near the top of
`post-install.sh`; the MSI sensor driver is installed from the AUR only when
CoolerControl is selected.

## Dotfiles

The separate dotfiles repository and setup script are available at
[github.com/gkuba/dotfiles](https://github.com/gkuba/dotfiles). Local hosts-file
entries are managed by that dotfiles setup, not by this post-install script.
