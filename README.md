# Arch-GKuba Post-Install

A personal post-install wizard for Arch-based systems, including CachyOS. It
installs optional package groups, copies desktop assets, can apply a KDE
Plasma configuration, install Dank Shell on Hyprland, and run a full system
update — all from an interactive terminal UI with a review step before
anything changes.

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

1. **Packages and updates** — choose the optional package groups and the full
   system update.
2. **Desktop assets** — choose wallpapers and/or cursor themes.
3. **Desktop themes** — choose the KDE Plasma configuration or Dank Shell.
   Only one desktop is set up per machine, so choosing one clears the other.
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
| System update (`pacman -Syu`) | The system update is selected |
| Pacman packages | Any package, KDE configuration or Dank Shell is selected |
| AUR packages | The MSI sensor driver or Dank Shell is selected (Dank Shell needs `qtengine`) |
| CoolerControl profile | The CoolerControl daemon is selected |
| Desktop assets | Wallpapers or cursor themes are selected |
| KDE Plasma configuration | KDE Plasma configuration is selected |
| Dank Shell | Dank Shell is selected |
| Dank Shell appearance | Dank Shell is selected |

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
-D, --dankshell    Dank Shell on Hyprland with Ghostty (DuxLabs headless installer)
-U, --update       Full system update (pacman -Syu) before anything else
-A, --all          -a, -c, -w, -u and -k (add -U for a system update; with -D, Dank Shell replaces -k)
-n, --dry-run      Run the whole wizard and install screens but change nothing
-h, --help         Show help
```

Selection options pre-select those items and open the wizard at the review
screen. Nothing runs until you confirm the plan and enter your password.
Short options can be combined:

```bash
./post-install.sh -ak      # apps + KDE, starting at review
./post-install.sh -An      # all selections with KDE, no update, dry run
./post-install.sh -ADU     # all selections with Dank Shell instead of KDE, after a system update
```

`DRY_RUN=1 ./post-install.sh` also enables a dry run. In a dry run every
command that would change the system is printed in the output frame instead of
executed; read-only checks (package status, downloads into a temporary
directory) still run so you can see what a real run would find.

## What each selection does

### Packages and the system update

The system update is off by default. Without it, package installs still sync
the package databases and upgrade the system in the same transaction
(`pacman -Syu --needed`), because syncing without upgrading would be a partial
upgrade, which Arch does not support. Packages that are already installed are
skipped, and when nothing needs installing, nothing is synced or upgraded.
With the system update selected, it runs first (`pacman -Syu`) and later
installs use `pacman -S --needed`.

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

### Dank Shell

Installs Dank Shell on Hyprland with the
[DuxLabs headless installer](https://duxlabs.dev/docs/duxinstall), the same as:

```bash
curl -fsSL https://install.duxlabs.dev | sh -s -- -c hyprland -t ghostty --all-features --replace-configs hyprland --privesc sudo -y
```

- installs Hyprland, Ghostty, Dank Shell (dms), quickshell and its other
  dependencies, plus the optional dms-greeter, dsearch and dcal
  (`--all-features`); `adw-gtk-theme` (GTK theming) and `breeze` (the Qt
  style) are installed in the pacman step, and `qtengine` (Qt theming, from
  the AUR with `paru`) in the AUR step, as Dank Shell's
  [application themes docs](https://duxlabs.dev/docs/dms/application-themes)
  require;
- replaces only the Hyprland config, after backing up the existing one; an
  existing Ghostty config is kept;
- uses the sudo session this script already holds (`--privesc sudo`), so it
  never prompts. Without the system update selected, the step syncs and
  upgrades first so duxinstall never installs onto stale package databases;
- the bootstrap script verifies the installer binary's SHA-256 checksum
  before running it, and duxinstall writes its own log to
  `/tmp/duxinstall-<timestamp>.log`.

It does not need a Plasma session. Choosing Dank Shell also selects the
wallpapers and cursor themes, which its appearance step uses.

The **Dank Shell appearance** step then applies the Violet-Noir look from
[DESetupLinux/DankShell](https://github.com/gkuba/DESetupLinux/tree/main/DankShell).
Changed files are backed up to `~/.dotfiles-backup/dankshell-<timestamp>/`
first, and running it again changes nothing that is already current:

- installs the Violet-Noir custom theme to `~/.config/dms/themes/` and selects
  it in `~/.config/dms/settings.json`, together with the
  Empty-Butterfly-Purple cursor at 32px (`cursorSettings`) and the Fit
  wallpaper mode for the desktop and login screen, keeping every other
  setting;
- writes the cursor to `~/.config/hypr/dms/cursor.lua` and `~/.Xresources`
  with the same content Dank Shell writes, because Dank Shell only writes them
  when the cursor is changed in its Settings;
- installs `~/.config/hypr/violet-noir.lua` (gradient border, glassy windows
  at 90% focused and 82% unfocused, xray blur so windows blur the wallpaper
  rather than the windows beneath), which overrides Dank Shell's Window
  opacity slider, and `~/.config/hypr/discord-ptt.lua`, which passes the side
  mouse buttons (Mouse4, Mouse5) to Discord so push-to-talk works whichever
  window is focused; both load at the end of `hyprland.lua`, after the Dank
  Shell fragments;
- turns on Dank Shell's Xray blur for its bar and popups by adding its rule
  to `~/.config/hypr/dms/layout.lua`, where Dank Shell keeps that toggle;
- in `~/.local/state/dms/session.json`, gives each connected monitor a random
  wallpaper from `~/Pictures/Wallpapers`, shown with Fit, and rotates each one
  in random order every hour (monitor names come from `/sys/class/drm`);
- themes Qt apps, Dolphin among them, with Dank Shell's colors through
  qtengine: `violet-noir.lua` sets `QT_QPA_PLATFORMTHEME` (and `_QT6`) to
  `qtengine` in place of the gtk3 passthrough, and the step points
  `~/.config/qtengine/config.json` at Dank Shell's `DankMatugen.colors`
  (starting from qtengine's example config, other keys kept). Dank Shell
  rewrites that scheme and the config on every theme change. The AUR
  package's Qt5 plugin is linked into `/usr/lib/qt/plugins`, where Arch's Qt5
  looks; `dms doctor` checks both;
- runs `dms-greeter sync --yes` so the login screen uses the same theme and
  each monitor's current wallpaper, then lets the greeter group read
  `~/Pictures/Wallpapers` with ACLs, which the sync does not cover;
- copies the Empty-Butterfly-Purple cursor to `/usr/local/share/icons`, since
  the login screen only uses a cursor theme installed system-wide;
- preselects the plain Hyprland session (not Hyprland with uwsm) on the login
  screen, unless another session was chosen there since. The sync's auto-login
  warning about `memory.json` on the first run is harmless: the group change
  only applies after logging out.

Log out (once more if the greeter group was just added) and choose the
Hyprland session to start it. If Dank Shell is already running while the step
runs, restart it so it reads the new settings.

`DESETUP_REPO=<path or URL>` makes the script use another DESetupLinux
checkout, for testing changes before they are pushed.

## After running

If a package step installed a new kernel, or the MSI sensor driver was just
built, reboot to load it. The completion screen tells you when this applies.
