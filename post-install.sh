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
PACMAN_CORE_PACKAGES=(git curl unzip 7zip neovim fastfetch fzf ttf-fira-code zsh starship)
PACMAN_EXTRA_DESKTOP_PACKAGES=(discord ghostty obsidian vivaldi spotify-launcher solaar)
PACMAN_COOLING_PACKAGES=(coolercontrol coolercontrold liquidctl)
AUR_COOLING_PACKAGES=(nct6687d-dkms-git)
DESETUP_REPO='https://github.com/gkuba/DESetupLinux.git'
STARSHIP_FALLBACK_INSTALLER='https://starship.rs/install.sh'
COOLERCONTROL_CONFIG_URL='https://raw.githubusercontent.com/gkuba/DESetupLinux/refs/heads/main/coolercontrol/config.toml'
DEFAULT_INSTALL_EXTRA=no
DEFAULT_INSTALL_COOLING=no
DEFAULT_INSTALL_DESKTOP_ASSETS=no

# Help and supported public actions
usage() {
  cat <<EOF
Arch Post-Install Script
Usage: $(basename "$0") [installCorePackages|installExtraDesktopApps|installCooling|installDesktopAssets|--help]

No argument runs the interactive wizard. Each install action runs only its
package group, after a system update. Run as your user; sudo is requested as needed.

  installCorePackages       Install core packages and configure the Zsh login shell
  installExtraDesktopApps   Install optional desktop applications
  installCooling            Install CoolerControl and MSI sensor support
  installDesktopAssets      Copy selected wallpapers and/or cursor themes
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
  local active="$1" item done mark color
  shift
  printf '\033[H\033[2J%s%s╭──────────────────────────────────────────────╮%s\n%s%s│             Arch Post-Install Script         │%s\n%s%s╰──────────────────────────────────────────────╯%s\n\n' "$MAGENTA" "$BOLD" "$RESET" "$MAGENTA" "$BOLD" "$RESET" "$MAGENTA" "$BOLD" "$RESET"
  for item in 'Gathering Information' 'Updating System' 'Installing Pacman Packages' 'Configuring Login Shell' 'Ensuring Paru' 'Installing AUR Packages' 'Applying CoolerControl Config' 'Installing Desktop Assets' 'Applying KDE Plasma Config' 'Finalizing'; do
    mark='○'; color="$DIM"
    if [[ "$item" == "$active" ]]; then mark='●'; color="$CYAN$BOLD"; else
      for done in "$@"; do [[ "$item" == "$done" ]] && { mark='✓'; color="$GREEN"; break; }; done
    fi
    printf '  %s%s %s%s\n' "$color" "$mark" "$item" "$RESET"
  done
  printf '\n'
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
  if is_tty; then printf '\033[13;1H\033[J'; fi
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
on_error() { local rc=$? line=${1:-?}; is_tty && printf '\033[r\033[?25h\n'; error "Stopped at line $line (exit $rc). See the preceding error."; exit "$rc"; }
trap 'on_error $LINENO' ERR

# Internal workflow helpers
checkUpdates() { info 'Updating system packages.'; sudo pacman -Syu --noconfirm; }
run_in_progress_area() {
  if ! is_tty; then "$@"; return; fi
  local rows rc=0
  rows=$(tput lines 2>/dev/null || printf '24')
  if (( rows < 18 )); then "$@"; return; fi
  printf '\033[13;%sr\033[13;1H' "$rows"
  "$@" || rc=$?
  # Keep pacman/sudo diagnostics visible if a stage fails. On success the next
  # draw_screen refreshes the display before beginning the following stage.
  printf '\033[r'
  return "$rc"
}
installPackages() { local -n group="$1"; ((${#group[@]})) && sudo pacman -S --needed --noconfirm "${group[@]}"; }
installCorePackageGroup() {
  local -n group=PACMAN_CORE_PACKAGES
  local package starship_available=yes
  local -a pacman_packages=()
  for package in "${group[@]}"; do
    if [[ "$package" == starship ]] && ! pacman -Si starship >/dev/null 2>&1; then
      starship_available=no
      info 'Starship is not available in the configured pacman repositories; using its installer as a fallback.'
    else
      pacman_packages+=("$package")
    fi
  done
  if ((${#pacman_packages[@]})); then sudo pacman -S --needed --noconfirm "${pacman_packages[@]}"; fi
  if [[ "$starship_available" == no ]]; then
    local installer install_status
    if command -v starship >/dev/null 2>&1; then
      success 'Starship is already available; keeping the existing installation.'
      return 0
    fi
    installer=$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXXXX")
    if ! curl -fsSL "$STARSHIP_FALLBACK_INSTALLER" -o "$installer"; then
      rm -f -- "$installer"
      error 'Could not download the Starship fallback installer.'
      return 1
    fi
    if sh "$installer" -y; then
      install_status=0
    else
      install_status=$?
    fi
    rm -f -- "$installer"
    ((install_status == 0)) || return "$install_status"
  fi
}
loginShellIsZsh() {
  local user shell_path
  user=$(id -un)
  shell_path=$(getent passwd "$user" | cut -d: -f7)
  [[ "${shell_path##*/}" == zsh ]]
}
setZshLoginShell() {
  local user zsh_path current_shell
  user=$(id -un)
  zsh_path=$(command -v zsh) || { error 'Zsh was not found after installing the core packages.'; return 1; }
  [[ -x "$zsh_path" ]] || { error "Detected Zsh path is not executable: $zsh_path"; return 1; }
  current_shell=$(getent passwd "$user" | cut -d: -f7)
  if [[ "$current_shell" == "$zsh_path" ]]; then success 'Zsh is already the default login shell.'; return 0; fi
  info "Setting the login shell for $user to $zsh_path."
  sudo usermod --shell "$zsh_path" "$user"
  current_shell=$(getent passwd "$user" | cut -d: -f7)
  [[ "$current_shell" == "$zsh_path" ]] || { error 'The account database did not report the Zsh shell change.'; return 1; }
  success "Default login shell set to $zsh_path. Log out and back in for it to take effect."
}
ensureParu() {
  command -v paru >/dev/null 2>&1 && { success 'paru is already installed.'; return; }
  info 'Installing paru from the configured pacman repositories.'
  sudo pacman -S --needed --noconfirm paru
  command -v paru >/dev/null 2>&1 || { error 'paru installation did not complete.'; return 1; }
  success 'paru is ready.'
}
installAurPackages() { ((${#@})) || return 0; ensureParu; paru -S --needed --noconfirm "$@"; }
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
  local scratch choice
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
    cp -a "$scratch/DESetupLinux/Wallpapers/." "$HOME/Pictures/Wallpapers/"
  fi
  if [[ "$WANT_CURSORS" == yes ]]; then
    [[ -d "$scratch/DESetupLinux/.icons" ]] || { rm -rf -- "$scratch"; error 'DESetupLinux .icons directory not found.'; return 1; }
    mkdir -p "$HOME/.icons"
    cp -a "$scratch/DESetupLinux/.icons/." "$HOME/.icons/"
  fi
  rm -rf -- "$scratch"
  success 'Selected desktop assets copied; unrelated destination files were retained.'
}
applyKdePlasmaConfig() {
  local backup_dir name cursor_theme_found=no
  local -a cursor_theme_paths=(
    "$HOME/.icons/Empty-Butterfly-Purple"
    "$HOME/.local/share/icons/Empty-Butterfly-Purple"
    '/usr/share/icons/Empty-Butterfly-Purple'
  )

  if ! command -v kwriteconfig6 >/dev/null 2>&1; then
    error 'kwriteconfig6 is unavailable (requires KDE configuration utilities).'
    return 1
  fi
  if ! command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    error 'plasma-apply-colorscheme is unavailable.'
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
  for name in kdeglobals kcminputrc kwinrc plasmarc; do
    if [[ -f "$HOME/.config/$name" ]]; then
      cp -a -- "$HOME/.config/$name" "$backup_dir/$name"
    fi
  done
  info "Backed up existing KDE configuration files to $backup_dir"

  # KDE application color scheme. Apply through KDE's supported helper.
  plasma-apply-colorscheme BreezeDark

  # Breeze icons, without changing individual applications' bundled icons.
  kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark

  # Oxygen widgets, Plasma Style, and overall look and feel.
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Oxygen
  kwriteconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.oxygen
  kwriteconfig6 --file plasmarc --group Theme --key name oxygen

  # Use wallpaper-derived accent rather than a fixed purple value.
  kwriteconfig6 --file kdeglobals --group General --key accentColorFromWallpaper true

  # Oxygen window decorations; don't modify KWin behavior or effects.
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.oxygen
  kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Breeze

  # Cursor theme supplied by DESetupLinux via Arch-GKuba.
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Empty-Butterfly-Purple
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorSize 48

  printf '\n'
  success 'KDE Plasma appearance settings written.'
  info 'Some changes may require logging out and back in.'
}

# Wizard prompts and summary
gatherWizardAnswers() {
  INSTALL_EXTRA=no; INSTALL_COOLING=no; INSTALL_DESKTOP_ASSETS=no; INSTALL_KDE_CONFIG=no; SET_ZSH_SHELL=no
  WANT_WALLPAPERS=no; WANT_CURSORS=no
  local -a package_lines=()
  append_wrapped_packages package_lines "${PACMAN_CORE_PACKAGES[@]}"
  wizard_panel 'Core packages (always included)' "${package_lines[@]}"
  if ! loginShellIsZsh && ask_yes_no 'Make Zsh the default login shell after installation?' yes; then SET_ZSH_SHELL=yes; fi
  package_lines=()
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

  local -a kde_config_lines=('Oxygen style and Breeze Dark colors' 'KDE appearance configuration')
  kde_config_lines+=('Oxygen will be added to the installed package list')
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
  return 0
}
showPlan() {
  local -a lines=('Update system')
  lines+=('Core packages:')
  append_wrapped_packages lines "${PACMAN_CORE_PACKAGES[@]}"
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
    lines+=('  Install Oxygen and apply KDE appearance settings')
  fi
  [[ "$SET_ZSH_SHELL" == yes ]] && lines+=('Set Zsh as the default login shell')
  wizard_panel 'Setup Plan' "${lines[@]}"
}

# Public actions (the only accepted function arguments)
installCorePackages() {
  assert_prerequisites
  local set_shell=no
  if ! loginShellIsZsh && ask_yes_no 'Make Zsh the default login shell after installation?' yes; then set_shell=yes; fi
  checkUpdates
  installCorePackageGroup
  if [[ "$set_shell" == yes ]]; then setZshLoginShell; fi
  success 'core package group complete.'
}
installExtraDesktopApps() { run_group extra-desktop PACMAN_EXTRA_DESKTOP_PACKAGES; }
installCooling() { run_group cooling PACMAN_COOLING_PACKAGES; }
installSelectedDesktopPackages() {
  local -a packages=()
  [[ "$INSTALL_EXTRA" == yes ]] && packages+=("${PACMAN_EXTRA_DESKTOP_PACKAGES[@]}")
  [[ "$INSTALL_KDE_CONFIG" == yes ]] && packages+=(oxygen)
  ((${#packages[@]})) && sudo pacman -S --needed --noconfirm "${packages[@]}"
}

# Main wizard
main() {
  assert_prerequisites
  local tty=no; is_tty && tty=yes
  [[ "$tty" == yes ]] && draw_screen 'Gathering Information' || printf 'Arch Post-Install Script\n\n'
  gatherWizardAnswers
  local -a completed=('Gathering Information')
  # The shell stage is already satisfied when Zsh was the login shell before
  # the wizard began, even though no shell change was needed.
  loginShellIsZsh && completed+=('Configuring Login Shell')
  [[ "$tty" == yes ]] && draw_screen 'Updating System' "${completed[@]}"
  showPlan
  confirm_plan || { info 'Setup cancelled; no changes were made.'; return 0; }
  [[ "$tty" == yes ]] && draw_screen 'Updating System' "${completed[@]}"
  run_in_progress_area checkUpdates; completed+=('Updating System')
  [[ "$tty" == yes ]] && draw_screen 'Installing Pacman Packages' "${completed[@]}"
  run_in_progress_area installCorePackageGroup
  if [[ "$INSTALL_EXTRA" == yes || "$INSTALL_KDE_CONFIG" == yes ]]; then
    run_in_progress_area installSelectedDesktopPackages
  fi
  [[ "$INSTALL_COOLING" == yes ]] && run_in_progress_area installPackages PACMAN_COOLING_PACKAGES
  completed+=('Installing Pacman Packages')
  if [[ "$SET_ZSH_SHELL" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Configuring Login Shell' "${completed[@]}"
    setZshLoginShell
  fi
  [[ "$tty" == yes ]] && draw_screen 'Ensuring Paru' "${completed[@]}"
  ensureParu; completed+=('Ensuring Paru')
  if [[ "$INSTALL_COOLING" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing AUR Packages' "${completed[@]}"
    installAurPackages "${AUR_COOLING_PACKAGES[@]}"; completed+=('Installing AUR Packages')
    [[ "$tty" == yes ]] && draw_screen 'Applying CoolerControl Config' "${completed[@]}"
    applyCoolerControlConfig
  else
    completed+=('Installing AUR Packages' 'Applying CoolerControl Config')
  fi
  if [[ "$INSTALL_DESKTOP_ASSETS" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Installing Desktop Assets' "${completed[@]}"
    installDesktopAssets
    completed+=('Installing Desktop Assets')
  else
    completed+=('Installing Desktop Assets')
  fi
  if [[ "$INSTALL_KDE_CONFIG" == yes ]]; then
    [[ "$tty" == yes ]] && draw_screen 'Applying KDE Plasma Config' "${completed[@]}"
    applyKdePlasmaConfig
  fi
  completed+=('Applying KDE Plasma Config')
  completed+=('Applying CoolerControl Config')
  if [[ "$SET_ZSH_SHELL" == yes ]]; then
    completed+=('Configuring Login Shell')
    [[ "$tty" == yes ]] && draw_screen 'Finalizing' "${completed[@]}"
  fi
  [[ "$tty" == yes ]] && draw_screen 'Finalizing' "${completed[@]}"
  command -v fc-cache >/dev/null 2>&1 && spinner 'Refreshing font cache' fc-cache -f
  success 'Post-installation sequence completed successfully.'
}

# Final dispatch
if (($# == 0)); then main; else
  case "$1" in
    --help|-h) usage ;;
    installCorePackages|installExtraDesktopApps|installCooling|installDesktopAssets) (($# == 1)) || { error 'Pass one action at a time.'; usage; exit 2; }; "$1" ;;
    *) error "Unknown action: $1"; usage; exit 2 ;;
  esac
fi
