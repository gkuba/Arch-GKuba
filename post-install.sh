#!/usr/bin/env bash
#
# Arch-GKuba post-install wizard
#
# Interactive installer for Arch-based systems (including CachyOS). Pick
# optional package groups, desktop assets, and KDE Plasma configuration,
# review the plan, authenticate once, and watch each step run.
#
# Run as your normal user; sudo is used only for system changes.

set -u -o pipefail
shopt -s extglob

# ─────────────────────────────────────────────────────────────────────────────
# Command line
# ─────────────────────────────────────────────────────────────────────────────

DRY_RUN=${DRY_RUN:-0}
[[ "$DRY_RUN" == 1 ]] || DRY_RUN=0
PRESELECT=0
PRE_APPS=0 PRE_COOLING=0 PRE_WALLPAPERS=0 PRE_CURSORS=0 PRE_KDE=0 PRE_DANK=0 PRE_UPDATE=0

usage() {
  cat <<EOF
Usage: ${0##*/} [options]

Interactive Arch-GKuba post-install wizard. With no options the wizard starts
at the welcome screen. Selection options pre-select those items and open the
wizard at the review screen; nothing runs until you confirm the plan and enter
your password.

Selections:
  -a, --apps         Extra desktop applications
                     (discord, ghostty, obsidian, vivaldi, spotify-launcher, solaar)
  -c, --cooling      CoolerControl, liquidctl, and the MSI nct6687d sensor driver (AUR)
  -w, --wallpapers   Copy DESetupLinux wallpapers into ~/Pictures/Wallpapers
  -u, --cursors      Copy DESetupLinux cursor themes into ~/.icons
  -k, --kde          KDE Plasma configuration (Oxygen, Breeze Dark, Violet-Noir, Ghostty)
  -D, --dankshell    Dank Shell on Hyprland with Ghostty, via the DuxLabs headless installer
  -U, --update       Full system update (pacman -Syu) before anything else
  -A, --all          -a, -c, -w, -u and -k (add -D for Dank Shell, -U for a system update)

Other:
  -n, --dry-run      Run the whole wizard and install screens but change nothing;
                     every command that would modify the system is shown instead.
                     (Also enabled by DRY_RUN=1.)
  -h, --help         Show this help.

Short options can be combined, e.g. ${0##*/} -akn

Package installs always sync and upgrade together (pacman -Syu --needed), so
the system is never left partially upgraded. Packages that are already
installed are skipped, and nothing is synced when there is nothing to install.
EOF
}

parse_args() {
  local arg flag i
  while (($#)); do
    arg=$1; shift
    case "$arg" in
      --apps) PRE_APPS=1 ;;
      --cooling) PRE_COOLING=1 ;;
      --wallpapers) PRE_WALLPAPERS=1 ;;
      --cursors) PRE_CURSORS=1 ;;
      --kde) PRE_KDE=1 ;;
      --dankshell) PRE_DANK=1 ;;
      --update) PRE_UPDATE=1 ;;
      --all) PRE_APPS=1 PRE_COOLING=1 PRE_WALLPAPERS=1 PRE_CURSORS=1 PRE_KDE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      --help) usage; exit 0 ;;
      --) (($#)) && { printf '%s: unexpected argument: %s\n' "${0##*/}" "$1" >&2; exit 2; }; break ;;
      --*) printf '%s: unknown option: %s\nTry --help.\n' "${0##*/}" "$arg" >&2; exit 2 ;;
      -?*)
        for ((i = 1; i < ${#arg}; i++)); do
          flag=${arg:i:1}
          case "$flag" in
            a) PRE_APPS=1 ;;
            c) PRE_COOLING=1 ;;
            w) PRE_WALLPAPERS=1 ;;
            u) PRE_CURSORS=1 ;;
            k) PRE_KDE=1 ;;
            D) PRE_DANK=1 ;;
            U) PRE_UPDATE=1 ;;
            A) PRE_APPS=1 PRE_COOLING=1 PRE_WALLPAPERS=1 PRE_CURSORS=1 PRE_KDE=1 ;;
            n) DRY_RUN=1 ;;
            h) usage; exit 0 ;;
            *) printf '%s: unknown option: -%s\nTry --help.\n' "${0##*/}" "$flag" >&2; exit 2 ;;
          esac
        done
        ;;
      *) printf '%s: unexpected argument: %s\nTry --help.\n' "${0##*/}" "$arg" >&2; exit 2 ;;
    esac
  done
  (( PRE_APPS || PRE_COOLING || PRE_WALLPAPERS || PRE_CURSORS || PRE_KDE || PRE_DANK || PRE_UPDATE )) && PRESELECT=1
  return 0
}

parse_args "$@"

if [[ ! -t 0 || ! -t 1 ]]; then
  printf 'Run this installer in a terminal.\n' >&2
  exit 2
fi

# ─────────────────────────────────────────────────────────────────────────────
# Glyphs and colors
# ─────────────────────────────────────────────────────────────────────────────

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF8=1 ;;
  *) UTF8=0 ;;
esac

if (( UTF8 )); then
  G_TL='╭' G_TR='╮' G_BL='╰' G_BR='╯' G_H='─' G_V='│' G_HEAVY='━'
  G_ON='●' G_OFF='○' G_CUR='▸' G_OK='✓' G_FAIL='✗' G_SKIP='–' G_WARN='!'
  G_INFO='•' G_RUN='→' G_DIAMOND='◆' G_SEP='·' G_MASK='•' G_REBOOT='↻'
  G_SUB='↳' G_THUMB='┃' G_TRACK='│' G_ELLIPSIS='…' G_UPDOWN='↑↓' G_ARROWS='↑↓←→'
  SPINNER=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
else
  G_TL='+' G_TR='+' G_BL='+' G_BR='+' G_H='-' G_V='|' G_HEAVY='='
  G_ON='x' G_OFF='.' G_CUR='>' G_OK='v' G_FAIL='x' G_SKIP='-' G_WARN='!'
  G_INFO='*' G_RUN='>' G_DIAMOND='*' G_SEP='-' G_MASK='*' G_REBOOT='!'
  G_SUB='-' G_THUMB='#' G_TRACK='|' G_ELLIPSIS='...' G_UPDOWN='Up/Dn' G_ARROWS='Arrows'
  SPINNER=( '|' '/' '-' '\' )
fi

# Violet-Noir palette.
PURPLE=$'\e[38;2;128;80;212m'
LAVENDER=$'\e[38;2;235;230;248m'
PINK=$'\e[38;2;255;121;198m'
BLUE=$'\e[38;2;139;180;255m'
CYAN=$'\e[38;2;65;220;205m'
GREEN=$'\e[38;2;95;210;145m'
YELLOW=$'\e[38;2;241;214;125m'
RED=$'\e[38;2;255;85;85m'
DIM=$'\e[38;2;150;144;170m'
BOLD=$'\e[1m'
RESET=$'\e[0m'
if [[ -n "${NO_COLOR:-}" || "${TERM:-dumb}" == dumb ]]; then
  PURPLE='' LAVENDER='' PINK='' BLUE='' CYAN='' GREEN='' YELLOW='' RED='' DIM='' BOLD='' RESET=''
fi

repeat_glyph() { # glyph count -> REPEAT_OUT
  local g=$1 n=$2 s=''
  (( n < 1 )) && { REPEAT_OUT=''; return; }
  while (( ${#s} < n )); do s+="$g$g$g$g$g$g$g$g"; done
  REPEAT_OUT=${s:0:n}
}
repeat_glyph "$G_H" 200; HBAR=$REPEAT_OUT
repeat_glyph "$G_HEAVY" 200; HEAVYBAR=$REPEAT_OUT

# ─────────────────────────────────────────────────────────────────────────────
# Data
# ─────────────────────────────────────────────────────────────────────────────

APP_ITEMS=( discord ghostty obsidian vivaldi spotify-launcher solaar )
COOLER_ITEMS=( coolercontrol coolercontrold liquidctl nct6687d-dkms-git )
AUR_COOLING_PACKAGES=( nct6687d-dkms-git )
COOLER_AUR_INDEX=3
COOLER_DAEMON_INDEX=1
GHOSTTY_INDEX=1
DESETUP_REPO='https://github.com/gkuba/DESetupLinux.git'
COOLERCONTROL_CONFIG_URL='https://raw.githubusercontent.com/gkuba/DESetupLinux/refs/heads/main/coolercontrol/config.toml'

PACKAGE_LABELS=( 'Extra desktop applications' 'CoolerControl and MSI sensor support' 'Full system update' )
PACKAGE_DETAILS=(
  "discord $G_SEP ghostty $G_SEP obsidian $G_SEP vivaldi $G_SEP spotify-launcher $G_SEP solaar"
  "coolercontrol $G_SEP coolercontrold $G_SEP liquidctl $G_SEP nct6687d-dkms-git (AUR, needs paru)"
  'pacman -Syu first. Without it, package installs still sync and upgrade (pacman -Syu --needed).'
)
UPDATE_INDEX=2   # PACKAGE_SELECTED[UPDATE_INDEX] is the system update, not a package group
ASSET_LABELS=( 'Wallpapers' 'Cursor themes' )
ASSET_DETAILS=(
  'Copy DESetupLinux wallpapers into ~/Pictures/Wallpapers'
  'Copy DESetupLinux cursor themes (Empty-Butterfly-Purple) into ~/.icons'
)
DESKTOP_LABELS=( 'KDE Plasma configuration' 'Dank Shell' )
DESKTOP_DETAILS=(
  "Oxygen style $G_SEP Breeze Dark $G_SEP Violet-Noir accent $G_SEP Ghostty terminal $G_SEP Num Lock $G_SEP PTT mouse buttons $G_SEP hourly wallpaper slideshow $G_SEP login and lock screen wallpaper"
  "Hyprland $G_SEP Ghostty $G_SEP adw-gtk-theme $G_SEP dms-greeter, dsearch, dcal $G_SEP installed headless by duxinstall; the Hyprland config is replaced (backup kept)"
)
DANK_INDEX=1
DUX_INSTALL_URL='https://install.duxlabs.dev'
# Headless duxinstall: https://duxlabs.dev/docs/duxinstall
DUX_INSTALL_ARGS=( -c hyprland -t ghostty --all-features --replace-configs hyprland --privesc sudo -y )
GROUP_TITLES=( 'Desktop applications' 'CoolerControl & MSI sensors' 'Desktop assets' 'Desktop themes' 'System' )

PACKAGE_SELECTED=(0 0 0)
PACKAGE_PREVIOUS=(0 0 0)
DESKTOP_SELECTED=(0 0)
ASSET_SELECTED=(0 0)
APP_SELECTED=(0 0 0 0 0 0)
COOLER_SELECTED=(0 0 0 0)
APP_INSTALLED=(0 0 0 0 0 0)
COOLER_INSTALLED=(0 0 0 0)
KDE_OXYGEN_INSTALLED=0
ADW_GTK_INSTALLED=0
PARU_INSTALLED=0
PARU_AVAILABLE=0
PACKAGE_STATUS_READY=0

PHASE_TITLES=( 'System update' 'Pacman packages' 'AUR packages' 'CoolerControl profile' 'Desktop assets' 'KDE Plasma configuration' 'Dank Shell' )
PHASE_FUNCS=( update_system_packages install_selected_pacman_packages install_selected_cooling_aur applyCoolerControlConfig install_selected_desktop_assets applyKdePlasmaConfig install_dank_shell )
PHASE_DONE_TEXT=( 'System packages are up to date.' 'Selected pacman packages installed.' 'AUR packages installed.' 'CoolerControl profile applied and daemon enabled.' 'Desktop assets copied.' 'KDE Plasma configuration applied.' 'Dank Shell installed on Hyprland.' )
PHASE_FATAL=( 1 1 0 0 0 0 0 )
PHASE_STATE=( pending pending pending pending pending pending pending )
PHASE_TIME=( '' '' '' '' '' '' '' )
PHASE_RC=( 0 0 0 0 0 0 0 )
PHASE_COUNT=${#PHASE_TITLES[@]}
STOP_REQUESTED=0
REBOOT_REASON=''
SUDO_KEEPALIVE_PID=''

# ─────────────────────────────────────────────────────────────────────────────
# Terminal and logging
# ─────────────────────────────────────────────────────────────────────────────

LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/arch-gkuba-post-install-$(date +%Y%m%d-%H%M%S)-XXXXXX.log") || exit 1
exec {LOG_FD}>>"$LOG_FILE"
SAVED_STTY=$(stty -g 2>/dev/null || true)

log_event() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*" >&"$LOG_FD"; }

enter_screen() {
  printf '\e[?1049h\e[?25l'
  [[ -z "$SAVED_STTY" ]] || stty -echo -icanon min 1 time 0 2>/dev/null || true
}
restore_terminal() {
  [[ -z "$SUDO_KEEPALIVE_PID" ]] || kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  [[ -z "$SAVED_STTY" ]] || stty "$SAVED_STTY" 2>/dev/null || true
  printf '\e[?25h\e[?1049l'
}
trap restore_terminal EXIT
trap 'exit 130' INT TERM

# Ctrl+C during installation must not interrupt pacman mid-transaction, so the
# terminal stops generating SIGINT and the frame reads Ctrl+C as a key instead.
disable_interrupt_key() { [[ -z "$SAVED_STTY" ]] || stty -isig 2>/dev/null || true; }

# ─────────────────────────────────────────────────────────────────────────────
# Layout helpers (everything fits 80x24; uses up to 100 columns when present)
# ─────────────────────────────────────────────────────────────────────────────

TERM_ROWS=24 TERM_COLS=80 W=76 BODY_LAST=21 FOOT_RULE=22 FOOT_KEYS=23

ui_metrics() {
  local size c
  size=$(stty size 2>/dev/null) || size=''
  if [[ "$size" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
    TERM_ROWS=${BASH_REMATCH[1]} TERM_COLS=${BASH_REMATCH[2]}
  else
    TERM_ROWS=24 TERM_COLS=80
  fi
  (( TERM_ROWS < 16 )) && TERM_ROWS=16
  c=$TERM_COLS
  (( c > 100 )) && c=100
  (( c < 64 )) && c=64
  W=$((c - 4))
  BODY_LAST=$((TERM_ROWS - 3))
  FOOT_RULE=$((TERM_ROWS - 2))
  FOOT_KEYS=$((TERM_ROWS - 1))
}

at() { printf '\e[%d;%dH' "$1" "$2"; }
put() { printf '\e[%d;1H\e[2K  %s' "$1" "$2"; }          # row, text at column 3

vis_len() { # text -> VIS_LEN (ANSI color codes excluded)
  local s=${1//$'\e'\[*([0-9;])m/}
  VIS_LEN=${#s}
}
pad() { # text width -> text padded with spaces to width
  vis_len "$1"
  local n=$(( $2 - VIS_LEN ))
  (( n < 0 )) && n=0
  printf '%s%*s' "$1" "$n" ''
}
pad_v() { # VAR text width -> VAR=text padded to width (no subshell)
  vis_len "$2"
  local n=$(( $3 - VIS_LEN ))
  (( n < 0 )) && n=0
  printf -v "$1" '%s%*s' "$2" "$n" ''
}
fit() { # plain-text width -> FIT_OUT truncated with an ellipsis when needed
  local text=$1 width=$2
  if (( ${#text} > width )); then
    FIT_OUT="${text:0:width-${#G_ELLIPSIS}}$G_ELLIPSIS"
  else
    FIT_OUT=$text
  fi
}

# wrap_into ARRAY WIDTH TEXT [CONTINUATION_PREFIX]
# Word-wraps plain text by character count (multibyte aware, unlike fold).
wrap_into() {
  local -n __wrap_out=$1
  local width=$2 text=$3 cont=${4-} lead rest line word avail cand
  local -a words=()
  __wrap_out=()
  (( width < 10 )) && width=10
  if (( ${#text} <= width )); then __wrap_out=("$text"); return 0; fi
  lead=${text%%[! ]*}
  rest=${text#"$lead"}
  [[ -n "$cont" ]] || cont=$lead
  read -ra words <<< "$rest"
  line=$lead
  for word in "${words[@]}"; do
    if [[ "$line" == "$lead" || "$line" == "$cont" ]]; then cand="$line$word"; else cand="$line $word"; fi
    if (( ${#cand} <= width )); then line=$cand; continue; fi
    [[ "$line" == "$lead" || "$line" == "$cont" ]] || { __wrap_out+=("$line"); line=$cont; }
    avail=$((width - ${#cont}))
    (( avail < 1 )) && avail=1
    while (( ${#line} + ${#word} > width )); do
      __wrap_out+=("$line${word:0:avail}")
      word=${word:avail}
      line=$cont
    done
    line+=$word
  done
  __wrap_out+=("$line")
}

# Header: rounded box with the app name in the top border, the screen title
# on the left and step progress on the right.
draw_header() { # title [progress-label current total]
  local title=$1 label=${2:-} cur=${3:-0} total=${4:-0}
  local name=" $G_DIAMOND ARCH-GKUBA POST-INSTALL " tag='' fill i dots='' plain_dots='' right='' plain_right=''
  ui_metrics
  (( DRY_RUN )) && tag=' DRY RUN '
  fill=$((W - 4 - ${#name} - ${#tag}))
  printf '\e[?25l\e[H\e[2J'
  at 1 3
  printf '%s%s%s%s%s%s%s%s%s%s%s%s%s' "$PURPLE" "$G_TL$G_H" "$RESET" "$PINK$BOLD" "$name" "$RESET" \
    "$PURPLE" "${HBAR:0:fill}" "$RESET" "$YELLOW$BOLD" "$tag" "$RESET" "$PURPLE$G_H$G_TR$RESET"
  if (( total > 0 )); then
    for ((i = 1; i <= total; i++)); do
      if (( i < cur )); then dots+="$GREEN$G_ON$RESET"
      elif (( i == cur )); then dots+="$CYAN$BOLD$G_ON$RESET"
      else dots+="$DIM$G_OFF$RESET"
      fi
      plain_dots+=x
    done
    right="$dots  $DIM$label $cur/$total$RESET"
    plain_right="$plain_dots  $label $cur/$total"
  fi
  fit "$title" $((W - 5 - ${#plain_right}))
  at 2 3
  printf '%s%s%s %s%s' "$PURPLE" "$G_V" "$RESET" "$BLUE$BOLD" "$FIT_OUT"
  printf '%s' "$RESET"
  at 2 $((3 + W - 2 - ${#plain_right}))
  printf '%s %s%s%s' "$right" "$PURPLE" "$G_V" "$RESET"
  at 3 3
  printf '%s%s%s%s%s' "$PURPLE" "$G_BL" "${HBAR:0:W-2}" "$G_BR" "$RESET"
}

# Footer: heavy rule plus key hints. Pass key/label pairs.
draw_footer() {
  local -a parts=()
  local key label sep text plain spacing
  while (($# >= 2)); do parts+=("$1" "$2"); shift 2; done
  for spacing in 3 2 1; do
    printf -v sep '%*s' "$spacing" ''
    text='' plain=''
    local i
    for ((i = 0; i < ${#parts[@]}; i += 2)); do
      key=${parts[i]} label=${parts[i+1]}
      [[ -z "$plain" ]] || { text+=$sep; plain+=$sep; }
      text+="$CYAN$BOLD$key$RESET $DIM$label$RESET"
      plain+="$key $label"
    done
    (( ${#plain} <= W )) && break
  done
  printf '\e[%d;1H\e[2K  %s%s%s' "$FOOT_RULE" "$PURPLE" "${HEAVYBAR:0:W}" "$RESET"
  printf '\e[%d;1H\e[2K  %s' "$FOOT_KEYS" "$text"
}

# read_key -> KEY: UP DOWN LEFT RIGHT PGUP PGDN HOME END ENTER ESC SPACE
#                  BACKSPACE CTRL_C CTRL_D IGNORE EOF, or the character typed.
read_key() {
  local k='' k2='' k3='' k4='' seq
  KEY=''
  IFS= read -rsn1 k || { KEY=EOF; return 1; }
  case "$k" in
    $'\e')
      if IFS= read -rsn1 -t 0.08 k2; then
        if [[ "$k2" == '[' || "$k2" == O ]]; then
          IFS= read -rsn1 -t 0.08 k3 || k3=''
          case "$k3" in
            A) KEY=UP ;; B) KEY=DOWN ;; C) KEY=RIGHT ;; D) KEY=LEFT ;;
            H) KEY=HOME ;; F) KEY=END ;;
            [0-9])
              seq=$k3
              while IFS= read -rsn1 -t 0.08 k4; do [[ "$k4" == '~' ]] && break; seq+=$k4; done
              case "$seq" in 5) KEY=PGUP ;; 6) KEY=PGDN ;; 1|7) KEY=HOME ;; 4|8) KEY=END ;; *) KEY=IGNORE ;; esac
              ;;
            *) KEY=IGNORE ;;
          esac
        else
          KEY=ESC
        fi
      else
        KEY=ESC
      fi
      ;;
    $'\r'|$'\n'|'') KEY=ENTER ;;
    ' ') KEY=SPACE ;;
    $'\x7f'|$'\b') KEY=BACKSPACE ;;
    $'\x03') KEY=CTRL_C ;;
    $'\x04') KEY=CTRL_D ;;
    *) KEY=$k ;;
  esac
  return 0
}

# Scrollable list: pager_draw ARRAY FIRST_ROW LAST_ROW. PAGER_START=-1 means
# "show the end". pager_scroll KEY handles scrolling keys.
PAGER_START=0 PAGER_MAX=0 PAGER_VISIBLE=1
pager_draw() {
  local -n __pager_lines=$1
  local first=$2 last=$3 total i row thumb_size thumb_start text_w=$((W - 2)) glyph color line
  PAGER_VISIBLE=$((last - first + 1))
  (( PAGER_VISIBLE < 1 )) && PAGER_VISIBLE=1
  total=${#__pager_lines[@]}
  PAGER_MAX=$((total - PAGER_VISIBLE))
  (( PAGER_MAX < 0 )) && PAGER_MAX=0
  (( PAGER_START < 0 || PAGER_START > PAGER_MAX )) && PAGER_START=$PAGER_MAX
  thumb_size=$((PAGER_VISIBLE * PAGER_VISIBLE / (total > 0 ? total : 1)))
  (( thumb_size < 1 )) && thumb_size=1
  thumb_start=$((PAGER_START * (PAGER_VISIBLE - thumb_size) / (PAGER_MAX > 0 ? PAGER_MAX : 1)))
  for ((i = 0; i < PAGER_VISIBLE; i++)); do
    row=$((first + i))
    line=${__pager_lines[PAGER_START + i]:-}
    pad_v PADDED "$line" "$text_w"
    printf '\e[%d;1H\e[2K  %s' "$row" "$PADDED"
    if (( total > PAGER_VISIBLE )); then
      if (( i >= thumb_start && i < thumb_start + thumb_size )); then glyph=$G_THUMB color=$CYAN$BOLD; else glyph=$G_TRACK color=$DIM; fi
      at "$row" $((W + 2))
      printf '%s%s%s' "$color" "$glyph" "$RESET"
    fi
  done
}
pager_scroll() {
  case "$1" in
    UP|k) (( PAGER_START > 0 )) && ((PAGER_START -= 1)) ;;
    DOWN|j) (( PAGER_START < PAGER_MAX )) && ((PAGER_START += 1)) ;;
    PGUP) PAGER_START=$((PAGER_START - PAGER_VISIBLE)); (( PAGER_START < 0 )) && PAGER_START=0 ;;
    PGDN) PAGER_START=$((PAGER_START + PAGER_VISIBLE)); (( PAGER_START > PAGER_MAX )) && PAGER_START=$PAGER_MAX ;;
    HOME) PAGER_START=0 ;;
    END) PAGER_START=$PAGER_MAX ;;
    *) return 1 ;;
  esac
  return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# Output helpers (used inside install steps; the frame colors them by prefix)
# ─────────────────────────────────────────────────────────────────────────────

info() { printf '%s %s\n' "$G_INFO" "$*"; }
success() { printf '%s %s\n' "$G_OK" "$*"; }
warn() { printf '%s %s\n' "$G_WARN" "$*"; }
error() { printf '%s %s\n' "$G_FAIL" "$*" >&2; }

quote_cmd() {
  local out='' a
  for a in "$@"; do
    if [[ "$a" =~ ^[A-Za-z0-9_./:=@%+,~-]+$ ]]; then out+="$a "; else out+="$(printf '%q' "$a") "; fi
  done
  printf '%s' "${out% }"
}

# Every command that changes the system goes through run(). In a dry run it
# is printed instead of executed.
run() {
  if (( DRY_RUN )); then
    printf '%s would run: %s\n' "$G_RUN" "$(quote_cmd "$@")"
    return 0
  fi
  "$@"
}
as_root() { run sudo -n "$@"; }
pacman_root() { # pacman arguments...
  if command -v stdbuf >/dev/null 2>&1; then
    as_root stdbuf -oL -eL pacman --noconfirm --color never "$@"
  else
    as_root pacman --noconfirm --color never "$@"
  fi
}
# Installing from stale package databases risks a partial upgrade, which Arch
# does not support. Without the system update step, every install syncs and
# upgrades in the same transaction; after it, the databases are already fresh.
pacman_install() { # packages...
  if (( PACKAGE_SELECTED[UPDATE_INDEX] )); then
    pacman_root -S --needed "$@"
  else
    pacman_root -Syu --needed "$@"
  fi
}
split_installed() { # packages... -> MISSING_PACKAGES INSTALLED_PACKAGES
  local name
  local -A have=()
  MISSING_PACKAGES=() INSTALLED_PACKAGES=()
  while IFS= read -r name; do [[ -n "$name" ]] && have[$name]=1; done < <(pacman -Qq "$@" 2>/dev/null)
  for name in "$@"; do
    if [[ -n "${have[$name]:-}" ]]; then INSTALLED_PACKAGES+=("$name"); else MISSING_PACKAGES+=("$name"); fi
  done
}
dry_note() { (( DRY_RUN )) && printf '%s dry run: %s\n' "$G_RUN" "$*"; return 0; }

need_cmd() { # command message -> fails, or only warns in a dry run
  command -v "$1" >/dev/null 2>&1 && return 0
  if (( DRY_RUN )); then warn "$2 (dry run continues)"; return 0; fi
  error "$2"
  return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Checks
# ─────────────────────────────────────────────────────────────────────────────

prerequisite_problem() { # prints a reason, or nothing when everything is fine
  if (( EUID == 0 )); then printf 'Run this installer as your normal user; sudo is requested only when needed.'; return; fi
  command -v sudo >/dev/null 2>&1 || { printf 'sudo is required.'; return; }
  command -v pacman >/dev/null 2>&1 || { printf 'pacman is required; this installer is for Arch-based systems.'; return; }
  [[ -r /etc/arch-release ]] || { printf 'Arch-based systems only (/etc/arch-release not found).'; return; }
}

kde_session_problem() { # prints a reason, or nothing when Plasma is reachable
  local desktop=${XDG_CURRENT_DESKTOP:-}
  desktop=${desktop,,}
  if [[ "$desktop" != *kde* && "$desktop" != *plasma* && "${KDE_FULL_SESSION:-}" != true ]]; then
    printf 'Not running inside a KDE Plasma session.'; return
  fi
  command -v dbus-send >/dev/null 2>&1 || { printf 'dbus-send is required to reach plasmashell.'; return; }
  dbus-send --session --dest=org.kde.plasmashell --type=method_call \
    /PlasmaShell org.freedesktop.DBus.Peer.Ping >/dev/null 2>&1 \
    || printf 'Could not reach plasmashell on the session bus.'
}

check_package_status() {
  local -A have=()
  local name i
  while IFS= read -r name; do [[ -n "$name" ]] && have[$name]=1; done \
    < <(pacman -Qq "${APP_ITEMS[@]}" "${COOLER_ITEMS[@]}" paru oxygen adw-gtk-theme 2>/dev/null)
  for i in "${!APP_ITEMS[@]}"; do APP_INSTALLED[i]=${have[${APP_ITEMS[i]}]:-0}; done
  for i in "${!COOLER_ITEMS[@]}"; do COOLER_INSTALLED[i]=${have[${COOLER_ITEMS[i]}]:-0}; done
  PARU_INSTALLED=${have[paru]:-0}
  KDE_OXYGEN_INSTALLED=${have[oxygen]:-0}
  ADW_GTK_INSTALLED=${have[adw-gtk-theme]:-0}
  if (( PARU_INSTALLED )) || pacman -Si paru >/dev/null 2>&1; then PARU_AVAILABLE=1; else PARU_AVAILABLE=0; fi
  PACKAGE_STATUS_READY=1
  log_event "Package status: apps=${APP_INSTALLED[*]} cooling=${COOLER_INSTALLED[*]} paru=$PARU_INSTALLED/$PARU_AVAILABLE oxygen=$KDE_OXYGEN_INSTALLED"
}

any_selected() { local v; for v in "$@"; do (( v )) && return 0; done; return 1; }

# ─────────────────────────────────────────────────────────────────────────────
# Wizard screens
# ─────────────────────────────────────────────────────────────────────────────

show_message_screen() { # title color lines...
  local title=$1 color=$2 row=5 line
  shift 2
  local -a wrapped=()
  draw_header "$title"
  local text
  for text in "$@"; do
    wrap_into wrapped $((W - 2)) "$text"
    for line in "${wrapped[@]}"; do put "$row" "$color$line$RESET"; ((row++)); done
  done
  put $((row + 1)) "${DIM}Log: $LOG_FILE$RESET"
  draw_footer 'Enter' 'Exit'
  while read_key; do [[ "$KEY" == ENTER || "$KEY" == ESC || "$KEY" == q ]] && return 0; done
}

show_welcome() {
  local os user host session size_note row
  os=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | sed 's/^"//;s/"$//')
  [[ -n "$os" ]] || os=Linux
  user=$(id -un 2>/dev/null || printf 'unknown')
  host=$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null || printf 'unknown')
  session="${XDG_CURRENT_DESKTOP:-no desktop}${XDG_SESSION_TYPE:+ ($XDG_SESSION_TYPE)}"
  log_event 'Welcome screen.'
  while :; do
    draw_header 'Welcome'
    put 5 "$DIM$G_INFO$RESET $LAVENDER$os$RESET $DIM$G_SEP$RESET $LAVENDER$user@$host$RESET $DIM$G_SEP$RESET $LAVENDER$session$RESET"
    put 7 "$BLUE${BOLD}What this installer can set up$RESET"
    put 8 "  $PINK$G_DIAMOND$RESET $(pad "${LAVENDER}${BOLD}Extra packages$RESET" 18)${DIM}desktop apps, CoolerControl, MSI sensor driver$RESET"
    put 9 "  $PINK$G_DIAMOND$RESET $(pad "${LAVENDER}${BOLD}Desktop assets$RESET" 18)${DIM}wallpapers and cursor themes$RESET"
    put 10 "  $PINK$G_DIAMOND$RESET $(pad "${LAVENDER}${BOLD}Desktop themes$RESET" 18)${DIM}KDE Plasma configuration, Dank Shell on Hyprland$RESET"
    put 11 "  $PINK$G_DIAMOND$RESET $(pad "${LAVENDER}${BOLD}System update$RESET" 18)${DIM}optional full pacman -Syu$RESET"
    put 13 "$BLUE${BOLD}How it works$RESET"
    put 14 "  ${CYAN}1$RESET Choose  $DIM$G_RUN$RESET  ${CYAN}2$RESET Review  $DIM$G_RUN$RESET  ${CYAN}3$RESET Authenticate  $DIM$G_RUN$RESET  ${CYAN}4$RESET Install"
    put 15 "  ${DIM}Nothing changes until you confirm the plan and enter your password.$RESET"
    put 16 "  ${DIM}Existing configs are backed up under ~/.dotfiles-backup/ first.$RESET"
    row=18
    if (( DRY_RUN )); then
      put "$row" "$YELLOW$BOLD$G_WARN Dry run:$RESET$YELLOW commands are shown, nothing is changed.$RESET"; ((row++))
    fi
    if (( TERM_COLS < 80 || TERM_ROWS < 24 )); then
      size_note="Terminal is ${TERM_COLS}x${TERM_ROWS}; resize to at least 80x24 for the best layout."
      put "$row" "$YELLOW$G_WARN $size_note$RESET"
    fi
    draw_footer 'Enter' 'Start' 'Esc' 'Quit'
    read_key || return 1
    case "$KEY" in
      ENTER) log_event 'Welcome accepted.'; return 0 ;;
      ESC|q|Q) return 1 ;;
    esac
  done
}

# draw_menu STEP TITLE INTRO LABELS DETAILS SELECTED -> 0 next, 1 quit, 2 back
draw_menu() {
  local step=$1 title=$2 intro=$3
  local -n labels_ref=$4 details_ref=$5 selected_ref=$6
  local cursor=0 i row line mark box label_color
  local -a wrapped=()
  while :; do
    draw_header "$title" Step "$step" 6
    put 5 "$LAVENDER$intro$RESET"
    row=7
    for i in "${!labels_ref[@]}"; do
      if (( i == cursor )); then mark="$CYAN$BOLD$G_CUR$RESET" label_color=$CYAN$BOLD; else mark=' ' label_color=$LAVENDER; fi
      if (( selected_ref[i] )); then box="$GREEN$G_ON$RESET"; else box="$DIM$G_OFF$RESET"; fi
      (( selected_ref[i] )) && (( i != cursor )) && label_color=$LAVENDER$BOLD
      put "$row" "$mark $box $label_color${labels_ref[i]}$RESET"; ((row++))
      wrap_into wrapped $((W - 6)) "${details_ref[i]}"
      for line in "${wrapped[@]}"; do put "$row" "    $DIM$line$RESET"; ((row++)); done
      ((row++))
    done
    draw_footer "$G_UPDOWN" 'Move' 'Space' 'Toggle' 'A' 'All' 'N' 'None' 'Enter' 'Next' 'B' 'Back' 'Esc' 'Quit'
    read_key || return 1
    case "$KEY" in
      UP|k|K) (( cursor > 0 )) && ((cursor--)) ;;
      DOWN|j|J) (( cursor + 1 < ${#labels_ref[@]} )) && ((cursor++)) ;;
      SPACE) selected_ref[cursor]=$((1 - selected_ref[cursor])); log_event "Toggled ${labels_ref[cursor]} to ${selected_ref[cursor]}." ;;
      a|A) for i in "${!selected_ref[@]}"; do selected_ref[i]=1; done ;;
      n|N) for i in "${!selected_ref[@]}"; do selected_ref[i]=0; done ;;
      ENTER) log_event "Completed page: $title (${selected_ref[*]})."; return 0 ;;
      b|B|BACKSPACE) return 2 ;;
      ESC|q|Q) return 1 ;;
    esac
  done
}

# Status text and color for one review row -> ST_TEXT ST_COLOR SEL
item_status() { # group index
  local g=$1 i=$2 installed=0 required=0
  ST_TEXT='' ST_COLOR=$DIM
  case "$g" in
    0) SEL=${APP_SELECTED[i]}; installed=${APP_INSTALLED[i]}
       (( i == GHOSTTY_INDEX && DESKTOP_SELECTED[0] )) && { SEL=1; required=1; } ;;
    1) SEL=${COOLER_SELECTED[i]}; installed=${COOLER_INSTALLED[i]} ;;
    2) SEL=${ASSET_SELECTED[i]} ;;
    3) SEL=${DESKTOP_SELECTED[i]} ;;
    4) SEL=${PACKAGE_SELECTED[UPDATE_INDEX]} ;;
  esac
  if (( g <= 1 )); then
    if (( installed )); then ST_TEXT="$G_OK installed" ST_COLOR=$DIM$GREEN
    elif (( SEL )); then ST_TEXT="+ install" ST_COLOR=$GREEN
    else ST_TEXT="$G_SKIP skip"
    fi
    (( required )) && ST_TEXT+=' *'
    (( g == 1 && i == COOLER_AUR_INDEX && SEL )) && ST_TEXT+=' **'
  else
    if (( SEL )); then ST_TEXT="+ apply" ST_COLOR=$GREEN; else ST_TEXT="$G_SKIP skip"; fi
  fi
}

show_selection_review() {
  local -a rg=() ri=() rl=() rcol=() rr=() hg=() hc=() hr=()
  local i g r cw lw x row cursor=${REVIEW_CURSOR:-0} mark label_color sel_count total notes_row target best dist
  for i in "${!APP_ITEMS[@]}"; do rg+=(0); ri+=("$i"); rl+=("${APP_ITEMS[i]}"); done
  for i in "${!COOLER_ITEMS[@]}"; do rg+=(1); ri+=("$i"); rl+=("${COOLER_ITEMS[i]}"); done
  for i in "${!ASSET_LABELS[@]}"; do rg+=(2); ri+=("$i"); rl+=("${ASSET_LABELS[i]}"); done
  for i in "${!DESKTOP_LABELS[@]}"; do rg+=(3); ri+=("$i"); rl+=("${DESKTOP_LABELS[i]}"); done
  rg+=(4); ri+=(0); rl+=('System update')
  # Two columns: applications and desktop themes on the left, everything else
  # on the right.
  r=7
  for g in 0 3; do
    hg+=("$g"); hc+=(0); hr+=("$r"); ((r++))
    for i in "${!rg[@]}"; do (( rg[i] == g )) && { rcol[i]=0; rr[i]=$r; ((r++)); }; done
    ((r++))
  done
  notes_row=$r
  r=7
  for g in 1 2 4; do
    hg+=("$g"); hc+=(1); hr+=("$r"); ((r++))
    for i in "${!rg[@]}"; do (( rg[i] == g )) && { rcol[i]=1; rr[i]=$r; ((r++)); }; done
    ((r++))
  done
  (( r > notes_row )) && notes_row=$r
  log_event 'Step 04/06: Review selections.'
  while :; do
    draw_header 'Review selections' Step 4 6
    cw=$(((W - 4) / 2)); lw=$((cw - 19))
    put 5 "${LAVENDER}Fine-tune individual items. Status shows what is already on this system.$RESET"
    for i in "${!hg[@]}"; do
      g=${hg[i]}
      case "$g" in
        0) sel_count=0; for x in "${APP_SELECTED[@]}"; do ((sel_count += x)); done; total=${#APP_SELECTED[@]}
           (( DESKTOP_SELECTED[0] && ! APP_SELECTED[GHOSTTY_INDEX] )) && ((sel_count++)) ;;
        1) sel_count=0; for x in "${COOLER_SELECTED[@]}"; do ((sel_count += x)); done; total=${#COOLER_SELECTED[@]} ;;
        2) sel_count=0; for x in "${ASSET_SELECTED[@]}"; do ((sel_count += x)); done; total=${#ASSET_SELECTED[@]} ;;
        3) sel_count=0; for x in "${DESKTOP_SELECTED[@]}"; do ((sel_count += x)); done; total=${#DESKTOP_SELECTED[@]} ;;
        4) sel_count=${PACKAGE_SELECTED[UPDATE_INDEX]}; total=1 ;;
      esac
      x=$((3 + hc[i] * (cw + 4)))
      at "${hr[i]}" "$x"
      printf '%s%s%s %s%d/%d%s' "$BLUE$BOLD" "${GROUP_TITLES[g]}" "$RESET" "$DIM" "$sel_count" "$total" "$RESET"
    done
    for i in "${!rg[@]}"; do
      item_status "${rg[i]}" "${ri[i]}"
      if (( i == cursor )); then mark="$CYAN$BOLD$G_CUR$RESET" label_color=$CYAN$BOLD
      elif (( SEL )); then mark=' ' label_color=$LAVENDER
      else mark=' ' label_color=$DIM
      fi
      x=$((3 + rcol[i] * (cw + 4)))
      at "${rr[i]}" "$x"
      fit "${rl[i]}" "$lw"
      if (( SEL )); then
        printf '%s %s%s%s %s %s%s%s' "$mark" "$GREEN" "$G_ON" "$RESET" "$(pad "$label_color$FIT_OUT$RESET" "$lw")" "$ST_COLOR" "$ST_TEXT" "$RESET"
      else
        printf '%s %s%s%s %s %s%s%s' "$mark" "$DIM" "$G_OFF" "$RESET" "$(pad "$label_color$FIT_OUT$RESET" "$lw")" "$ST_COLOR" "$ST_TEXT" "$RESET"
      fi
    done
    row=$notes_row
    if (( DESKTOP_SELECTED[0] )); then
      put "$row" "${CYAN}*$RESET ${DIM}Ghostty is required by the KDE Plasma configuration.$RESET"; ((row++))
    fi
    if (( COOLER_SELECTED[COOLER_AUR_INDEX] )); then
      if (( PARU_INSTALLED )); then
        put "$row" "${CYAN}**$RESET ${DIM}The AUR driver is built with paru (already installed).$RESET"
      elif (( PARU_AVAILABLE )); then
        put "$row" "${CYAN}**$RESET ${DIM}The AUR driver needs paru; it will be installed from your repositories.$RESET"
      else
        put "$row" "${RED}**$RESET ${RED}paru is not installed or in your repositories. Install paru first.$RESET"
      fi
    fi
    draw_footer "$G_ARROWS" 'Move' 'Space' 'Toggle' 'G' 'Group' 'A/N' 'All/None' 'Enter' 'Next' 'B' 'Back' 'Esc' 'Quit'
    read_key || return 1
    case "$KEY" in
      UP|k|K) (( cursor > 0 )) && ((cursor--)) ;;
      DOWN|j|J) (( cursor + 1 < ${#rg[@]} )) && ((cursor++)) ;;
      LEFT|RIGHT|h|l)
        if [[ "$KEY" == LEFT || "$KEY" == h ]]; then target=0; else target=1; fi
        if (( rcol[cursor] != target )); then
          best=-1
          for i in "${!rg[@]}"; do
            (( rcol[i] == target )) || continue
            dist=$((rr[i] - rr[cursor])); (( dist < 0 )) && dist=$((-dist))
            if (( best < 0 )) || (( dist < best )); then best=$dist; x=$i; fi
          done
          cursor=$x
        fi
        ;;
      SPACE)
        g=${rg[cursor]} i=${ri[cursor]}
        case "$g" in
          0) if (( i == GHOSTTY_INDEX && DESKTOP_SELECTED[0] )); then
               log_event 'Ghostty stays selected while KDE Plasma configuration is selected.'
             else
               APP_SELECTED[i]=$((1 - APP_SELECTED[i]))
             fi ;;
          1) COOLER_SELECTED[i]=$((1 - COOLER_SELECTED[i])) ;;
          2) ASSET_SELECTED[i]=$((1 - ASSET_SELECTED[i])) ;;
          3) DESKTOP_SELECTED[i]=$((1 - DESKTOP_SELECTED[i])) ;;
          4) PACKAGE_SELECTED[UPDATE_INDEX]=$((1 - PACKAGE_SELECTED[UPDATE_INDEX])) ;;
        esac
        log_event "Review toggle: ${rl[cursor]}."
        ;;
      g|G)
        g=${rg[cursor]}
        case "$g" in
          0) if any_selected "${APP_SELECTED[@]}"; then x=0; else x=1; fi; for i in "${!APP_SELECTED[@]}"; do APP_SELECTED[i]=$x; done ;;
          1) if any_selected "${COOLER_SELECTED[@]}"; then x=0; else x=1; fi; for i in "${!COOLER_SELECTED[@]}"; do COOLER_SELECTED[i]=$x; done ;;
          2) if any_selected "${ASSET_SELECTED[@]}"; then x=0; else x=1; fi; for i in "${!ASSET_SELECTED[@]}"; do ASSET_SELECTED[i]=$x; done ;;
          3) if any_selected "${DESKTOP_SELECTED[@]}"; then x=0; else x=1; fi; for i in "${!DESKTOP_SELECTED[@]}"; do DESKTOP_SELECTED[i]=$x; done ;;
          4) PACKAGE_SELECTED[UPDATE_INDEX]=$((1 - PACKAGE_SELECTED[UPDATE_INDEX])) ;;
        esac
        ;;
      a|A) for i in "${!APP_SELECTED[@]}"; do APP_SELECTED[i]=1; done; for i in "${!COOLER_SELECTED[@]}"; do COOLER_SELECTED[i]=1; done
           ASSET_SELECTED=(1 1); DESKTOP_SELECTED=(1 1); PACKAGE_SELECTED[UPDATE_INDEX]=1 ;;
      n|N) for i in "${!APP_SELECTED[@]}"; do APP_SELECTED[i]=0; done; for i in "${!COOLER_SELECTED[@]}"; do COOLER_SELECTED[i]=0; done
           ASSET_SELECTED=(0 0); DESKTOP_SELECTED=(0 0); PACKAGE_SELECTED[UPDATE_INDEX]=0 ;;
      ENTER) REVIEW_CURSOR=$cursor; log_event 'Selection review confirmed.'; return 0 ;;
      b|B|BACKSPACE) REVIEW_CURSOR=$cursor; return 2 ;;
      ESC|q|Q) return 1 ;;
    esac
  done
}

# ── Plan ────────────────────────────────────────────────────────────────────

PLAN_LINES=() PLAN_BLOCKERS=()
PLAN_LABEL_W=22
plan_row() { # kind label value [more values...]
  local kind=$1 label=$2 icon color value first=1 line
  shift 2
  local -a wrapped=()
  case "$kind" in
    ok) icon=$G_OK color=$GREEN ;;
    skip) icon=$G_SKIP color=$DIM ;;
    warn) icon=$G_WARN color=$YELLOW ;;
    block) icon=$G_FAIL color=$RED ;;
  esac
  local value_w=$((W - 4 - 2 - PLAN_LABEL_W))
  for value in "$@"; do
    if (( first )); then
      wrap_into wrapped "$value_w" "$value"
      PLAN_LINES+=("$color$icon$RESET $(pad "$LAVENDER$BOLD$label$RESET" "$PLAN_LABEL_W")$LAVENDER${wrapped[0]}$RESET")
    else
      wrap_into wrapped "$value_w" "$G_SUB $value" '  '
      PLAN_LINES+=("  $(pad '' "$PLAN_LABEL_W")$DIM${wrapped[0]}$RESET")
    fi
    for line in "${wrapped[@]:1}"; do
      PLAN_LINES+=("  $(pad '' "$PLAN_LABEL_W")$( ((first)) && printf '%s' "$LAVENDER" || printf '%s' "$DIM")$line$RESET")
    done
    first=0
  done
}

join_by() { local sep=$1 out='' x; shift; for x in "$@"; do out+="${out:+$sep}$x"; done; printf '%s' "$out"; }

build_plan() {
  local i problem
  local -a list=() notes=()
  PLAN_LINES=() PLAN_BLOCKERS=()

  if (( PACKAGE_SELECTED[UPDATE_INDEX] )); then
    plan_row ok 'System update' 'pacman -Syu (full system upgrade, runs first)'
  else
    plan_row skip 'System update' 'not selected; package installs still sync and upgrade (pacman -Syu --needed)'
  fi

  list=()
  for i in "${!APP_ITEMS[@]}"; do
    if (( APP_SELECTED[i] )) || (( i == GHOSTTY_INDEX && DESKTOP_SELECTED[0] )); then list+=("${APP_ITEMS[i]}"); fi
  done
  ((${#list[@]})) && plan_row ok 'Applications' "$(join_by ', ' "${list[@]}")"

  list=() notes=()
  for i in "${!COOLER_ITEMS[@]}"; do (( COOLER_SELECTED[i] )) && list+=("${COOLER_ITEMS[i]}"); done
  if ((${#list[@]})); then
    if (( COOLER_SELECTED[COOLER_AUR_INDEX] )); then
      if (( PARU_INSTALLED )); then notes+=('AUR driver built with paru (installed)')
      elif (( PARU_AVAILABLE )); then notes+=('paru installed from your repositories for the AUR driver')
      else PLAN_BLOCKERS+=('paru is not installed and not in your repositories. Install paru first, or deselect nct6687d-dkms-git.')
      fi
      notes+=('matching kernel headers for the DKMS sensor module')
    fi
    (( COOLER_SELECTED[COOLER_DAEMON_INDEX] )) && notes+=('profile to /etc/coolercontrol/config.toml (backup kept), daemon enabled')
    plan_row ok 'CoolerControl' "$(join_by ', ' "${list[@]}")" "${notes[@]}"
  fi

  list=()
  (( ASSET_SELECTED[0] )) && list+=('wallpapers into ~/Pictures/Wallpapers')
  (( ASSET_SELECTED[1] )) && list+=('cursor themes into ~/.icons')
  ((${#list[@]})) && plan_row ok 'Desktop assets' "$(join_by ', ' "${list[@]}")"

  if (( DESKTOP_SELECTED[0] )); then
    local deps
    if (( KDE_OXYGEN_INSTALLED )); then deps='oxygen: installed'; else deps='oxygen: will install'; fi
    if (( APP_INSTALLED[GHOSTTY_INDEX] )); then deps+=" $G_SEP ghostty: installed"; else deps+=" $G_SEP ghostty: will install"; fi
    if (( ASSET_SELECTED[1] )); then deps+=" $G_SEP Empty-Butterfly-Purple cursor 48px"; else deps+=" $G_SEP cursor unchanged"; fi
    notes=("$deps")
    notes+=("Ghostty terminal (Super+X, Ctrl+Alt+T) $G_SEP Num Lock on $G_SEP PTT mouse buttons")
    notes+=("wallpaper slideshow, login and lock screen $G_SEP old configs to ~/.dotfiles-backup/")
    plan_row ok 'KDE Plasma' "Oxygen style $G_SEP Breeze Dark $G_SEP Violet-Noir accent" "${notes[@]}"
    problem=$(kde_session_problem)
    if [[ -n "$problem" ]]; then
      if (( DRY_RUN )); then
        plan_row warn 'KDE session' "$problem The dry run continues; a real run would stop here."
      else
        PLAN_BLOCKERS+=("$problem KDE Plasma configuration must run inside your Plasma session.")
      fi
    fi
  fi

  if (( DESKTOP_SELECTED[DANK_INDEX] )); then
    if (( ADW_GTK_INSTALLED )); then notes=('adw-gtk-theme: installed'); else notes=('adw-gtk-theme: will install'); fi
    notes+=("Ghostty $G_SEP dms-greeter, dsearch, dcal $G_SEP existing Hyprland config backed up, then replaced")
    notes+=("runs: curl -fsSL $DUX_INSTALL_URL | sh -s -- ${DUX_INSTALL_ARGS[*]}")
    plan_row ok 'Dank Shell' 'Hyprland session with Dank Shell, installed headless by duxinstall' "${notes[@]}"
    case "$(uname -m)" in
      x86_64|aarch64) ;;
      *) PLAN_BLOCKERS+=("duxinstall supports only x86_64 and aarch64, not $(uname -m). Deselect Dank Shell.") ;;
    esac
  fi

  if ! any_selected "${APP_SELECTED[@]}" "${COOLER_SELECTED[@]}" "${ASSET_SELECTED[@]}" "${DESKTOP_SELECTED[@]}"; then
    if (( PACKAGE_SELECTED[UPDATE_INDEX] )); then
      plan_row skip 'Optional items' 'none selected; only the system update will run'
    else
      PLAN_BLOCKERS+=('Nothing is selected. Go back and choose at least one item.')
    fi
  fi
  for problem in "${PLAN_BLOCKERS[@]}"; do plan_row block 'Cannot continue' "$problem"; done
  return 0
}

show_plan() {
  log_event 'Step 05/06: Review the plan.'
  build_plan
  PAGER_START=0
  while :; do
    draw_header 'Review the plan' Step 5 6
    put 5 "${LAVENDER}This run will:$RESET"
    pager_draw PLAN_LINES 7 $((BODY_LAST - 1))
    if ((${#PLAN_BLOCKERS[@]})); then
      put "$BODY_LAST" "$RED$G_FAIL Resolve the ${#PLAN_BLOCKERS[@]} problem(s) marked $G_FAIL to continue. B goes back.$RESET"
      draw_footer "$G_UPDOWN" 'Scroll' 'B' 'Back' 'Esc' 'Quit'
    else
      put "$BODY_LAST" "${CYAN}Next: enter your password, then installation starts.$RESET"
      draw_footer "$G_UPDOWN" 'Scroll' 'Enter' 'Continue' 'B' 'Back' 'Esc' 'Quit'
    fi
    read_key || return 1
    pager_scroll "$KEY" && continue
    case "$KEY" in
      ENTER) ((${#PLAN_BLOCKERS[@]})) && continue; log_event 'Plan confirmed.'; return 0 ;;
      b|B|BACKSPACE) return 2 ;;
      ESC|q|Q) return 1 ;;
    esac
  done
}

# ── Authentication ──────────────────────────────────────────────────────────

draw_auth_page() { # masked-length message message-color
  local length=$1 message=$2 mcolor=${3:-$CYAN} bw shown label=' sudo password '
  draw_header 'Authenticate' Step 6 6
  bw=$((W < 52 ? W : 52))
  if (( DRY_RUN )); then
    put 5 "${YELLOW}Dry run: nothing is installed, so the password is not checked.$RESET"
    put 6 "${DIM}Press Enter to continue.$RESET"
  else
    put 5 "${LAVENDER}Installation needs administrator rights.$RESET"
    put 6 "${DIM}Your password is passed only to sudo and is never logged or stored.$RESET"
  fi
  put 8 "$PURPLE$G_TL$G_H$RESET$DIM$label$RESET$PURPLE${HBAR:0:bw-3-${#label}}$G_TR$RESET"
  if (( length > 0 )); then
    shown=$length; (( shown > bw - 4 )) && shown=$((bw - 4))
    repeat_glyph "$G_MASK" "$shown"
    put 9 "$PURPLE$G_V$RESET $(pad "$LAVENDER$REPEAT_OUT$RESET" $((bw - 4))) $PURPLE$G_V$RESET"
  else
    put 9 "$PURPLE$G_V$RESET $(pad "${DIM}type your password$RESET" $((bw - 4))) $PURPLE$G_V$RESET"
  fi
  put 10 "$PURPLE$G_BL${HBAR:0:bw-2}$G_BR$RESET"
  [[ -z "$message" ]] || put 12 "$mcolor$message$RESET"
  draw_footer 'Enter' 'Authenticate' 'Esc' 'Back' 'Ctrl+C' 'Quit'
}

show_authentication() {
  local password='' message='' mcolor=$CYAN auth_pid auth_rc spin=0
  log_event 'Step 06/06: Authentication.'
  while :; do
    draw_auth_page "${#password}" "$message" "$mcolor"
    read_key || return 1
    case "$KEY" in
      ENTER)
        if (( DRY_RUN )); then password=''; log_event 'Dry run: authentication skipped.'; return 0; fi
        if [[ -z "$password" ]]; then message='Enter your sudo password to continue.' mcolor=$YELLOW; continue; fi
        log_event 'Validating sudo credentials.'
        # Validate in the background so the spinner keeps moving. The password
        # travels through a pipe: never argv, the environment, or the log.
        { printf '%s\n' "$password" | sudo -S -p '' -v >/dev/null 2>&1; } &
        auth_pid=$!
        password=''
        while kill -0 "$auth_pid" 2>/dev/null; do
          put 12 "$CYAN${SPINNER[spin % ${#SPINNER[@]}]} Checking with sudo$G_ELLIPSIS$RESET"
          ((spin++))
          sleep 0.08
        done
        auth_rc=0
        wait "$auth_pid" || auth_rc=$?
        if (( auth_rc == 0 )); then log_event 'Sudo authentication succeeded.'; return 0; fi
        log_event "Sudo authentication failed (status $auth_rc)."
        message="$G_FAIL Sudo did not accept that password. Try again." mcolor=$RED
        ;;
      ESC) password=''; return 2 ;;
      BACKSPACE) password=${password%?}; message='' ;;
      SPACE) password+=' '; message='' ;;
      CTRL_D|UP|DOWN|LEFT|RIGHT|PGUP|PGDN|HOME|END|IGNORE|CTRL_C) : ;;
      *) [[ ${#KEY} == 1 && "$KEY" == [[:print:]] ]] && { password+=$KEY; message=''; } ;;
    esac
  done
}

start_sudo_keepalive() {
  (( DRY_RUN )) && return 0
  local parent=$$
  # Refresh the sudo timestamp while installation runs; Arch's default sudo
  # timeout is 5 minutes, shorter than many updates or AUR builds.
  ( while sleep 45; do
      kill -0 "$parent" 2>/dev/null || exit 0
      sudo -n -v 2>/dev/null || exit 0
    done ) </dev/null >/dev/null 2>&1 &
  SUDO_KEEPALIVE_PID=$!
  log_event "Sudo keepalive started (pid $SUDO_KEEPALIVE_PID)."
}

# ── Log viewer and completion ──────────────────────────────────────────────

LOG_VIEW=()
load_log_view() {
  local line
  local -a raw=() wrapped=()
  LOG_VIEW=()
  mapfile -t raw < "$LOG_FILE"
  for line in "${raw[@]}"; do
    wrap_into wrapped $((W - 2)) "$line" '           '
    LOG_VIEW+=("${wrapped[@]}")
  done
  ((${#LOG_VIEW[@]})) || LOG_VIEW=('No log entries yet.')
}

show_log_viewer() {
  local saved=$PAGER_START
  load_log_view
  PAGER_START=-1
  while :; do
    draw_header 'Full log'
    pager_draw LOG_VIEW 5 $((BODY_LAST - 1))
    put "$BODY_LAST" "${DIM}File: $LOG_FILE$RESET"
    draw_footer "$G_UPDOWN" 'Scroll' 'PgUp/PgDn' 'Page' 'Home/End' 'Jump' 'Esc' 'Back'
    read_key || break
    pager_scroll "$KEY" && continue
    case "$KEY" in ESC|CTRL_D|q|Q|ENTER|b|B) break ;; esac
  done
  PAGER_START=$saved
}

show_completion() {
  local i icon color status title outcome=ok
  local -a lines=()
  for i in "${!PHASE_TITLES[@]}"; do
    case "${PHASE_STATE[i]}" in
      ok) icon=$G_OK color=$GREEN status="done in ${PHASE_TIME[i]}" ;;
      fail) icon=$G_FAIL color=$RED status="failed (exit ${PHASE_RC[i]}) after ${PHASE_TIME[i]}"; outcome=fail ;;
      skip) icon=$G_SKIP color=$DIM status='not selected' ;;
      stopped) icon=$G_SKIP color=$YELLOW status='not run'; [[ "$outcome" == ok ]] && outcome=stopped ;;
      *) icon=$G_SKIP color=$DIM status='not run' ;;
    esac
    lines+=("$color$icon$RESET $(pad "$LAVENDER${PHASE_TITLES[i]}$RESET" 28)$color$status$RESET")
  done
  lines+=('')
  if [[ -n "$REBOOT_REASON" ]]; then lines+=("$YELLOW$G_REBOOT $REBOOT_REASON$RESET"); fi
  if [[ "${PHASE_STATE[5]}" == ok ]]; then lines+=("$DIM$G_INFO Log out and back in to see every KDE change.$RESET"); fi
  if [[ "${PHASE_STATE[6]}" == ok ]]; then lines+=("$DIM$G_INFO Log out and choose the Hyprland session to start Dank Shell.$RESET"); fi
  (( DRY_RUN )) && lines+=("$YELLOW$G_WARN Dry run: nothing was changed.$RESET")
  case "$outcome" in
    ok) title='Finished' ;;
    fail) title='Finished with errors' ;;
    stopped) title='Stopped' ;;
  esac
  log_event "Run finished: $outcome."
  PAGER_START=0
  while :; do
    draw_header "$title"
    case "$outcome" in
      ok) put 5 "$GREEN$BOLD$G_OK Selected setup actions completed.$RESET" ;;
      fail) put 5 "$RED$BOLD$G_FAIL Some steps failed. Open the full log for details.$RESET" ;;
      stopped) put 5 "$YELLOW$BOLD$G_WARN Stopped at your request. Remaining steps were not run.$RESET" ;;
    esac
    pager_draw lines 7 $((BODY_LAST - 1))
    put "$BODY_LAST" "${DIM}Log: $LOG_FILE$RESET"
    draw_footer 'Ctrl+D' 'Full log' 'Enter' 'Exit'
    read_key || return 0
    case "$KEY" in
      CTRL_D|l|L) show_log_viewer ;;
      ENTER|ESC|q|Q|CTRL_C) return 0 ;;
    esac
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# Install step frame
# ─────────────────────────────────────────────────────────────────────────────

FRAME_LINES=() FRAME_NUM=0 FRAME_TITLE='' FRAME_STATUS='' FRAME_STATUS_COLOR=''

frame_line_color() {
  case "$1" in
    "$G_OK "*) FRAME_COLOR=$GREEN ;;
    "$G_FAIL "*) FRAME_COLOR=$RED ;;
    "$G_WARN "*|warning:*|*' warning: '*) FRAME_COLOR=$YELLOW ;;
    "$G_RUN "*) FRAME_COLOR=$CYAN ;;
    "$G_INFO "*|'::'*) FRAME_COLOR=$BLUE ;;
    *) case "${1,,}" in
         *error*|*failed*|*failure*|*denied*|*'not found'*) FRAME_COLOR=$RED ;;
         *) FRAME_COLOR=$LAVENDER ;;
       esac ;;
  esac
}

draw_frame_box() {
  local visible=$1 label=' Output '
  put 5 "$PURPLE$G_TL$G_H$RESET$DIM$label$RESET$PURPLE${HBAR:0:W-3-${#label}}$G_TR$RESET"
  local i
  for ((i = 1; i <= visible; i++)); do
    printf '\e[%d;1H\e[2K  %s%s%s\e[%d;%dH%s%s%s' $((5 + i)) "$PURPLE" "$G_V" "$RESET" $((5 + i)) $((W + 2)) "$PURPLE" "$G_V" "$RESET"
  done
  put $((6 + visible)) "$PURPLE$G_BL${HBAR:0:W-2}$G_BR$RESET"
}

draw_frame_rows() {
  local visible=$1 start i line inner=$((W - 4)) out=''
  start=$((${#FRAME_LINES[@]} - visible))
  (( start < 0 )) && start=0
  for ((i = 0; i < visible; i++)); do
    line=${FRAME_LINES[start + i]:-}
    frame_line_color "$line"
    pad_v PADDED "$FRAME_COLOR$line$RESET" "$inner"
    out+=$'\e['"$((6 + i));5H$PADDED"
  done
  # One write per redraw so the terminal never shows a half-updated frame.
  printf '%s' "$out"
}

draw_frame_status() { # visible text color
  put $((7 + $1)) "$3$2$RESET"
}

redraw_frame() {
  local visible=$((TERM_ROWS - 11))
  (( visible < 3 )) && visible=3
  draw_header "${FRAME_TITLE}" Install "$FRAME_NUM" "$PHASE_COUNT"
  draw_frame_box "$visible"
  draw_frame_rows "$visible"
  draw_frame_status "$visible" "$FRAME_STATUS" "$FRAME_STATUS_COLOR"
}

format_elapsed() { printf '%d:%02d' $(($1 / 60)) $(($1 % 60)); }

clean_output_line() { # text -> CLEAN_LINE without terminal control sequences
  local s=${1%$'\r'}
  s=${s##*$'\r'}
  s=${s//$'\e'\[*([0-9;?])[A-Za-z]/}
  s=${s//$'\e'\]*([^$'\a'])$'\a'/}
  s=${s//$'\t'/    }
  s=${s//[$'\001'-$'\037'$'\177']/}
  CLEAN_LINE=$s
}

# run_step NUMBER TITLE FUNCTION -> exit status of FUNCTION
run_step() {
  local num=$1 title=$2 fn=$3
  local visible fd pid rc=0 read_rc line pending='' started=$SECONDS spin=0 dirty=1 burst key
  local -a wrapped=()
  ui_metrics
  visible=$((TERM_ROWS - 11))
  (( visible < 3 )) && visible=3
  FRAME_LINES=() FRAME_NUM=$num FRAME_TITLE=$title
  FRAME_STATUS='' FRAME_STATUS_COLOR=$CYAN
  log_event "Install step $num/$PHASE_COUNT started: $title."
  draw_header "$title" Install "$num" "$PHASE_COUNT"
  draw_frame_box "$visible"
  draw_footer 'Ctrl+C' 'Stop after this step'

  # stdin is /dev/null so a prompt fails immediately instead of hanging.
  coproc STEP_CMD { step_entry "$fn" </dev/null 2>&1; }
  exec {fd}<&"${STEP_CMD[0]}"
  pid=$STEP_CMD_PID

  while :; do
    burst=0
    while :; do
      if IFS= read -r -t 0.12 -u "$fd" line; then read_rc=0; else read_rc=$?; fi
      if (( read_rc > 128 )); then pending+=$line; break; fi
      line="$pending$line" pending=''
      if (( read_rc == 0 )) || [[ -n "$line" ]]; then
        log_event "  $line"
        clean_output_line "$line"
        if [[ -n "${CLEAN_LINE//[[:space:]]/}" ]]; then
          wrap_into wrapped $((W - 4)) "$CLEAN_LINE" '  '
          FRAME_LINES+=("${wrapped[@]}")
          dirty=1
        fi
      fi
      (( read_rc != 0 )) && break
      (( ++burst >= 300 )) && break
      read -t 0 -u "$fd" || break
    done
    if (( ${#FRAME_LINES[@]} > 4000 )); then FRAME_LINES=("${FRAME_LINES[@]: -2000}"); fi
    if read -t 0 -u 0 2>/dev/null && IFS= read -rsn1 -u 0 key; then
      if [[ "$key" == $'\x03' ]] && (( ! STOP_REQUESTED )); then
        STOP_REQUESTED=1
        log_event 'Stop requested; finishing the current step.'
      fi
    fi
    (( dirty )) && { draw_frame_rows "$visible"; dirty=0; }
    if (( STOP_REQUESTED )); then
      FRAME_STATUS="${SPINNER[spin % ${#SPINNER[@]}]} $title $G_SEP $(format_elapsed $((SECONDS - started))) $G_SEP stopping after this step$G_ELLIPSIS"
      FRAME_STATUS_COLOR=$YELLOW
    else
      FRAME_STATUS="${SPINNER[spin % ${#SPINNER[@]}]} $title $G_SEP $(format_elapsed $((SECONDS - started)))"
    fi
    draw_frame_status "$visible" "$FRAME_STATUS" "$FRAME_STATUS_COLOR"
    ((spin++))
    (( read_rc == 1 )) && break
  done
  exec {fd}<&-
  wait "$pid" || rc=$?

  PHASE_TIME[num-1]=$(format_elapsed $((SECONDS - started)))
  PHASE_RC[num-1]=$rc
  if ((${#FRAME_LINES[@]} == 0)); then FRAME_LINES=('(no output)'); draw_frame_rows "$visible"; fi
  if (( rc == 0 )); then
    PHASE_STATE[num-1]=ok
    FRAME_STATUS="$G_OK ${PHASE_DONE_TEXT[num-1]} (${PHASE_TIME[num-1]})" FRAME_STATUS_COLOR=$GREEN
    log_event "Install step $num/$PHASE_COUNT completed: $title (${PHASE_TIME[num-1]})."
  else
    PHASE_STATE[num-1]=fail
    FRAME_STATUS="$G_FAIL $title failed (exit $rc) after ${PHASE_TIME[num-1]}" FRAME_STATUS_COLOR=$RED
    log_event "ERROR: install step $num/$PHASE_COUNT failed: $title (exit $rc)."
  fi
  draw_frame_status "$visible" "$FRAME_STATUS" "$FRAME_STATUS_COLOR"
  return "$rc"
}

step_entry() {
  if (( ! DRY_RUN )); then
    sudo -n -v 2>/dev/null || { error 'Sudo authorization expired; nothing was run.'; return 1; }
  fi
  "$@"
}

# After a step: brief pause on success, explicit choice on failure.
# Returns 0 to continue, 1 to stop the run.
after_step() {
  local num=$1 rc=$2 key
  if (( rc == 0 )); then
    (( STOP_REQUESTED )) && return 1
    draw_footer 'Ctrl+C' 'Stop' 'Any key' 'Skip pause'
    if IFS= read -rsn1 -t 1.2 key && [[ "$key" == $'\x03' ]]; then STOP_REQUESTED=1; return 1; fi
    return 0
  fi
  while :; do
    if (( PHASE_FATAL[num-1] )); then
      draw_footer 'Ctrl+D' 'Full log' 'Enter' 'Finish'
    else
      draw_footer 'Ctrl+D' 'Full log' 'Enter' 'Continue with remaining steps' 'Esc' 'Stop here'
    fi
    read_key || return 1
    case "$KEY" in
      CTRL_D|l|L) show_log_viewer; redraw_frame ;;
      ENTER) (( PHASE_FATAL[num-1] )) && return 1; (( STOP_REQUESTED )) && return 1; return 0 ;;
      ESC|CTRL_C|q|Q) STOP_REQUESTED=1; return 1 ;;
    esac
  done
}

phase_enabled() {
  case "$1" in
    1) (( PACKAGE_SELECTED[UPDATE_INDEX] )) ;;
    2) any_selected "${APP_SELECTED[@]}" "${COOLER_SELECTED[@]:0:3}" "${DESKTOP_SELECTED[@]}" \
         || { (( COOLER_SELECTED[COOLER_AUR_INDEX] && ! PARU_INSTALLED )); } ;;
    3) (( COOLER_SELECTED[COOLER_AUR_INDEX] )) ;;
    4) (( COOLER_SELECTED[COOLER_DAEMON_INDEX] )) ;;
    5) any_selected "${ASSET_SELECTED[@]}" ;;
    6) (( DESKTOP_SELECTED[0] )) ;;
    7) (( DESKTOP_SELECTED[DANK_INDEX] )) ;;
  esac
}

run_installation_phases() {
  local num rc stop=0
  disable_interrupt_key
  start_sudo_keepalive
  for ((num = 1; num <= PHASE_COUNT; num++)); do
    if ! phase_enabled "$num"; then PHASE_STATE[num-1]=skip; continue; fi
    if (( stop )); then PHASE_STATE[num-1]=stopped; continue; fi
    rc=0
    run_step "$num" "${PHASE_TITLES[num-1]}" "${PHASE_FUNCS[num-1]}" || rc=$?
    if (( rc == 0 )) && (( num <= 3 || num == 7 )); then check_reboot_needed; fi
    after_step "$num" "$rc" || stop=1
  done
}

check_reboot_needed() {
  (( DRY_RUN )) && return 0
  if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
    REBOOT_REASON='A new kernel was installed. Reboot to start it and load its DKMS modules.'
  elif (( COOLER_SELECTED[COOLER_AUR_INDEX] )) && ! lsmod 2>/dev/null | grep -q '^nct6687 '; then
    REBOOT_REASON='Reboot (or run: sudo modprobe nct6687) to load the MSI sensor driver.'
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Install steps (run inside the frame; output is captured and logged)
# ─────────────────────────────────────────────────────────────────────────────

update_system_packages() {
  info 'Updating system packages with pacman -Syu.'
  pacman_root -Syu
}

install_selected_pacman_packages() {
  local i
  local -a packages=()
  for i in "${!APP_ITEMS[@]}"; do
    if (( APP_SELECTED[i] )); then
      packages+=("${APP_ITEMS[i]}")
    elif (( i == GHOSTTY_INDEX && DESKTOP_SELECTED[0] )); then
      packages+=(ghostty)
      info 'Including Ghostty; the KDE Plasma configuration needs it.'
    fi
  done
  for i in 0 1 2; do (( COOLER_SELECTED[i] )) && packages+=("${COOLER_ITEMS[i]}"); done
  if (( COOLER_SELECTED[COOLER_AUR_INDEX] )) && ! command -v paru >/dev/null 2>&1; then
    packages+=(paru)
    info 'Including paru from your repositories for the AUR sensor driver.'
  fi
  (( DESKTOP_SELECTED[0] )) && packages+=(oxygen)
  (( DESKTOP_SELECTED[DANK_INDEX] )) && packages+=(adw-gtk-theme)
  if ((${#packages[@]} == 0)); then
    info 'No pacman packages selected.'
    return 0
  fi
  split_installed "${packages[@]}"
  if ((${#MISSING_PACKAGES[@]} == 0)); then
    success "Already installed: ${packages[*]}"
    return 0
  fi
  ((${#INSTALLED_PACKAGES[@]})) && info "Already installed, skipped: ${INSTALLED_PACKAGES[*]}"
  if (( ! PACKAGE_SELECTED[UPDATE_INDEX] )); then
    info 'Syncing and upgrading in the same transaction (pacman -Syu --needed).'
  fi
  info "Installing: ${MISSING_PACKAGES[*]}"
  pacman_install "${MISSING_PACKAGES[@]}"
}

ensureParu() {
  if command -v paru >/dev/null 2>&1; then return 0; fi
  if (( DRY_RUN )) && (( PARU_AVAILABLE )); then dry_note 'paru would have been installed in the pacman step.'; return 0; fi
  if pacman -Si paru >/dev/null 2>&1; then
    info 'paru is missing; installing it from your repositories.'
    pacman_install paru || return 1
    (( DRY_RUN )) || command -v paru >/dev/null 2>&1 || { error 'paru is still unavailable after installation.'; return 1; }
    return 0
  fi
  error 'paru is not installed and is not in your configured repositories. Install paru, then run this again.'
  return 1
}

installKernelHeadersForDkms() {
  local pkgbase_file pkgbase headers_package found_kernel=no
  local -a header_packages=()
  local -A seen_headers=()
  for pkgbase_file in /usr/lib/modules/*/pkgbase; do
    [[ -r "$pkgbase_file" ]] || continue
    IFS= read -r pkgbase < "$pkgbase_file"
    [[ -n "$pkgbase" ]] || continue
    found_kernel=yes
    headers_package="${pkgbase}-headers"
    [[ -n "${seen_headers[$headers_package]:-}" ]] && continue
    seen_headers[$headers_package]=yes
    pacman -Qq "$headers_package" >/dev/null 2>&1 && continue
    if ! pacman -Si "$headers_package" >/dev/null 2>&1; then
      error "Headers package $headers_package is not available for installed kernel $pkgbase. Install matching headers, then run this again."
      return 1
    fi
    header_packages+=("$headers_package")
  done
  # dkms is the driver's one repository dependency; installing it here keeps
  # paru from pulling it from unsynced package databases.
  pacman -Qq dkms >/dev/null 2>&1 || header_packages+=(dkms)
  if [[ "$found_kernel" != yes ]]; then
    error 'Could not determine installed kernel packages under /usr/lib/modules.'
    return 1
  fi
  if ((${#header_packages[@]})); then
    info "Installing for DKMS: ${header_packages[*]}"
    pacman_install "${header_packages[@]}"
  else
    success 'Matching kernel headers are already installed.'
  fi
}

installAurPackages() {
  ((${#@})) || return 0
  installKernelHeadersForDkms || return 1
  ensureParu || return 1
  info "Building with paru: $*"
  run paru -S --needed --noconfirm --skipreview "$@"
}

install_selected_cooling_aur() {
  installAurPackages "${AUR_COOLING_PACKAGES[@]}"
}

applyCoolerControlConfig() {
  local tmp backup
  tmp=$(mktemp "${TMPDIR:-/tmp}/coolercontrol.XXXXXXXX") || return 1
  info 'Downloading the CoolerControl profile from DESetupLinux.'
  if ! curl -fsSL "$COOLERCONTROL_CONFIG_URL" -o "$tmp" || ! grep -qE '^[[:space:]]*\[' "$tmp"; then
    rm -f -- "$tmp"; error 'Could not download a valid CoolerControl TOML profile.'; return 1
  fi
  success "Profile downloaded and looks like TOML ($(wc -l < "$tmp") lines)."
  as_root systemctl stop coolercontrold 2>/dev/null || true
  as_root install -d -m 0755 /etc/coolercontrol || { rm -f -- "$tmp"; return 1; }
  if sudo -n test -e /etc/coolercontrol/config.toml 2>/dev/null; then
    backup="/etc/coolercontrol/config.toml.backup.$(date +%Y%m%d-%H%M%S)"
    as_root cp -a /etc/coolercontrol/config.toml "$backup" || { rm -f -- "$tmp"; return 1; }
    info "Backed up the existing profile to $backup"
  fi
  as_root install -m 0644 "$tmp" /etc/coolercontrol/config.toml || { rm -f -- "$tmp"; return 1; }
  rm -f -- "$tmp"
  as_root systemctl enable --now coolercontrold || return 1
  success 'CoolerControl profile applied; coolercontrold enabled and started.'
}

install_selected_desktop_assets() {
  local scratch wallpaper count=0
  need_cmd git 'git is required to download desktop assets.' || return 1
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/desktop-assets.XXXXXXXX") || return 1
  info 'Downloading DESetupLinux.'
  if ! git clone --depth=1 --quiet "$DESETUP_REPO" "$scratch/DESetupLinux"; then
    rm -rf -- "$scratch"; error 'Could not download DESetupLinux.'; return 1
  fi
  if (( ASSET_SELECTED[0] )); then
    [[ -d "$scratch/DESetupLinux/Wallpapers" ]] || { rm -rf -- "$scratch"; error 'DESetupLinux has no Wallpapers directory.'; return 1; }
    run mkdir -p "$HOME/Pictures/Wallpapers" || { rm -rf -- "$scratch"; return 1; }
    for wallpaper in "$scratch/DESetupLinux/Wallpapers"/* "$scratch/DESetupLinux/Wallpapers"/.[!.]* "$scratch/DESetupLinux/Wallpapers"/..?*; do
      [[ -e "$wallpaper" || -L "$wallpaper" ]] || continue
      [[ "${wallpaper##*/}" == Archive ]] && continue
      if (( DRY_RUN )); then ((count++)); continue; fi
      cp -a -- "$wallpaper" "$HOME/Pictures/Wallpapers/" || { rm -rf -- "$scratch"; error "Could not copy ${wallpaper##*/}."; return 1; }
      ((count++))
    done
    if (( DRY_RUN )); then dry_note "would copy $count wallpaper entries into ~/Pictures/Wallpapers"
    else success "Copied $count wallpaper entries into ~/Pictures/Wallpapers."; fi
  fi
  if (( ASSET_SELECTED[1] )); then
    [[ -d "$scratch/DESetupLinux/.icons" ]] || { rm -rf -- "$scratch"; error 'DESetupLinux has no .icons directory.'; return 1; }
    run mkdir -p "$HOME/.icons" || { rm -rf -- "$scratch"; return 1; }
    if (( DRY_RUN )); then
      dry_note "would copy cursor themes: $(cd "$scratch/DESetupLinux/.icons" && printf '%s ' *)"
    else
      cp -a "$scratch/DESetupLinux/.icons/." "$HOME/.icons/" || { rm -rf -- "$scratch"; error 'Could not copy cursor themes.'; return 1; }
      success 'Copied cursor themes into ~/.icons.'
    fi
  fi
  rm -rf -- "$scratch"
  success 'Desktop assets done; unrelated files in those folders were left alone.'
}

# kwriteconfig6 wrapper that counts failures instead of ignoring them.
KW_FAILURES=0
kw() {
  if ! run kwriteconfig6 "$@"; then
    ((KW_FAILURES++))
    error "kwriteconfig6 failed: $(quote_cmd "$@")"
  fi
}
kw_root() {
  if ! as_root kwriteconfig6 "$@"; then
    ((KW_FAILURES++))
    error "kwriteconfig6 (root) failed: $(quote_cmd "$@")"
  fi
}

applyKdePlasmaConfig() {
  local problem backup_dir name cursor_theme_found=no output configured
  local wallpaper_dir="$HOME/Pictures/Wallpapers" wallpaper_source='' lock_wallpaper_url
  local -a cursor_theme_paths=(
    "$HOME/.icons/Empty-Butterfly-Purple"
    "$HOME/.local/share/icons/Empty-Butterfly-Purple"
    '/usr/share/icons/Empty-Butterfly-Purple'
  )
  KW_FAILURES=0

  problem=$(kde_session_problem)
  if [[ -n "$problem" ]]; then
    if (( DRY_RUN )); then warn "$problem (dry run continues)"; else error "$problem No KDE changes were made."; return 1; fi
  fi
  need_cmd kwriteconfig6 'kwriteconfig6 is unavailable (KDE configuration utilities).' || return 1
  need_cmd kreadconfig6 'kreadconfig6 is unavailable; settings cannot be verified.' || return 1
  need_cmd plasma-apply-colorscheme 'plasma-apply-colorscheme is unavailable.' || return 1
  need_cmd plasma-apply-lookandfeel 'plasma-apply-lookandfeel is unavailable.' || return 1

  for name in "${cursor_theme_paths[@]}"; do [[ -d "$name" ]] && { cursor_theme_found=yes; break; }; done
  if (( ASSET_SELECTED[1] )) && [[ "$cursor_theme_found" != yes ]] && (( ! DRY_RUN )); then
    error 'The Empty-Butterfly-Purple cursor theme was not found after the Desktop assets step.'
    return 1
  fi
  (( DRY_RUN && ASSET_SELECTED[1] )) && cursor_theme_found=yes

  backup_dir="$HOME/.dotfiles-backup/kde-appearance-$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$backup_dir" || return 1
  for name in kdeglobals kcminputrc kwinrc plasmarc kglobalshortcutsrc kscreenlockerrc plasma-org.kde.plasma.desktop-appletsrc; do
    [[ -f "$HOME/.config/$name" ]] && { run cp -a -- "$HOME/.config/$name" "$backup_dir/$name" || return 1; }
  done
  [[ -r /etc/plasmalogin.conf ]] && { run cp -a -- /etc/plasmalogin.conf "$backup_dir/plasmalogin.conf" || return 1; }
  success "Backed up current KDE configuration to $backup_dir"

  info 'Applying the Oxygen global theme.'
  # Apply Oxygen through KDE first so its defaults are recorded before the
  # individual components and Breeze Dark colors are set below.
  run plasma-apply-lookandfeel --apply org.kde.oxygen || { error 'Could not apply the Oxygen global theme.'; return 1; }
  kw --file kdeglobals --group KDE --key widgetStyle Oxygen
  kw --file plasmarc --group Theme --key name oxygen
  # Lock screen theme: Theme for older Plasma, LookAndFeel for Plasma 6.
  kw --file kscreenlockerrc --group Greeter --key Theme org.kde.oxygen
  kw --file kscreenlockerrc --group Greeter --key LookAndFeel org.kde.oxygen

  info 'Applying Breeze Dark and the Violet-Noir accent.'
  # Some Plasma versions exit nonzero when the scheme is already active.
  if (( DRY_RUN )); then
    run plasma-apply-colorscheme BreezeDark
  elif ! output=$(plasma-apply-colorscheme BreezeDark 2>&1); then
    if [[ "$output" == *'already set'* ]]; then info 'Breeze Dark is already active.'
    else error "Could not apply Breeze Dark: $output"; return 1
    fi
  fi
  if (( ! DRY_RUN )); then
    configured=$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)
    [[ "$configured" == BreezeDark ]] || { error "Breeze Dark did not persist (KDE reports: ${configured:-<empty>})."; return 1; }
    success 'Verified Breeze Dark as the active color scheme.'
  fi

  # Seed the persisted accent first; the helper can report that Breeze Dark is
  # already active even while it applies the accent.
  kw --file kdeglobals --group General --key AccentColor '69,48,120'
  kw --file kdeglobals --group General --key accentColorFromWallpaper false
  if (( DRY_RUN )); then
    run plasma-apply-colorscheme --accent-color '#453078' BreezeDark
  elif ! output=$(plasma-apply-colorscheme --accent-color '#453078' BreezeDark 2>&1); then
    if [[ "$output" == *'already set'* ]]; then info 'Breeze Dark was already active while applying the accent.'
    else error "Could not apply the Violet-Noir accent: $output"; return 1
    fi
  fi
  if (( ! DRY_RUN )); then
    configured=$(kreadconfig6 --file kdeglobals --group General --key AccentColor)
    [[ -n "$configured" ]] || configured=$(kreadconfig6 --file kdeglobals --group General --key accentColor)
    [[ "$configured" == '69,48,120' || "$configured" == '#453078' ]] \
      || { error "Violet-Noir accent did not persist (KDE reports: ${configured:-<empty>})."; return 1; }
    success 'Verified the Violet-Noir accent color.'
  fi

  kw --file kdeglobals --group Icons --key Theme breeze-dark
  # Oxygen window decoration; drop the obsolete theme key so Oxygen's own
  # defaults apply.
  kw --file kwinrc --group org.kde.kdecoration2 --key library org.kde.oxygen
  kw --file kwinrc --group org.kde.kdecoration2 --key theme --delete

  if [[ "$cursor_theme_found" == yes ]]; then
    info 'Applying the Empty-Butterfly-Purple cursor at 48px.'
    kw --file kcminputrc --group Mouse --key cursorTheme Empty-Butterfly-Purple
    kw --file kcminputrc --group Mouse --key cursorSize 48
  else
    info 'Cursor theme not selected; cursor settings left unchanged.'
  fi

  info 'Setting Ghostty as the terminal (Super+X, Ctrl+Alt+T).'
  kw --file kglobalshortcutsrc --group services --group org.kde.konsole.desktop --key _launch none
  kw --file kdeglobals --group General --key TerminalApplication ghostty
  kw --file kdeglobals --group General --key TerminalService com.mitchellh.ghostty.desktop
  kw --file kglobalshortcutsrc --group services --group com.mitchellh.ghostty.desktop --key _launch $'Meta+X\tCtrl+Alt+T'

  info 'Input: PTT mouse buttons for X11 apps, Num Lock on at login.'
  kw --file kwinrc --group Xwayland --key XwaylandEavesdropsMouse true
  kw --file kcminputrc --group Keyboard --key NumLock 0

  if [[ -d "$wallpaper_dir" ]]; then
    need_cmd python3 'python3 is required for the wallpaper slideshow.' || return 1
    if (( DRY_RUN )); then
      dry_note 'would set an hourly slideshow from ~/Pictures/Wallpapers on every screen (plasmashell evaluateScript)'
    else
      info 'Configuring an hourly wallpaper slideshow on every screen.'
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
subprocess.run(["dbus-send", "--session", "--dest=org.kde.plasmashell", "--type=method_call",
                "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", "string:" + script], check=True)
' || { error 'Could not configure the wallpaper slideshow.'; return 1; }
      success 'Hourly wallpaper slideshow configured on all screens.'
    fi

    wallpaper_source=$(find "$wallpaper_dir" -maxdepth 1 -type f -iname '*.png' 2>/dev/null | shuf -n 1)
    if [[ -n "$wallpaper_source" ]]; then
      info "Login and lock screen wallpaper: ${wallpaper_source##*/}"
      as_root install -d -m 755 /var/lib/plasmalogin/wallpapers || return 1
      as_root install -m 644 "$wallpaper_source" /var/lib/plasmalogin/wallpapers/login-wallpaper.png || return 1
      kw_root --file /etc/plasmalogin.conf --group Greeter --key WallpaperPluginId org.kde.image
      kw_root --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General \
        --key Image 'file:///var/lib/plasmalogin/wallpapers/login-wallpaper.png'

      lock_wallpaper_url=$(WALLPAPER_SOURCE="$wallpaper_source" python3 -c \
        'import os, urllib.parse; print("file://" + urllib.parse.quote(os.environ["WALLPAPER_SOURCE"]))')
      kw --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
      kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "$lock_wallpaper_url"
      kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key PreviewImage "$lock_wallpaper_url"
      if (( ! DRY_RUN )); then
        local plugin image
        plugin=$(kreadconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin)
        image=$(kreadconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image)
        if [[ "$plugin" != org.kde.image || "$image" != "$lock_wallpaper_url" ]]; then
          error "Lock screen wallpaper did not persist (plugin: ${plugin:-<empty>}, image: ${image:-<empty>})."
          return 1
        fi
        success 'Verified the lock screen wallpaper settings.'
      fi
    else
      info 'No PNG wallpapers found; login and lock screen wallpapers left unchanged.'
    fi
  else
    info "No $wallpaper_dir; slideshow, login, and lock screen wallpapers skipped."
  fi

  if (( KW_FAILURES )); then
    error "$KW_FAILURES KDE setting(s) could not be written; see the lines above."
    return 1
  fi
  success 'KDE Plasma appearance, terminal, input, and wallpaper settings written.'
}

# duxinstall installs Hyprland, Ghostty and Dank Shell with pacman and makepkg
# on its own. It needs cached sudo credentials (the keepalive provides them)
# and never prompts with -y.
install_dank_shell() {
  local tmp rc=0
  need_cmd curl 'curl is required to download duxinstall.' || return 1
  if (( ! PACKAGE_SELECTED[UPDATE_INDEX] )); then
    info 'Syncing and upgrading first so duxinstall does not install onto stale package databases.'
    pacman_root -Syu || return 1
  fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/duxinstall.XXXXXXXX") || return 1
  info "Downloading the duxinstall bootstrap from $DUX_INSTALL_URL"
  if ! curl -fsSL "$DUX_INSTALL_URL" -o "$tmp" || [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"; error 'Could not download the duxinstall bootstrap.'; return 1
  fi
  success "Bootstrap downloaded ($(wc -l < "$tmp") lines); it verifies the installer's checksum before running it."
  info "Running duxinstall ${DUX_INSTALL_ARGS[*]}"
  run sh "$tmp" "${DUX_INSTALL_ARGS[@]}" || rc=$?
  rm -f -- "$tmp"
  if (( rc )); then
    error "duxinstall failed (exit $rc). Its own log is /tmp/duxinstall-<timestamp>.log."
    return "$rc"
  fi
  success 'Dank Shell installed. Its own log is /tmp/duxinstall-<timestamp>.log.'
}

# ─────────────────────────────────────────────────────────────────────────────
# Main flow
# ─────────────────────────────────────────────────────────────────────────────

sync_groups_from_items() {
  if any_selected "${APP_SELECTED[@]}"; then PACKAGE_SELECTED[0]=1; else PACKAGE_SELECTED[0]=0; fi
  if any_selected "${COOLER_SELECTED[@]}"; then PACKAGE_SELECTED[1]=1; else PACKAGE_SELECTED[1]=0; fi
  PACKAGE_PREVIOUS=("${PACKAGE_SELECTED[@]}")
}
apply_group_changes() {
  local i
  # Only a group whose checkbox changed resets its items, so individual
  # choices made on the review screen survive going back.
  if (( PACKAGE_SELECTED[0] != PACKAGE_PREVIOUS[0] )); then
    for i in "${!APP_SELECTED[@]}"; do APP_SELECTED[i]=${PACKAGE_SELECTED[0]}; done
  fi
  if (( PACKAGE_SELECTED[1] != PACKAGE_PREVIOUS[1] )); then
    for i in "${!COOLER_SELECTED[@]}"; do COOLER_SELECTED[i]=${PACKAGE_SELECTED[1]}; done
  fi
  PACKAGE_PREVIOUS=("${PACKAGE_SELECTED[@]}")
}

apply_preselection() {
  local i
  (( PRE_APPS )) && for i in "${!APP_SELECTED[@]}"; do APP_SELECTED[i]=1; done
  (( PRE_COOLING )) && for i in "${!COOLER_SELECTED[@]}"; do COOLER_SELECTED[i]=1; done
  (( PRE_WALLPAPERS )) && ASSET_SELECTED[0]=1
  (( PRE_CURSORS )) && ASSET_SELECTED[1]=1
  (( PRE_KDE )) && DESKTOP_SELECTED[0]=1
  (( PRE_DANK )) && DESKTOP_SELECTED[DANK_INDEX]=1
  (( PRE_UPDATE )) && PACKAGE_SELECTED[UPDATE_INDEX]=1
  sync_groups_from_items
  log_event "Preselected from options: apps=$PRE_APPS cooling=$PRE_COOLING wallpapers=$PRE_WALLPAPERS cursors=$PRE_CURSORS kde=$PRE_KDE dankshell=$PRE_DANK update=$PRE_UPDATE"
}

main() {
  local result stage=0 problem
  enter_screen
  log_event "Arch-GKuba post-install started (dry run: $DRY_RUN)."

  problem=$(prerequisite_problem)
  if [[ -n "$problem" ]]; then
    log_event "Prerequisite failed: $problem"
    show_message_screen 'Cannot start' "$RED" "$G_FAIL $problem"
    return 1
  fi

  if (( PRESELECT )); then apply_preselection; stage=4; fi

  while :; do
    case "$stage" in
      0) show_welcome || return 0; stage=1 ;;
      1)
        sync_groups_from_items
        result=0
        draw_menu 1 'Packages and updates' 'Choose package groups and the system update. Fine-tune them on review.' \
          PACKAGE_LABELS PACKAGE_DETAILS PACKAGE_SELECTED || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=0; continue; }
        apply_group_changes
        stage=2
        ;;
      2)
        result=0
        draw_menu 2 'Desktop assets' 'Choose wallpapers and cursor themes to copy from DESetupLinux.' \
          ASSET_LABELS ASSET_DETAILS ASSET_SELECTED || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=1; continue; }
        stage=3
        ;;
      3)
        result=0
        draw_menu 3 'Desktop themes' 'Choose optional desktop setups. Both can be installed side by side.' \
          DESKTOP_LABELS DESKTOP_DETAILS DESKTOP_SELECTED || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=2; continue; }
        stage=4
        ;;
      4)
        if (( ! PACKAGE_STATUS_READY )); then
          draw_header 'Checking this system' Step 4 6
          put 5 "$CYAN${SPINNER[0]} Checking installed packages$G_ELLIPSIS$RESET"
          check_package_status
        fi
        result=0
        show_selection_review || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=3; continue; }
        stage=5
        ;;
      5)
        result=0
        show_plan || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=4; continue; }
        stage=6
        ;;
      6)
        result=0
        show_authentication || result=$?
        (( result == 1 )) && return 0
        (( result == 2 )) && { stage=5; continue; }
        break
        ;;
    esac
  done

  log_event 'Plan confirmed and authenticated; starting installation.'
  run_installation_phases
  show_completion
  [[ " ${PHASE_STATE[*]} " == *' fail '* ]] && return 1
  return 0
}

main
