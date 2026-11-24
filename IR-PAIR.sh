#!/usr/bin/env bash
[ -n "$BASH_VERSION" ] || exec bash "$0" "$@"
export PATH="$PATH:/usr/local/bin:/usr/sbin:/sbin"

# ----------------------------------------------------------------------------
# ir-pair.sh : IR remote pairing for 240-MP (run it in "console" mode)
#
# Usage:
#   (no argument)        pair every action
#   select back          re-pair only the listed actions
#   actions: up down left right select back play_pause
#
# Requirements: a GPIO IR receiver enabled with "dtoverlay=gpio-ir" in
# config.txt (this script never edits that file), passwordless sudo.
# ----------------------------------------------------------------------------

TIMEOUT=20
MAX_TRIES=3
OUT="${DATA_ROOT:-$HOME/.local/share/240-MP}/ir"
CODES="$OUT/codes.txt"
KEYMAP="$OUT/mp240.toml"

ACTIONS=(up down left right select back play_pause)
declare -A KEYS=([up]=KEY_UP [down]=KEY_DOWN [left]=KEY_LEFT [right]=KEY_RIGHT
                 [select]=KEY_ENTER [back]=KEY_ESC [play_pause]=KEY_SPACE)
declare -A LABELS=([up]="UP" [down]="DOWN" [left]="LEFT" [right]="RIGHT"
                   [select]="SELECT (OK)" [back]="BACK" [play_pause]="PLAY/PAUSE")

# ---- output helpers --------------------------------------------------------
step() { printf '\n[%s] %s\n' "$1" "$2"; }
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [ !! ] %s\n' "$*"; }
info() { printf '  [ .. ] %s\n' "$*"; }
die()  { printf '\n  [FAIL] %s\n\n' "$*"; exit 1; }

printf '==============================================\n'
printf '        240-MP  -  IR remote pairing\n'
printf '==============================================\n'

mkdir -p "$OUT"; touch "$CODES"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=("${ACTIONS[@]}")
  : > "$CODES"          # full pairing: start from scratch
  info "Mode: full pairing (${#TARGETS[@]} actions)"
else
  info "Mode: partial re-pairing (${TARGETS[*]})"
fi

# ---- [1/4] dependencies ----------------------------------------------------
step "1/4" "Checking dependencies"

sudo -n true 2>/dev/null || die "Passwordless sudo is required (no terminal is available in console mode)."
ok "sudo available"

ensure_tool() {   # ensure_tool <command> <apt package>
  if command -v "$1" >/dev/null 2>&1; then ok "$1"; return 0; fi
  info "$1 not found, installing package '$2'..."
  if ! sudo -n apt-get install -y -qq "$2" >/dev/null 2>&1; then
    info "Refreshing package lists..."
    sudo -n apt-get update -qq >/dev/null 2>&1
    sudo -n apt-get install -y -qq "$2" >/dev/null 2>&1
  fi
  command -v "$1" >/dev/null 2>&1 \
    || die "Could not install '$2' (no network?). Run manually: sudo apt install $2"
  ok "$1 (installed)"
}

ensure_tool ir-keytable ir-keytable
ensure_tool stdbuf      coreutils
ensure_tool pkill       procps

# ---- [2/4] receiver --------------------------------------------------------
step "2/4" "Looking for the IR receiver"

RC="${RC:-}"
if [ -z "$RC" ]; then
  for d in /sys/class/rc/rc*; do
    [ -e "$d" ] && { RC=$(basename "$d"); break; }
  done
fi

if [ -z "$RC" ] || [ ! -d "/sys/class/rc/$RC" ]; then
  CFG=/boot/firmware/config.txt; [ -f "$CFG" ] || CFG=/boot/config.txt
  warn "No IR receiver detected."
  if grep -qE '^[[:space:]]*dtoverlay=gpio-ir' "$CFG" 2>/dev/null; then
    echo "      The overlay is already in $CFG."
    echo "      Reboot the Pi, and check the wiring and the GPIO number."
  else
    echo "      Add this line to $CFG :"
    echo ""
    echo "          dtoverlay=gpio-ir,gpio_pin=18"
    echo ""
    echo "      (replace 18 by the BCM number of the pin wired to the receiver"
    echo "       data output), then reboot and run this script again."
  fi
  exit 1
fi
ok "Receiver found: $RC"

# ---- [3/4] pairing ---------------------------------------------------------
step "3/4" "Pairing - use your REMOTE, not the keyboard"

# Normalise protocol variants: they are not valid names in a keymap file
normalize() {
  case "$1" in
    necx|nec32)    echo nec ;;
    rc-5x*|rc5x*)  echo rc-5 ;;
    rc-6*)         echo rc-6 ;;
    sony*)         echo sony ;;
    "")            echo nec ;;
    *)             echo "$1" ;;
  esac
}

# Prints "<protocol> <scancode>" on stdout, or returns 1 on timeout.
# The countdown goes to stderr so it is not captured by $(...).
capture() {
  local tmp line="" i proto code
  tmp=$(mktemp)
  sudo -n stdbuf -oL ir-keytable -s "$RC" -t >"$tmp" 2>&1 &
  local pid=$!
  for ((i=0; i<TIMEOUT*10; i++)); do
    line=$(grep -m1 'scancode = 0x' "$tmp") && break
    [ $((i % 10)) -eq 0 ] && printf '\r      waiting... %2ds ' $((TIMEOUT - i/10)) >&2
    sleep 0.1
  done
  printf '\r%*s\r' 40 '' >&2
  sudo -n pkill -f "ir-keytable -s $RC -t" 2>/dev/null
  wait "$pid" 2>/dev/null; rm -f "$tmp"
  [ -n "$line" ] || return 1
  proto=$(sed -n 's/.*protocol(\([a-z0-9_-]*\)).*/\1/p' <<<"$line")
  code=$(grep -oE '0x[0-9a-fA-F]+' <<<"$line" | tail -1)
  echo "$(normalize "$proto") $code"
}

# Which other action already uses this "<protocol> <scancode>" ?
owner_of() { awk -v r="$1" -v me="$2" '($2" "$3)==r && $1!=me {print $1; exit}' "$CODES"; }

# Clear the kernel keymap so remote buttons do not act on 240-MP while pairing
sudo -n ir-keytable -s "$RC" -c -p all >/dev/null 2>&1

for a in "${TARGETS[@]}"; do
  if [ -z "${KEYS[$a]:-}" ]; then warn "Unknown action '$a' (skipped)"; continue; fi
  printf '\n  >> Press  %-12s on the remote  (%ss)\n' "${LABELS[$a]}" "$TIMEOUT"
  tries=0
  while [ $tries -lt $MAX_TRIES ]; do
    tries=$((tries+1))
    if res=$(capture); then
      other=$(owner_of "$res" "$a")
      if [ -n "$other" ]; then
        warn "That button is already used for ${LABELS[$other]}. Press a different one."
        sleep 1; continue
      fi
      sed -i "/^$a /d" "$CODES"
      echo "$a $res" >> "$CODES"
      ok "Received $res"
      break
    else
      warn "Nothing received, skipping ${LABELS[$a]}."
      break
    fi
  done
  sleep 1   # let repeat codes die out
done

[ -s "$CODES" ] || die "No code captured, nothing to save."

# ---- [4/4] save ------------------------------------------------------------
step "4/4" "Saving and loading the keymap"

{
  for p in $(awk '{print $2}' "$CODES" | sort -u); do
    printf '[[protocols]]\nname = "mp240"\nprotocol = "%s"\n[protocols.scancodes]\n' "$p"
    while read -r a pr c; do
      [ "$pr" = "$p" ] && printf '%s = "%s"\n' "$c" "${KEYS[$a]}"
    done < "$CODES"
  done
} > "$KEYMAP"

if ! sudo -n ir-keytable -s "$RC" -c -w "$KEYMAP"; then
  warn "The kernel rejected the keymap. File content:"
  cat "$KEYMAP"
  die "Keymap not loaded."
fi
loaded=$(sudo -n ir-keytable -s "$RC" -r | grep -c 'KEY_')
[ "$loaded" -gt 0 ] || die "Keymap loaded but the kernel table is empty."
ok "$loaded key(s) loaded in the kernel"

sudo -n install -D -m644 "$KEYMAP" /etc/rc_keymaps/mp240.toml
grep -q mp240 /etc/rc_maps.cfg 2>/dev/null \
  || echo '* * mp240.toml' | sudo -n tee -a /etc/rc_maps.cfg >/dev/null
ok "Saved for next boots (/etc/rc_keymaps/mp240.toml)"

# ---- summary ---------------------------------------------------------------
printf '\n----------------------------------------------\n'
printf '  %-13s %-11s %s\n' "ACTION" "KEY" "IR CODE"
printf '----------------------------------------------\n'
for a in "${ACTIONS[@]}"; do
  line=$(grep "^$a " "$CODES")
  if [ -n "$line" ]; then
    read -r _ pr c <<<"$line"
    printf '  %-13s %-11s %s (%s)\n' "${LABELS[$a]}" "${KEYS[$a]}" "$c" "$pr"
  else
    printf '  %-13s %-11s %s\n' "${LABELS[$a]}" "${KEYS[$a]}" "not paired"
  fi
done
printf '----------------------------------------------\n'
printf '\nDone. Test it: UP/DOWN should scroll this view, BACK leaves it.\n'
printf 'To redo some buttons only, set  args = select back  in the .txt file.\n'
