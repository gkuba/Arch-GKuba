#!/usr/bin/env bash
set -Eeuo pipefail

# Colors (kept individually editable)
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# Package groups (manager-specific to support future distro mappings)
PACMAN_EXTRA_DESKTOP_PACKAGES=(discord ghostty obsidian vivaldi spotify-launcher solaar)
PACMAN_COOLING_PACKAGES=(coolercontrol coolercontrold liquidctl)
PACMAN_NOCTALIA_PACKAGES=(noctalia)
AUR_COOLING_PACKAGES=(nct6687d-dkms-git)
DESETUP_REPO='https://github.com/gkuba/DESetupLinux.git'
COOLERCONTROL_CONFIG_URL='https://raw.githubusercontent.com/gkuba/DESetupLinux/refs/heads/main/coolercontrol/config.toml'
DEFAULT_INSTALL_EXTRA=no
DEFAULT_INSTALL_COOLING=no
DEFAULT_INSTALL_DESKTOP_ASSETS=no

# Help and supported public actions
usage() {
  cat <<EOF
Arch Post-Install Script
Usage: $(basename "$0") [installExtraDesktopApps|installCooling|installDesktopAssets|installNoctaliaShellForKde|--help]

No argument runs the interactive wizard. Direct actions run only the selected
task; package actions update the system first. Run as your user; sudo is
requested as needed.

  installExtraDesktopApps   Install optional desktop applications
  installCooling            Install CoolerControl and MSI sensor support
  installDesktopAssets      Copy selected wallpapers and/or cursor themes
  installNoctaliaShellForKde Install and configure Noctalia in the active KDE session
EOF
}

# Disable escape sequences when color output is unavailable or explicitly disabled.
configureColors() {
  if [[ ! -t 1 || -n "${NO_COLOR:-}" || "${TERM:-dumb}" == dumb ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    MAGENTA=''
    CYAN=''
    BOLD=''
    DIM=''
    RESET=''
  fi
}
configureColors

# Shared UI and validation helpers
info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
success() { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
error() { printf '%s[ERR ]%s %s\n' "$RED" "$RESET" "$*" >&2; }
is_tty() { [[ -t 0 && -t 1 && -n "${TERM:-}" && "${TERM:-dumb}" != dumb ]]; }
assert_prerequisites() {
  (( EUID != 0 )) || { error 'Run as your normal user; sudo is used only when needed.'; return 1; }
  command -v sudo >/dev/null || { error 'sudo is required.'; return 1; }
  [[ -r /etc/arch-release ]] || { error 'Arch-based systems only.'; return 1; }
}
draw_screen() {
  local active="$1" item done mark color title='Arch Post-Install Script' width=68 left_pad right_pad
  shift
  left_pad=$(((width - ${#title}) / 2))
  right_pad=$((width - ${#title} - left_pad))
  printf '\033[H\033[2J%s%s╭' "$MAGENTA" "$BOLD"
  printf '─%.0s' $(seq 1 "$width")
  printf '╮%s\n%s%s│%*s%s%*s│%s\n%s%s╰' \
    "$RESET" "$MAGENTA" "$BOLD" "$left_pad" '' "$title" "$right_pad" '' "$RESET" "$MAGENTA" "$BOLD"
  printf '─%.0s' $(seq 1 "$width")
  printf '╯%s\n\n' "$RESET"
  for item in 'Gathering Information' 'Updating System' 'Installing Pacman Packages' 'Installing AUR Packages' 'Applying CoolerControl Config' 'Installing Desktop Assets' 'Applying KDE Plasma Config' 'Installing Noctalia shell for KDE' 'Finalizing'; do
    mark='○'; color="$DIM"
    if [[ "$item" == "$active" ]]; then mark='●'; color="$CYAN$BOLD"; else
      for done in "$@"; do [[ "$item" == "$done" ]] && { mark='✓'; color="$GREEN"; break; }; done
    fi
    printf '  %s%s %s%s\n' "$color" "$mark" "$item" "$RESET"
  done
  printf '\n'
}
mark_setup_complete_in_place() {
  local item done row=5 output_row=14
  is_tty || return 0
  for item in 'Gathering Information' 'Updating System' 'Installing Pacman Packages' 'Installing AUR Packages' 'Applying CoolerControl Config' 'Installing Desktop Assets' 'Applying KDE Plasma Config' 'Installing Noctalia shell for KDE' 'Finalizing'; do
    for done in "$@"; do
      if [[ "$item" == "$done" ]]; then
        printf '\033[%d;1H\033[2K  %s✓ %s%s' "$row" "$GREEN" "$item" "$RESET"
        break
      fi
    done
    row=$((row + 1))
  done
  # Clear the last stage's completion/progress rows before writing final status.
  printf '\033[%d;1H\033[2K\033[%d;1H\033[2K\033[%d;1H' \
    "$output_row" "$((output_row + 1))" "$output_row"
}
panel() {
  local title="$1" line width=68
  shift
  (( ${#title} + 4 > width )) && width=$((${#title} + 4))
  printf '%s┌─ %s ' "$CYAN" "$title"; printf '─%.0s' $(seq 1 $((width-${#title}-3))); printf '┐%s\n' "$RESET"
  for line in "$@"; do printf '%s│%s %s\n' "$CYAN" "$RESET" "$line"; done
  printf '%s└' "$CYAN"; printf '─%.0s' $(seq 1 "$width"); printf '┘%s\n' "$RESET"
}
append_wrapped_packages() {
  local output_name="$1" line='' item separator=' · ' max_width=64
  shift
  local -n output_ref="$output_name"
  for item in "$@"; do
    if [[ -z "$line" ]]; then
      line="  $item"
    elif (( ${#line} + ${#separator} + ${#item} <= max_width )); then
      line+="$separator$item"
    else
      output_ref+=("$line")
      line="  $item"
    fi
  done
  [[ -n "$line" ]] && output_ref+=("$line")
}
wizard_panel() {
  if is_tty; then printf '\033[14;1H\033[J'; fi
  panel "$@"
}
ask_yes_no() {
  local prompt="$1" default="$2" answer suffix='[y/N]'
  [[ "$default" == yes ]] && suffix='[Y/n]'
  while true; do
    read -r -p "$prompt $suffix " answer || return 1
    case "${answer,,}" in y|yes) return 0;; n|no) return 1;; '') [[ "$default" == yes ]] && return 0 || return 1;; *) printf 'Please answer y or n.\n';; esac
  done
}
confirm_plan() { local answer; read -r -p 'Continue with this plan? [Y/n] ' answer || return 1; [[ "${answer,,}" != n && "${answer,,}" != no ]]; }
spinner() {
  local label="$1" chars='|/-\\' i=0 pid rc
  shift
  if ! is_tty; then "$@"; return; fi
  "$@" & pid=$!
  while kill -0 "$pid" 2>/dev/null; do printf '\r  %s%s%s %s' "$CYAN" "${chars:i++%4:1}" "$RESET" "$label"; sleep .12; done
  if wait "$pid"; then rc=0; else rc=$?; fi
  printf '\r\033[K'; return "$rc"
}
on_error() { local rc=$? line=${1:-?}; is_tty && printf '\033[?25h\n'; error "Stopped at line $line (exit $rc). See the preceding error."; exit "$rc"; }
trap 'on_error $LINENO' ERR

# Internal workflow helpers
checkUpdates() { info 'Updating system packages.'; sudo pacman -Syu --noconfirm; }
run_in_progress_area() {
  if ! is_tty; then "$@"; return; fi
  local rows rc=0
  rows=$(tput lines 2>/dev/null || printf '24')
  if (( rows < 18 )); then "$@"; return; fi
  printf '\033[14;%sr\033[14;1H' "$rows"
  "$@" || rc=$?
  # Keep pacman/sudo diagnostics visible if a stage fails. On success the next
  # draw_screen refreshes the display before beginning the following stage.
  printf '\033[s\033[r\033[u'
  return "$rc"
}
installPackages() { local -n group="$1"; ((${#group[@]})) && sudo pacman -S --needed --noconfirm "${group[@]}"; }
ensureParu() {
  command -v paru >/dev/null 2>&1 && { success 'paru is already installed.'; return; }
  info 'Installing paru from the configured pacman repositories.'
  sudo pacman -S --needed --noconfirm paru
  command -v paru >/dev/null 2>&1 || { error 'paru installation did not complete.'; return 1; }
  success 'paru is ready.'
}
installAurPackages() {
  ((${#@})) || return 0
  ensureParu || return 1
  paru -S --needed --noconfirm "$@"
}
applyCoolerControlConfig() {
  local tmp backup
  tmp=$(mktemp "${TMPDIR:-/tmp}/coolercontrol.XXXXXXXX")
  if ! curl -fsSL "$COOLERCONTROL_CONFIG_URL" -o "$tmp" || ! grep -qE '^[[:space:]]*\[' "$tmp"; then
    rm -f -- "$tmp"; error 'Could not fetch a valid CoolerControl TOML profile.'; return 1
  fi
  sudo systemctl stop coolercontrold 2>/dev/null || true
  sudo install -d -m 0755 /etc/coolercontrol
  if sudo test -e /etc/coolercontrol/config.toml; then
    backup="/etc/coolercontrol/config.toml.backup.$(date +%Y%m%d-%H%M%S)"
    sudo cp -a /etc/coolercontrol/config.toml "$backup"
    info "Backed up existing profile to $backup"
  fi
  sudo install -m 0644 "$tmp" /etc/coolercontrol/config.toml
  rm -f -- "$tmp"
  sudo systemctl enable --now coolercontrold
  success 'CoolerControl profile applied; daemon enabled.'
}
run_group() {
  local name="$1" array="$2"
  assert_prerequisites
  checkUpdates
  installPackages "$array"
  if [[ "$name" == cooling ]]; then installAurPackages "${AUR_COOLING_PACKAGES[@]}"; applyCoolerControlConfig; fi
  success "$name package group complete."
}
installDesktopAssets() {
  local scratch choice wallpaper
  if [[ "${WANT_WALLPAPERS:-no}" != yes && "${WANT_CURSORS:-no}" != yes ]]; then
    while true; do
      read -r -p 'Choose [w]allpapers, [c]ursor themes, or [b]oth: ' choice || return 1
      case "${choice,,}" in
        w|wallpapers) WANT_WALLPAPERS=yes; break ;;
        c|cursors|cursor) WANT_CURSORS=yes; break ;;
        b|both) WANT_WALLPAPERS=yes; WANT_CURSORS=yes; break ;;
        *) warn "Enter 'w', 'c', or 'b'." ;;
      esac
    done
  fi
  assert_prerequisites
  command -v git >/dev/null 2>&1 || { error 'git is required to download desktop assets.'; return 1; }
  [[ "$WANT_WALLPAPERS" == yes || "$WANT_CURSORS" == yes ]] || { error 'Select wallpapers, cursor themes, or both first.'; return 2; }
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/desktop-assets.XXXXXXXX")
  if ! git clone --depth=1 "$DESETUP_REPO" "$scratch/DESetupLinux"; then
    rm -rf -- "$scratch"; error 'Could not download DESetupLinux assets.'; return 1
  fi
  if [[ "$WANT_WALLPAPERS" == yes ]]; then
    [[ -d "$scratch/DESetupLinux/Wallpapers" ]] || { rm -rf -- "$scratch"; error 'DESetupLinux Wallpapers directory not found.'; return 1; }
    mkdir -p "$HOME/Pictures/Wallpapers"
    for wallpaper in "$scratch/DESetupLinux/Wallpapers"/* "$scratch/DESetupLinux/Wallpapers"/.[!.]* "$scratch/DESetupLinux/Wallpapers"/..?*; do
      [[ -e "$wallpaper" || -L "$wallpaper" ]] || continue
      [[ "${wallpaper##*/}" == Archive ]] && continue
      cp -a -- "$wallpaper" "$HOME/Pictures/Wallpapers/"
    done
  fi
  if [[ "$WANT_CURSORS" == yes ]]; then
    [[ -d "$scratch/DESetupLinux/.icons" ]] || { rm -rf -- "$scratch"; error 'DESetupLinux .icons directory not found.'; return 1; }
    mkdir -p "$HOME/.icons"
    cp -a "$scratch/DESetupLinux/.icons/." "$HOME/.icons/"
  fi
  rm -rf -- "$scratch"
  success 'Selected desktop assets copied; unrelated destination files were retained.'
}
configureNoctaliaShellForKde() {
  local scratch staged_config staged_palette config_target palette_target override_file autostart_target backup_dir
  local has_override=no

  assert_prerequisites
  command -v git >/dev/null 2>&1 || { error 'git is required to download the Noctalia configuration.'; return 1; }
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/noctalia-setup.XXXXXXXX")
  if ! git clone --depth=1 "$DESETUP_REPO" "$scratch/DESetupLinux"; then
    rm -rf -- "$scratch"
    error 'Could not download the Noctalia configuration from DESetupLinux.'
    return 1
  fi

  staged_config="$scratch/DESetupLinux/.config/noctalia/config.toml"
  staged_palette="$scratch/DESetupLinux/.config/noctalia/palettes/Violet-Noir.json"
  if [[ ! -f "$staged_config" || ! -f "$staged_palette" ]]; then
    rm -rf -- "$scratch"
    error 'DESetupLinux is missing the Noctalia config or Violet-Noir palette.'
    return 1
  fi

  sudo pacman -S --needed --noconfirm "${PACMAN_NOCTALIA_PACKAGES[@]}"

  config_target="$HOME/.config/noctalia/config.toml"
  palette_target="$HOME/.config/noctalia/palettes/Violet-Noir.json"
  override_file="$HOME/.local/state/noctalia/settings.toml"
  autostart_target="$HOME/.config/autostart/noctalia.desktop"
  backup_dir="$HOME/.dotfiles-backup/noctalia-$(date +%Y%m%d-%H%M%S)"
  if [[ -f "$config_target" || -f "$palette_target" || -f "$override_file" || -f "$autostart_target" ]]; then
    mkdir -p "$backup_dir"
    if [[ -f "$config_target" ]]; then cp -a -- "$config_target" "$backup_dir/config.toml"; fi
    if [[ -f "$palette_target" ]]; then cp -a -- "$palette_target" "$backup_dir/Violet-Noir.json"; fi
    if [[ -f "$autostart_target" ]]; then cp -a -- "$autostart_target" "$backup_dir/noctalia.desktop"; fi
    if [[ -f "$override_file" ]]; then
      cp -a -- "$override_file" "$backup_dir/settings.toml"
      has_override=yes
    fi
    info "Backed up existing Noctalia files to $backup_dir"
  fi

  mkdir -p "${config_target%/*}" "${palette_target%/*}"
  if ! sed "s|@HOME@|$HOME|g" "$staged_config" > "$scratch/config.toml"; then
    rm -rf -- "$scratch"
    error 'Could not substitute the home directory into the Noctalia config.'
    return 1
  fi
  install -m 644 "$scratch/config.toml" "$config_target"
  install -m 644 "$staged_palette" "$palette_target"
  rm -rf -- "$scratch"

  # Register Noctalia for KDE login before removing Plasma's panels.
  mkdir -p "${autostart_target%/*}"
  cat > "$autostart_target" <<'EOF'
[Desktop Entry]
Type=Application
Name=Noctalia
Exec=noctalia --daemon
Terminal=false
OnlyShowIn=KDE;
X-KDE-autostart-phase=2
EOF
  chmod 0644 "$autostart_target"

  # Daemon mode returns only after Noctalia has initialized successfully. Keep
  # the existing Plasma panels if the startup check fails.
  info 'Starting Noctalia to verify its installation before changing Plasma panels.'
  if ! noctalia --daemon >/dev/null 2>&1; then
    error 'Noctalia did not start successfully; check ~/.cache/noctalia/noctalia.log. Plasma panels were left unchanged.'
    return 1
  fi

  # Run through the live Plasma scripting interface, preserving desktop
  # containments while removing panel containments after the Noctalia check.
  if ! command -v dbus-send >/dev/null 2>&1; then
    error 'dbus-send is unavailable; Plasma panels were left unchanged.'
    return 1
  fi
  dbus-send --session \
    --dest=org.kde.plasmashell \
    --type=method_call \
    /PlasmaShell \
    org.kde.PlasmaShell.evaluateScript \
    'string:for (const panel of panels()) { panel.remove(); }'

  if [[ "$has_override" == yes ]]; then
    warn "Existing Noctalia GUI overrides were preserved and may take precedence; backup: $backup_dir/settings.toml"
  fi
  success 'Noctalia installed, started, configured to autostart, and Plasma panels removed.'
}
installNoctaliaShellForKde() {
  assert_prerequisites
  checkUpdates
  configureNoctaliaShellForKde
}
applyKdePlasmaConfig() {
  local backup_dir name cursor_theme_found=no
  local wallpaper_dir="$HOME/Pictures/Wallpapers" wallpaper_source=''
  local -a cursor_theme_paths=(
    "$HOME/.icons/Empty-Butterfly-Purple"
    "$HOME/.local/share/icons/Empty-Butterfly-Purple"
    '/usr/share/icons/Empty-Butterfly-Purple'
  )

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    error 'kwriteconfig6 is unavailable (requires KDE configuration utilities).'
    return 1
  fi
  if ! command -v kreadconfig6 >/dev/null 2>&1; then
    error 'kreadconfig6 is unavailable; KDE configuration cannot be verified.'
    return 1
  fi
  if ! command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    error 'plasma-apply-colorscheme is unavailable.'
    return 1
  fi
  if ! command -v plasma-apply-lookandfeel >/dev/null 2>&1; then
    error 'plasma-apply-lookandfeel is unavailable.'
    return 1
  fi

  for name in "${cursor_theme_paths[@]}"; do
    if [[ -d "$name" ]]; then cursor_theme_found=yes; break; fi
  done
  if [[ "$cursor_theme_found" != yes ]]; then
    error 'Required Empty-Butterfly-Purple cursor theme was not found after installing Desktop Environment Items.'
    return 1
  fi

  backup_dir="$HOME/.dotfiles-backup/kde-appearance-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"
  for name in kdeglobals kcminputrc kwinrc plasmarc kglobalshortcutsrc kscreenlockerrc plasma-org.kde.plasma.desktop-appletsrc; do
    if [[ -f "$HOME/.config/$name" ]]; then
      cp -a -- "$HOME/.config/$name" "$backup_dir/$name"
    fi
  done
  if [[ -r /etc/plasmalogin.conf ]]; then
    cp -a -- /etc/plasmalogin.conf "$backup_dir/plasmalogin.conf"
  fi
  info "Backed up existing KDE configuration files to $backup_dir"

  # Apply Oxygen through KDE so its first-login defaults are recorded before
  # the individual Oxygen components and Breeze Dark colors are set below.
  if ! plasma-apply-lookandfeel --apply org.kde.oxygen; then
    error 'Could not apply the Oxygen global theme through KDE.'
    return 1
  fi

  # Keep the Oxygen application style and Plasma style after applying the theme.
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Oxygen
  kwriteconfig6 --file plasmarc --group Theme --key name oxygen

  # Keep the lock-screen theme Oxygen. Theme is used by
  # older Plasma releases; LookAndFeel is used by newer Plasma 6 releases.
  kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme org.kde.oxygen
  kwriteconfig6 --file kscreenlockerrc --group Greeter --key LookAndFeel org.kde.oxygen

  # Apply Breeze Dark after all theme settings. Some Plasma versions return a
  # nonzero status when the requested scheme is already active.
  local colorscheme_output
  if ! colorscheme_output=$(plasma-apply-colorscheme BreezeDark 2>&1); then
    if [[ "$colorscheme_output" == *'already set'* ]]; then
      info 'Breeze Dark is already active.'
    else
      error "Could not apply the Breeze Dark color scheme: $colorscheme_output"
      return 1
    fi
  fi
  local configured_colorscheme
  configured_colorscheme=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)
  if [[ "$configured_colorscheme" != BreezeDark ]]; then
    error "Breeze Dark did not persist as the active color scheme (KDE reports: ${configured_colorscheme:-<empty>})."
    return 1
  fi
  success 'Verified Breeze Dark as the active KDE color scheme.'

  # Apply the custom Violet-Noir accent through KDE's supported helper so
  # Plasma updates the active session as well as saving the setting.
  local accent_output
  if ! accent_output=$(plasma-apply-colorscheme --accent-color '#453078' BreezeDark 2>&1); then
    if [[ "$accent_output" == *'already set'* ]]; then
      info 'Breeze Dark is already active while applying the custom accent.'
    else
      error "Could not apply the Violet-Noir accent color: $accent_output"
      return 1
    fi
  fi
  local configured_accent
  configured_accent=$(kreadconfig6 --file kdeglobals --group General --key accentColor)
  if [[ "$configured_accent" != '69,48,120' && "$configured_accent" != '#453078' ]]; then
    error "Violet-Noir accent did not persist (KDE reports: ${configured_accent:-<empty>})."
    return 1
  fi
  kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper false
  success 'Verified the Violet-Noir custom accent color.'

  # Breeze icons, without changing individual applications' bundled icons.
  kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark

  # Oxygen window decoration. Remove the obsolete theme key so it uses the
  # Oxygen decoration's own defaults.
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.oxygen
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme --delete

  # Cursor theme supplied by DESetupLinux via Arch-GKuba.
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Empty-Butterfly-Purple
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 48

  # Use Ghostty as KDE's terminal and move the terminal shortcuts from Konsole.
  kwriteconfig6 --file kglobalshortcutsrc \
    --group services \
    --group org.kde.konsole.desktop \
    --key _launch none
  kwriteconfig6 --file kdeglobals \
    --group General \
    --key TerminalApplication ghostty
  kwriteconfig6 --file kdeglobals \
    --group General \
    --key TerminalService com.mitchellh.ghostty.desktop
  kwriteconfig6 --file kglobalshortcutsrc \
    --group services \
    --group com.mitchellh.ghostty.desktop \
    --key _launch $'Meta+X\tCtrl+Alt+T'

  # Allow legacy X11 applications to receive mouse-button events for PTT.
  kwriteconfig6 --file kwinrc \
    --group Xwayland \
    --key XwaylandEavesdropsMouse true

  # Turn Num Lock on when Plasma starts.
  kwriteconfig6 --file kcminputrc \
    --group Keyboard \
    --key NumLock 0

  # Configure an hourly slideshow on every screen when wallpaper assets exist.
  if [[ -d "$wallpaper_dir" ]]; then
    local required_command
    for required_command in python3 dbus-send; do
      if ! command -v "$required_command" >/dev/null 2>&1; then
        error "$required_command is unavailable; cannot configure the Plasma wallpaper slideshow."
        return 1
      fi
    done
    WALLPAPER_DIR="$wallpaper_dir" python3 -c '
import json, os, subprocess

folder = os.environ["WALLPAPER_DIR"]
script = """
var screens = desktops();
for (var i = 0; i < screens.length; i++) {
    var desktop = screens[i];
    desktop.wallpaperPlugin = "org.kde.slideshow";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.slideshow", "General"];
    desktop.writeConfig("SlidePaths", [FOLDER]);
    desktop.writeConfig("SlideInterval", 3600);
    desktop.writeConfig("SlideshowMode", 1);
    desktop.writeConfig("SlideshowFoldersFirst", false);
    desktop.writeConfig("UncheckedSlides", []);
    desktop.writeConfig("FillMode", 2);
    desktop.writeConfig("DynamicMode", 0);
    desktop.reloadConfig();
}
""".replace("FOLDER", json.dumps(folder))

subprocess.run([
    "dbus-send", "--session",
    "--dest=org.kde.plasmashell",
    "--type=method_call",
    "/PlasmaShell",
    "org.kde.PlasmaShell.evaluateScript",
    "string:" + script
], check=True)
'
    success 'Configured the hourly Plasma wallpaper slideshow on all screens.'
  else
    info "Wallpaper directory not found; skipping slideshow setup: $wallpaper_dir"
  fi

  # Choose a PNG wallpaper for Plasma Login Manager when one is available.
  if [[ -d "$wallpaper_dir" ]]; then
    wallpaper_source=$(find "$wallpaper_dir" -maxdepth 1 -type f -iname '*.png' | shuf -n 1)
    if [[ -n "$wallpaper_source" ]]; then
      sudo install -d -m 755 /var/lib/plasmalogin/wallpapers
      sudo install -m 644 "$wallpaper_source" \
        /var/lib/plasmalogin/wallpapers/login-wallpaper.png

      sudo kwriteconfig6 --file /etc/plasmalogin.conf \
        --group Greeter \
        --key WallpaperPluginId org.kde.image
      sudo kwriteconfig6 --file /etc/plasmalogin.conf \
        --group Greeter \
        --group Wallpaper \
        --group org.kde.image \
        --group General \
        --key Image 'file:///var/lib/plasmalogin/wallpapers/login-wallpaper.png'
      success 'Configured a random PNG wallpaper for Plasma Login Manager.'
    else
      info "No PNG wallpapers found; skipping Plasma Login Manager wallpaper setup."
    fi
  else
    info "Wallpaper directory not found; skipping Plasma Login Manager wallpaper setup: $wallpaper_dir"
  fi

  # Configure the Plasma lock screen to read the selected image from the
  # user's wallpaper directory. The login manager uses its separate system copy.
  if [[ -n "$wallpaper_source" ]]; then
    if [[ ! -r "$wallpaper_source" ]]; then
      error "The selected lock-screen wallpaper is not readable: $wallpaper_source"
      return 1
    fi
    local lock_wallpaper_url="file://${wallpaper_source}"
    kwriteconfig6 \
      --file kscreenlockerrc \
      --group Greeter \
      --key WallpaperPlugin \
      org.kde.image
    kwriteconfig6 \
      --file kscreenlockerrc \
      --group Greeter \
      --group Wallpaper \
      --group org.kde.image \
      --group General \
      --key Image \
      "$lock_wallpaper_url"
    kwriteconfig6 \
      --file kscreenlockerrc \
      --group Greeter \
      --group Wallpaper \
      --group org.kde.image \
      --group General \
      --key PreviewImage \
      "$lock_wallpaper_url"

    local configured_lock_wallpaper configured_lock_plugin
    configured_lock_plugin=$(kreadconfig6 --file kscreenlockerrc \
      --group Greeter --key WallpaperPlugin)
    configured_lock_wallpaper=$(kreadconfig6 --file kscreenlockerrc \
      --group Greeter --group Wallpaper --group org.kde.image \
      --group General --key Image)
    if [[ "$configured_lock_plugin" != org.kde.image || \
      "$configured_lock_wallpaper" != "$lock_wallpaper_url" ]]; then
      error 'Plasma lock-screen wallpaper settings did not persist to kscreenlockerrc.'
      info "Expected plugin: org.kde.image; image: $lock_wallpaper_url"
      info "Read back plugin: ${configured_lock_plugin:-<empty>}; image: ${configured_lock_wallpaper:-<empty>}"
      return 1
    fi
    success 'Verified the Plasma lock-screen wallpaper settings and image file.'
  fi

  printf '\n'
  success 'KDE Plasma appearance, terminal, input, and wallpaper settings written.'
  info 'Some changes may require logging out and back in.'
}

# Wizard prompts and summary
gatherWizardAnswers() {
  INSTALL_EXTRA=no; INSTALL_COOLING=no; INSTALL_DESKTOP_ASSETS=no; INSTALL_KDE_CONFIG=no; INSTALL_NOCTALIA=no
  WANT_WALLPAPERS=no; WANT_CURSORS=no
  local -a package_lines=()
  append_wrapped_packages package_lines "${PACMAN_EXTRA_DESKTOP_PACKAGES[@]}"
  wizard_panel 'Extra Desktop Apps' "${package_lines[@]}"
  if ask_yes_no 'Install these extra desktop applications?' "$DEFAULT_INSTALL_EXTRA"; then INSTALL_EXTRA=yes; fi
  package_lines=()
  package_lines+=('CoolerControl packages:')
  append_wrapped_packages package_lines "${PACMAN_COOLING_PACKAGES[@]}"
  package_lines+=('MSI sensor driver (AUR):')
  append_wrapped_packages package_lines "${AUR_COOLING_PACKAGES[@]}"
  package_lines+=('CoolerControl profile will also be applied.')
  wizard_panel 'CoolerControl and MSI sensor support' "${package_lines[@]}"
  if ask_yes_no 'Install CoolerControl and its MSI sensor driver?' "$DEFAULT_INSTALL_COOLING"; then INSTALL_COOLING=yes; fi
  local -a desktop_asset_lines=()
  append_wrapped_packages desktop_asset_lines 'Wallpapers' 'Cursor themes'
  wizard_panel 'Optional Desktop Environment Items' "${desktop_asset_lines[@]}"
  info 'Desktop Environment Items are required for KDE Plasma cursor settings.'
  if ask_yes_no 'Install these desktop environment items?' "$DEFAULT_INSTALL_DESKTOP_ASSETS"; then
    INSTALL_DESKTOP_ASSETS=yes
    # Replace the yes/no question with the follow-up choice, leaving the
    # desktop-items panel visible above it.
    if is_tty; then printf '\033[1A\r\033[2K'; fi
    local choice
    while true; do
      read -r -p 'Choose [w]allpapers, [c]ursor themes, or [b]oth: ' choice || return 1
      case "${choice,,}" in
        w|wallpapers) WANT_WALLPAPERS=yes; break ;;
        c|cursors|cursor) WANT_CURSORS=yes; break ;;
        b|both) WANT_WALLPAPERS=yes; WANT_CURSORS=yes; break ;;
        *) warn "Enter 'w', 'c', or 'b'." ;;
      esac
    done
  fi

  local -a kde_config_lines=('Oxygen style, Breeze Dark colors, and Violet-Noir accent' 'Set Ghostty as the default terminal')
  kde_config_lines+=('Bind Super+X and Ctrl+Alt+T to Ghostty')
  kde_config_lines+=('Allow X11 apps to receive mouse-button events for PTT')
  kde_config_lines+=('Turn Num Lock on when Plasma starts')
  kde_config_lines+=('Set an hourly slideshow on all screens if wallpapers exist')
  kde_config_lines+=('Set a random PNG for the Plasma login and lock screens if available')
  kde_config_lines+=('Oxygen will be added to the installed package list')
  kde_config_lines+=('Ghostty will be added if Extra Desktop Apps is not selected')
  kde_config_lines+=('Requires the Empty-Butterfly-Purple cursor theme; it will be added')
  wizard_panel 'KDE Plasma Configuration' "${kde_config_lines[@]}"
  if ask_yes_no 'Install KDE Plasma configuration?' no; then
    INSTALL_KDE_CONFIG=yes
    if [[ "$WANT_CURSORS" != yes ]]; then
      info 'Adding Desktop Environment Items and the required cursor theme for KDE Plasma configuration.'
      INSTALL_DESKTOP_ASSETS=yes
      WANT_CURSORS=yes
    fi
  fi

  local -a noctalia_lines=('Install Noctalia with Violet-Noir config')
  noctalia_lines+=('Autostart on KDE login')
  noctalia_lines+=('Remove Plasma panels')
  noctalia_lines+=('Preserve existing GUI overrides')
  wizard_panel 'Noctalia shell for KDE' "${noctalia_lines[@]}"
  if ask_yes_no 'Install Noctalia shell for KDE?' no; then INSTALL_NOCTALIA=yes; fi
  return 0
}
showPlan() {
  local -a lines=('Update system')
  if [[ "$INSTALL_EXTRA" == yes ]]; then
    lines+=('Extra Desktop Apps:')
    append_wrapped_packages lines "${PACMAN_EXTRA_DESKTOP_PACKAGES[@]}"
  fi
  if [[ "$INSTALL_COOLING" == yes ]]; then
    lines+=('CoolerControl packages:')
    append_wrapped_packages lines "${PACMAN_COOLING_PACKAGES[@]}"
    lines+=('MSI sensor driver (AUR):')
    append_wrapped_packages lines "${AUR_COOLING_PACKAGES[@]}"
    lines+=('Apply CoolerControl profile and enable daemon')
  fi
  if [[ "$INSTALL_DESKTOP_ASSETS" == yes ]]; then
    lines+=('Optional Desktop Environment Items:')
    local -a selected_assets=()
    [[ "$WANT_WALLPAPERS" == yes ]] && selected_assets+=('Wallpapers')
    [[ "$WANT_CURSORS" == yes ]] && selected_assets+=('Cursor themes')
    append_wrapped_packages lines "${selected_assets[@]}"
  fi
  if [[ "$INSTALL_KDE_CONFIG" == yes ]]; then
    lines+=('KDE Plasma Configuration:')
    lines+=('  Oxygen, Ghostty, theme, input, and wallpapers')
  fi
  if [[ "$INSTALL_NOCTALIA" == yes ]]; then
    lines+=('Noctalia shell for KDE:')
    lines+=('  Install, configure, autostart, remove Plasma panels')
  fi
  wizard_panel 'Setup Plan' "${lines[@]}"
}

# Public actions (the only accepted function arguments)
installExtraDesktopApps() { run_group extra-desktop PACMAN_EXTRA_DESKTOP_PACKAGES; }
installCooling() { run_group cooling PACMAN_COOLING_PACKAGES; }
installSelectedDesktopPackages() {
  local -a packages=()
  [[ "$INSTALL_EXTRA" == yes ]] && packages+=("${PACMAN_EXTRA_DESKTOP_PACKAGES[@]}")
  if [[ "$INSTALL_KDE_CONFIG" == yes ]]; then
    packages+=(oxygen)
    [[ "$INSTALL_EXTRA" == yes ]] || packages+=(ghostty)
  fi
  ((${#packages[@]})) && sudo pacman -S --needed --noconfirm "${packages[@]}"
}

# Main wizard
main() {
  assert_prerequisites
  local tty=no; is_tty && tty=yes
  [[ "$tty" == yes ]] && draw_screen 'Gathering Information' || printf 'Arch Post-Install Script\n\n'
  gatherWizardAnswers
  local -a completed=('Gathering Information')
  [[ "$tty" == yes ]] && draw_screen 'Updating System' "${completed[@]}"
  showPlan
  confirm_plan || { info 'Setup cancelled; no changes were made.'; return 0; }
  [[ "$tty" == yes ]] && draw_screen 'Updating System' "${completed[@]}"
  run_in_progress_area checkUpdates; completed+=('Updating System')
  [[ "$tty" == yes ]] && draw_screen 'Installing Pacman Packages' "${completed[@]}"
  if [[ "$INSTALL_EXTRA" == yes || "$INSTALL_KDE_CONFIG" == yes ]]; then
    run_in_progress_area installSelectedDesktopPackages
  fi
  [[ "$INSTALL_COOLING" == yes ]] && run_in_progress_area installPackages PACMAN_COOLING_PACKAGES
  completed+=('Installing Pacman Packages')
  if [[ "$INSTALL_COOLING" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing AUR Packages' "${completed[@]}"
    run_in_progress_area installAurPackages "${AUR_COOLING_PACKAGES[@]}"; completed+=('Installing AUR Packages')
    [[ "$tty" == yes ]] && draw_screen 'Applying CoolerControl Config' "${completed[@]}"
    run_in_progress_area applyCoolerControlConfig
  else
    completed+=('Installing AUR Packages' 'Applying CoolerControl Config')
  fi
  if [[ "$INSTALL_DESKTOP_ASSETS" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing Desktop Assets' "${completed[@]}"
    run_in_progress_area installDesktopAssets
    completed+=('Installing Desktop Assets')
  else
    completed+=('Installing Desktop Assets')
  fi
  if [[ "$INSTALL_KDE_CONFIG" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Applying KDE Plasma Config' "${completed[@]}"
    run_in_progress_area applyKdePlasmaConfig
  fi
  completed+=('Applying KDE Plasma Config')
  if [[ "$INSTALL_NOCTALIA" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing Noctalia shell for KDE' "${completed[@]}"
    run_in_progress_area configureNoctaliaShellForKde
  fi
  completed+=('Installing Noctalia shell for KDE' 'Applying CoolerControl Config' 'Finalizing')
  mark_setup_complete_in_place "${completed[@]}"
  success 'Post-installation sequence completed successfully.'
}

# Final dispatch
if (($# == 0)); then main; else
  case "$1" in
    --help|-h) usage ;;
    installExtraDesktopApps|installCooling|installDesktopAssets|installNoctaliaShellForKde) (($# == 1)) || { error 'Pass one action at a time.'; usage; exit 2; }; "$1" ;;
    *) error "Unknown action: $1"; usage; exit 2 ;;
  esac
fi
printf '\n'
