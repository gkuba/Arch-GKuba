# Arch-GKuba Post-Install

A personal post-install wizard for Arch-based systems, including CachyOS. It
updates the system, installs optional package groups, copies desktop assets,
and can apply a KDE Plasma configuration — all from an interactive terminal UI
with a review step before anything changes.

Run it as your regular user. The script uses `sudo` only for system package,
service, and configuration changes; you enter your password once and the
script keeps sudo alive until the run finishes. Running it as root is refused.

## Quick start

```bash
./post-install.sh
```

To download and run the current script directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gkuba/Arch-GKuba/main/post-install.sh)
```

Try it first without changing anything:

```bash
./post-install.sh --dry-run
```

The layout fits a standard 80×24 terminal and uses up to 100 columns when
available.

## How the wizard works

1. **Packages** — choose the optional package groups.
2. **Desktop assets** — choose wallpapers and/or cursor themes.
3. **Desktop themes** — choose the KDE Plasma configuration.
4. **Review selections** — fine-tune individual packages and items. Each one
   shows whether it is already installed on this system.
5. **Review the plan** — a summary of everything the run will do. Problems
   that would make the run fail (for example, paru not available, or KDE
   configuration selected outside a Plasma session) are shown here and block
   continuing until they are fixed.
6. **Authenticate** — enter your sudo password. It is passed only to sudo
   through a pipe and is never logged or stored.

Installation then runs step by step, with live output in a frame:

| Step | Runs when |
| --- | --- |
| System update (`pacman -Syu`) | Always |
| Pacman packages | Any package or KDE configuration is selected |
| AUR packages | The MSI sensor driver is selected |
| CoolerControl profile | The CoolerControl daemon is selected |
| Desktop assets | Wallpapers or cursor themes are selected |
| KDE Plasma configuration | KDE Plasma configuration is selected |

- A step that succeeds continues automatically after a short pause.
- If the system update or pacman package step fails, the run stops there.
- If a later step fails, you can continue with the remaining steps or stop.
- **Ctrl+C** during a step finishes that step safely, then stops; it never
  interrupts pacman mid-transaction.
- Package manager prompts are skipped after you approve the plan. Commands run
  without keyboard input, so anything that would prompt fails visibly instead
  of hanging.

The completion screen lists each step's result and duration, tells you when a
reboot is needed (new kernel or newly built DKMS module), and **Ctrl+D** opens
the full log. The log path is shown on screen (under `/tmp`).

### Keys

| Key | Action |
| --- | --- |
| ↑ ↓ (or j k) | Move / scroll |
| ← → (or h l) | Switch columns on the review screen |
| Space | Toggle the highlighted item |
| G | Toggle the whole group (review screen) |
| A / N | Select all / none |
| Enter | Next / confirm |
| B or Backspace | Back |
| Esc | Quit (Back on the password screen) |
| Ctrl+D | Full log (after steps run) |

## Options

```text
-a, --apps         Extra desktop applications
-c, --cooling      CoolerControl, liquidctl, and the MSI nct6687d sensor driver (AUR)
-w, --wallpapers   Copy DESetupLinux wallpapers into ~/Pictures/Wallpapers
-u, --cursors      Copy DESetupLinux cursor themes into ~/.icons
-k, --kde          KDE Plasma configuration
-A, --all          Everything above
-n, --dry-run      Run the whole wizard and install screens but change nothing
-h, --help         Show help
```

Selection options pre-select those items and open the wizard at the review
screen. Nothing runs until you confirm the plan and enter your password.
Short options can be combined:

```bash
./post-install.sh -ak      # apps + KDE, starting at review
./post-install.sh -An      # everything, dry run
```

`DRY_RUN=1 ./post-install.sh` also enables a dry run. In a dry run every
command that would change the system is printed in the output frame instead of
executed; read-only checks (package status, downloads into a temporary
directory) still run so you can see what a real run would find.

## What each selection does

### Extra desktop applications

Installs Discord, Ghostty, Obsidian, Vivaldi, Spotify Launcher, and Solaar
from your configured pacman repositories. Each can be deselected on the review
screen.

### CoolerControl and MSI sensor support

Installs `coolercontrol`, `coolercontrold`, and `liquidctl` with pacman, and
the `nct6687d-dkms-git` sensor driver from the AUR with `paru`.

- If `paru` is not installed, it is installed from your configured
  repositories (CachyOS provides it). On stock Arch, install `paru` first —
  the script does not bootstrap an AUR helper, and the plan screen will tell
  you if it is missing.
- Matching headers are installed for every kernel package present so DKMS can
  build the sensor module.
- When the daemon is selected, the CoolerControl profile is downloaded from
  DESetupLinux and checked before use, an existing
  `/etc/coolercontrol/config.toml` is backed up, and `coolercontrold` is
  enabled and started.

### Desktop assets

Downloads DESetupLinux and copies wallpapers into `~/Pictures/Wallpapers`
and/or cursor themes (including Empty-Butterfly-Purple) into `~/.icons`.
Unrelated files already in those folders are left alone.

### KDE Plasma configuration

Must run inside an active KDE Plasma session. It:

- applies the Oxygen global theme, widget style, Plasma style, window
  decoration, and lock screen theme;
- applies Breeze Dark with the Violet-Noir accent (`#453078`) and verifies
  both persisted;
- sets Ghostty as the default terminal and binds Super+X and Ctrl+Alt+T to it
  (Ghostty and Oxygen are installed automatically when needed);
- lets legacy X11 apps receive mouse-button events for push-to-talk and turns
  Num Lock on at login;
- applies the Empty-Butterfly-Purple cursor at 48px when cursor themes are
  selected;
- when `~/Pictures/Wallpapers` exists, configures an hourly all-screen
  wallpaper slideshow, and picks a random PNG for the Plasma Login Manager and
  lock screen.

Existing KDE configuration files (and `/etc/plasmalogin.conf`) are backed up to
`~/.dotfiles-backup/kde-appearance-<timestamp>/` first. Every setting write is
checked; the step reports how many failed, if any. Log out and back in to see
every change.

## After running

If the system update installed a new kernel, or the MSI sensor driver was just
built, reboot to load it. The completion screen tells you when this applies.
