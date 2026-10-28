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
SUDO_KEEPALIVE_PID=''

# Help and supported public actions
usage() {
  cat <<EOF
Arch Post-Install Script
Usage: post-install.sh [installExtraDesktopApps|installCooling|installDesktopAssets|installNoctaliaShellForKde|installHyprlandNoctaliaConfig|--help]

No argument runs the interactive wizard. Direct actions run only the selected
task; package actions update the system first. Run as your user; sudo is
requested as needed.

  installExtraDesktopApps   Install optional desktop applications
  installCooling            Install CoolerControl and MSI sensor support
  installDesktopAssets      Copy selected wallpapers and/or cursor themes
  installNoctaliaShellForKde Install and configure Noctalia in the active KDE session
  installHyprlandNoctaliaConfig Deploy Hyprland and Noctalia appearance settings
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
  local active="$1" item completed_item mark color title='Arch Post-Install Script' width=68 left_pad right_pad
  shift
  left_pad=$(((width - ${#title}) / 2))
  right_pad=$((width - ${#title} - left_pad))
  printf '\033[H\033[2J%s%s╭' "$MAGENTA" "$BOLD"
  printf '─%.0s' $(seq 1 "$width")
  printf '╮%s\n%s%s│%*s%s%*s│%s\n%s%s╰' \
    "$RESET" "$MAGENTA" "$BOLD" "$left_pad" '' "$title" "$right_pad" '' "$RESET" "$MAGENTA" "$BOLD"
  printf '─%.0s' $(seq 1 "$width")
  printf '╯%s\n\n' "$RESET"
  for item in 'Gathering Information' 'Updating System' 'Installing Pacman Packages' 'Installing AUR Packages' 'Applying CoolerControl Config' 'Installing Desktop Assets' 'Applying KDE Plasma Config' 'Noctalia KDE Plasma' 'Hyprland & Noctalia Appearance' 'Finalizing'; do
    mark='○'; color="$DIM"
    if [[ "$item" == "$active" ]]; then mark='●'; color="$CYAN$BOLD"; else
      for completed_item in "$@"; do [[ "$item" == "$completed_item" ]] && { mark='✓'; color="$GREEN"; break; }; done
    fi
    printf '  %s%s %s%s\n' "$color" "$mark" "$item" "$RESET"
  done
  printf '\n'
}
mark_setup_complete_in_place() {
  local item row=5 output_row=15
  is_tty || return 0
  for item in 'Gathering Information' 'Updating System' 'Installing Pacman Packages' 'Installing AUR Packages' 'Applying CoolerControl Config' 'Installing Desktop Assets' 'Applying KDE Plasma Config' 'Noctalia KDE Plasma' 'Hyprland & Noctalia Appearance' 'Finalizing'; do
    # The finished view represents a completed run, including optional stages
    # the user chose to skip.
    printf '\033[%d;1H\033[2K  %s✓ %s%s' "$row" "$GREEN" "$item" "$RESET"
    row=$((row + 1))
  done
  # Clear the last stage's completion/progress area before final status output.
  printf '\033[%d;1H\033[J' "$output_row"
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
on_error() {
  local rc=$? line=${1:-?}
  if is_tty; then printf '\033[r\033[?25h\n'; fi
  error "Stopped at line $line (exit $rc). See the preceding error."
  exit "$rc"
}
trap 'on_error $LINENO' ERR

# Internal workflow helpers
cleanupSudoKeepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    local child_pid
    child_pid=$(pgrep -P "$SUDO_KEEPALIVE_PID" || true)
    [[ -n "$child_pid" ]] && kill $child_pid 2>/dev/null || true
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}
trap cleanupSudoKeepalive EXIT
startSudoKeepalive() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && return 0
  sudo -v
  (while :; do sleep 60; sudo -n -v || exit; done) </dev/null >/dev/null 2>&1 &
  SUDO_KEEPALIVE_PID=$!
}
checkUpdates() {
  startSudoKeepalive
  info 'Updating system packages.'
  sudo pacman -Syu --noconfirm
  SYSTEM_UPDATE_RAN=yes
}
run_in_progress_area() {
  if ! is_tty; then "$@"; return; fi
  local rows
  rows=$(tput lines 2>/dev/null || printf '24')
  if (( rows < 18 )); then "$@"; return; fi
  printf '\033[15;%sr\033[15;1H' "$rows"
  "$@"
  # Restore the full scroll region after the stage. On failure, the ERR trap
  # resets it before printing the error; successful redraw behavior is unchanged.
  printf '\033[s\033[r\033[u'
}
installPackages() { local -n group="$1"; ((${#group[@]})) && sudo pacman -S --needed --noconfirm "${group[@]}"; }
ensureParu() {
  command -v paru >/dev/null 2>&1 && { success 'paru is already installed.'; return; }
  info 'Installing paru from the configured pacman repositories.'
  sudo pacman -S --needed --noconfirm paru
  command -v paru >/dev/null 2>&1 || { error 'paru installation did not complete.'; return 1; }
  success 'paru is ready.'
}
installKernelHeadersForDkms() {
  local pkgbase_file pkgbase headers_package found_kernel=no
  local -a pkgbase_files=(/usr/lib/modules/*/pkgbase) header_packages=()
  local -A seen_headers=()

  for pkgbase_file in "${pkgbase_files[@]}"; do
    [[ -r "$pkgbase_file" ]] || continue
    IFS= read -r pkgbase < "$pkgbase_file"
    [[ -n "$pkgbase" ]] || continue
    found_kernel=yes
    headers_package="${pkgbase}-headers"
    [[ -n "${seen_headers[$headers_package]:-}" ]] && continue
    seen_headers[$headers_package]=yes
    pacman -Qq "$headers_package" >/dev/null 2>&1 && continue
    if ! pacman -Si "$headers_package" >/dev/null 2>&1; then
      error "Matching headers package $headers_package is not available for installed kernel $pkgbase. Install the matching headers before using the CoolerControl sensor driver."
      return 1
    fi
    header_packages+=("$headers_package")
  done

  if [[ "$found_kernel" != yes ]]; then
    error 'Could not determine installed kernel package bases under /usr/lib/modules.'
    return 1
  fi
  if ((${#header_packages[@]})); then
    info "Installing matching kernel headers for DKMS: ${header_packages[*]}"
    sudo pacman -S --needed --noconfirm "${header_packages[@]}"
  else
    info 'Matching kernel headers for DKMS are already installed.'
  fi
}
installAurPackages() {
  ((${#@})) || return 0
  installKernelHeadersForDkms
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
  WANT_WALLPAPERS=${WANT_WALLPAPERS:-no}
  WANT_CURSORS=${WANT_CURSORS:-no}
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
requireKdeSession() {
  local desktop="${XDG_CURRENT_DESKTOP:-}"
  desktop=${desktop,,}
  if [[ "$desktop" != *kde* && "$desktop" != *plasma* && "${KDE_FULL_SESSION:-}" != true ]]; then
    error 'This action requires an active KDE Plasma desktop session.'
    return 1
  fi
  command -v dbus-send >/dev/null 2>&1 || { error 'dbus-send is required for the active Plasma session.'; return 1; }
  if ! dbus-send --session --dest=org.kde.plasmashell --type=method_call \
    /PlasmaShell org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1; then
    error 'Could not reach plasmashell on the current session bus; no Noctalia changes were made.'
    return 1
  fi
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

  staged_config="$scratch/DESetupLinux/KDE Plasma/.config/noctalia/config.toml"
  staged_palette="$scratch/DESetupLinux/KDE Plasma/.config/noctalia/palettes/Violet-Noir.json"
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
  requireKdeSession
  checkUpdates
  configureNoctaliaShellForKde
}
configureHyprlandNoctaliaSettings() {
  local scratch staged_config_dir overlay_target backup_dir source_file relative_path target_file
  local cursor_source cursor_target wallpaper_source wallpaper_target asset wallpaper
  local wallpaper_applied=no theme_applied=no bar_style_applied=yes active_theme=
  local config_target="$HOME/.config/hypr/hyprland.lua"
  local overlay_line='dofile(os.getenv("HOME") .. "/.config/hypr/visual-overlay.lua")'

  assert_prerequisites
  command -v git >/dev/null 2>&1 || { error 'git is required to download the Hyprland configuration.'; return 1; }
  [[ -f "$config_target" ]] || {
    error "No Hyprland Lua config was found at $config_target; no files were changed."
    return 1
  }

  scratch=$(mktemp -d "${TMPDIR:-/tmp}/hyprland-noctalia-setup.XXXXXXXX")
  if ! git clone --depth=1 "$DESETUP_REPO" "$scratch/DESetupLinux"; then
    rm -rf -- "$scratch"
    error 'Could not download the Hyprland configuration from DESetupLinux.'
    return 1
  fi

  staged_config_dir="$scratch/DESetupLinux/Hyprland/.config"
  overlay_target="$staged_config_dir/hypr/visual-overlay.lua"
  cursor_source="$scratch/DESetupLinux/.icons/Empty-Butterfly-Purple"
  wallpaper_source="$scratch/DESetupLinux/Wallpapers"
  cursor_target="$HOME/.local/share/icons/Empty-Butterfly-Purple-Hyprland"
  wallpaper_target="$HOME/Pictures/Wallpapers"
  [[ -f "$overlay_target" && -f "$staged_config_dir/noctalia/90-hyprland-overlay.toml" && -f "$staged_config_dir/noctalia/palettes/Violet-Noir.json" ]] || {
    rm -rf -- "$scratch"
    error 'DESetupLinux is missing one or more Hyprland/Noctalia overlay files.'
    return 1
  }
  [[ -d "$cursor_source" && -d "$wallpaper_source" ]] || {
    rm -rf -- "$scratch"
    error 'DESetupLinux is missing the Hyprland cursor theme or wallpaper assets.'
    return 1
  }

  backup_dir="$HOME/.dotfiles-backup/hyprland-noctalia-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$HOME/.config"
  while IFS= read -r -d '' source_file; do
    relative_path=${source_file#"$staged_config_dir/"}
    target_file="$HOME/.config/$relative_path"
    if [[ -e "$target_file" || -L "$target_file" ]]; then
      mkdir -p "$backup_dir/${relative_path%/*}"
      cp -a -- "$target_file" "$backup_dir/$relative_path"
    fi
  done < <(find "$staged_config_dir" -type f -print0)

  # Install the same cursor and wallpaper assets used by the other desktop
  # setup options. Existing files are backed up before being replaced.
  mkdir -p "${cursor_target%/*}" "$wallpaper_target"
  if [[ -e "$cursor_target" || -L "$cursor_target" ]]; then
    mkdir -p "$backup_dir/.local/share/icons"
    cp -a -- "$cursor_target" "$backup_dir/.local/share/icons/Empty-Butterfly-Purple-Hyprland"
    rm -rf -- "$cursor_target"
  fi
  cp -a -- "$cursor_source" "$cursor_target"
  # Keep DESetupLinux's shared KDE cursor source untouched. Normalize only this
  # Hyprland-specific copy and give it a separate theme name.
  sed -i \
    -e 's/^Name=Empty-Butterfly-Purple$/Name=Empty-Butterfly-Purple-Hyprland/' \
    -e 's/^Inherits=.*/Inherits=hicolor/' \
    "$cursor_target/index.theme" "$cursor_target/cursor.theme"
  for asset in "$wallpaper_source"/* "$wallpaper_source"/.[!.]* "$wallpaper_source"/..?*; do
    [[ -e "$asset" || -L "$asset" ]] || continue
    [[ "${asset##*/}" == Archive ]] && continue
    wallpaper="$wallpaper_target/${asset##*/}"
    if [[ -e "$wallpaper" || -L "$wallpaper" ]]; then
      mkdir -p "$backup_dir/Pictures/Wallpapers"
      cp -a -- "$wallpaper" "$backup_dir/Pictures/Wallpapers/${asset##*/}"
    fi
    cp -a -- "$asset" "$wallpaper_target/"
  done
  cp -a -- "$staged_config_dir/." "$HOME/.config/"

  if ! grep -Fq "$overlay_line" "$config_target"; then
    mkdir -p "$backup_dir"
    cp -a -- "$config_target" "$backup_dir/hyprland.lua"
    {
      printf '\n-- Arch-GKuba managed visual overlay\n'
      printf '%s\n' "$overlay_line"
    } >> "$config_target"
  fi
  rm -rf -- "$scratch"
  if [[ -d "$backup_dir" ]]; then
    info "Existing configuration backups are in $backup_dir"
  fi
  if command -v noctalia >/dev/null 2>&1; then
    # Let Noctalia's config watcher load the newly copied settings.
    sleep 1
    # Keep the appearance settings effective even when the user has older
    # GUI-managed Noctalia overrides in settings.toml. Keep the user's existing
    # default bar shape while applying the requested size and widget styling.
    noctalia msg config-set bar.default.thickness '36' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.scale '1.2' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.color "'#E5E7ED'" >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.icon_color "'#E5E7ED'" >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.capsule_fill "'#202229'" >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.capsule_foreground "'#E5E7ED'" >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.background_opacity '0.72' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.shadow 'true' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.border "'#30303A'" >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.border_width '1.0' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.default.start '["workspaces", "active_window"]' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set bar.main.enabled 'false' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set widget.workspaces.capsule 'false' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set widget.network.show_label 'false' >/dev/null 2>&1 || bar_style_applied=no
    noctalia msg config-set widget.session.icon_color "'#72B87A'" >/dev/null 2>&1 || bar_style_applied=no
    if [[ "$bar_style_applied" == yes ]]; then
      success 'Applied Noctalia bar colors.'
    else
      warn 'Could not apply all Noctalia bar colors.'
    fi
    if noctalia msg color-scheme-set custom Violet-Noir >/dev/null 2>&1; then
      active_theme=$(noctalia msg color-scheme-get 2>/dev/null || true)
    fi
    if [[ "$active_theme" == 'custom Violet-Noir' ]]; then
      theme_applied=yes
      success 'Verified Noctalia theme selection: Custom / Violet-Noir.'
    else
      warn 'Noctalia did not confirm Custom / Violet-Noir; the Greeter sync was skipped.'
    fi
    if noctalia msg wallpaper-random >/dev/null 2>&1; then
      wallpaper_applied=yes
      success 'Applied a random wallpaper from ~/Pictures/Wallpapers.'
    fi
    if command -v noctalia-greeter-apply-appearance >/dev/null 2>&1; then
      if [[ "$theme_applied" == yes ]] && noctalia msg greeter-sync >/dev/null 2>&1; then
        success 'Synced the Violet-Noir Noctalia appearance to the login screen.'
      else
        warn 'Could not complete the initial Violet-Noir Greeter sync; Auto-Sync is enabled for later changes.'
      fi
    else
      info 'Noctalia Greeter is not installed; its Auto-Sync setting will take effect if Greeter is installed later.'
    fi
  fi
  if [[ "$wallpaper_applied" != yes ]]; then
    info 'The wallpaper folder is configured; Noctalia will use it when the shell starts.'
  fi
  success 'Hyprland and Noctalia appearance settings, cursor, and wallpapers are deployed; existing bindings and monitor settings were preserved.'
}
installHyprlandNoctaliaConfig() {
  configureHyprlandNoctaliaSettings
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
  # Seed the persisted value first; the helper can report that Breeze Dark is
  # already active even while it applies the accent option.
  kwriteconfig6 --file kdeglobals --group General --key AccentColor '69,48,120'
  kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper false
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
  configured_accent=$(kreadconfig6 --file kdeglobals --group General --key AccentColor)
  if [[ -z "$configured_accent" ]]; then
    configured_accent=$(kreadconfig6 --file kdeglobals --group General --key accentColor)
  fi
  if [[ "$configured_accent" != '69,48,120' && "$configured_accent" != '#453078' ]]; then
    error "Violet-Noir accent did not persist (KDE reports: ${configured_accent:-<empty>})."
    return 1
  fi
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
    local lock_wallpaper_url
    lock_wallpaper_url=$(WALLPAPER_SOURCE="$wallpaper_source" python3 -c \
      'import os, urllib.parse; print("file://" + urllib.parse.quote(os.environ["WALLPAPER_SOURCE"]))')
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
  INSTALL_EXTRA=no; INSTALL_COOLING=no; INSTALL_DESKTOP_ASSETS=no; INSTALL_KDE_CONFIG=no; INSTALL_NOCTALIA=no; INSTALL_HYPRLAND_CONFIG=no
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
  package_lines+=('Matching headers will be installed for DKMS.')
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
  wizard_panel 'Noctalia KDE Plasma' "${noctalia_lines[@]}"
  if ask_yes_no 'Install Noctalia KDE Plasma?' no; then INSTALL_NOCTALIA=yes; fi

  local -a hyprland_noctalia_lines=('Apply Violet-Noir glassy visual style' 'Set Empty-Butterfly-Purple cursor and install wallpapers' 'Use the wallpaper folder for hourly random Noctalia backgrounds' 'Enable Noctalia Greeter appearance auto-sync' 'Preserve monitor settings and keybindings')
  wizard_panel 'Hyprland & Noctalia Appearance' "${hyprland_noctalia_lines[@]}"
  if ask_yes_no 'Apply Hyprland and Noctalia appearance settings?' no; then INSTALL_HYPRLAND_CONFIG=yes; fi
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
    lines+=('Install matching kernel headers for DKMS')
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
    lines+=('Noctalia KDE Plasma:')
    lines+=('  Install, configure, autostart, remove Plasma panels')
  fi
  if [[ "$INSTALL_HYPRLAND_CONFIG" == yes ]]; then
    lines+=('Hyprland & Noctalia Appearance:')
    lines+=('  Back up and install appearance config, cursor, and wallpapers')
    lines+=('  Enable hourly random wallpapers and Greeter auto-sync')
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
  showPlan
  confirm_plan || { info 'Setup cancelled; no changes were made.'; return 0; }
  if [[ "$INSTALL_KDE_CONFIG" == yes || "$INSTALL_NOCTALIA" == yes ]]; then
    requireKdeSession
  fi
  [[ "$tty" == yes ]] && draw_screen 'Updating System' "${completed[@]}"
  run_in_progress_area checkUpdates; completed+=('Updating System')
  if [[ "$INSTALL_EXTRA" == yes || "$INSTALL_KDE_CONFIG" == yes || "$INSTALL_COOLING" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing Pacman Packages' "${completed[@]}"
  fi
  if [[ "$INSTALL_EXTRA" == yes || "$INSTALL_KDE_CONFIG" == yes ]]; then
    run_in_progress_area installSelectedDesktopPackages
  fi
  if [[ "$INSTALL_COOLING" == yes ]]; then
    run_in_progress_area installPackages PACMAN_COOLING_PACKAGES
  fi
  if [[ "$INSTALL_EXTRA" == yes || "$INSTALL_KDE_CONFIG" == yes || "$INSTALL_COOLING" == yes ]]; then
    completed+=('Installing Pacman Packages')
  fi
  if [[ "$INSTALL_COOLING" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing AUR Packages' "${completed[@]}"
    run_in_progress_area installAurPackages "${AUR_COOLING_PACKAGES[@]}"; completed+=('Installing AUR Packages')
    [[ "$tty" == yes ]] && draw_screen 'Applying CoolerControl Config' "${completed[@]}"
    run_in_progress_area applyCoolerControlConfig
    completed+=('Applying CoolerControl Config')
  fi
  if [[ "$INSTALL_DESKTOP_ASSETS" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing Desktop Assets' "${completed[@]}"
    run_in_progress_area installDesktopAssets
    completed+=('Installing Desktop Assets')
  fi
  if [[ "$INSTALL_KDE_CONFIG" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Applying KDE Plasma Config' "${completed[@]}"
    run_in_progress_area applyKdePlasmaConfig
    completed+=('Applying KDE Plasma Config')
  fi
  if [[ "$INSTALL_NOCTALIA" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Noctalia KDE Plasma' "${completed[@]}"
    run_in_progress_area configureNoctaliaShellForKde
    completed+=('Noctalia KDE Plasma')
  fi
  if [[ "$INSTALL_HYPRLAND_CONFIG" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Hyprland & Noctalia Appearance' "${completed[@]}"
    run_in_progress_area configureHyprlandNoctaliaSettings
    completed+=('Hyprland & Noctalia Appearance')
  fi
  completed+=('Finalizing')
  mark_setup_complete_in_place "${completed[@]}"
  [[ "$tty" == yes ]] && printf '\033[15;1H'
  success 'Post-installation sequence completed successfully.'
  if [[ "${SYSTEM_UPDATE_RAN:-no}" == yes ]]; then
    info 'If the update installed a new kernel, reboot to start it and load its DKMS modules.'
  fi
  [[ "$tty" == yes ]] && printf '\n'
}

# Final dispatch
if (($# == 0)); then main; else
  case "$1" in
    --help|-h) usage ;;
    installExtraDesktopApps|installCooling|installDesktopAssets|installNoctaliaShellForKde|installHyprlandNoctaliaConfig) (($# == 1)) || { error 'Pass one action at a time.'; usage; exit 2; }; "$1" ;;
    *) error "Unknown action: $1"; usage; exit 2 ;;
  esac
fi
[[ "${tty:-no}" == no ]] && printf '\n'
