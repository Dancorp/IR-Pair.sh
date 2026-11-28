#!/usr/bin/env bash
[ -n "$BASH_VERSION" ] || exec bash "$0" "$@"
export PATH="$PATH:/usr/local/bin:/usr/sbin:/sbin"

# ----------------------------------------------------------------------------
# IR-PAIR.sh : IR remote pairing for 240-MP (run it in "console" mode)
#
# The keys to pair are listed in IR-PAIR.conf (same folder, same base name).
#
# Usage (the "args" line of IR-PAIR.txt):
#   (no argument)        pair every enabled key, starting from scratch
#   new                  pair only the enabled keys that have no code yet
#   enter esc KEY_UP     re-pair only the listed keys (KEY_ prefix optional)
#
# Requirements: IR receiver enabled with "dtoverlay=gpio-ir" in config.txt,
# the ir-keytable package, and sudo without password prompt.
# ----------------------------------------------------------------------------

TIMEOUT=20          # seconds to wait for each button
MAX_TRIES=3         # attempts when a button is already used by another key
COUNTDOWN=1         # 1 = live countdown on the key line, 0 = no countdown
CONF="${0%.*}.conf"
OUT="${DATA_ROOT:-$HOME/.local/share/240-MP}/ir"
CODES="$OUT/codes.txt"
KEYMAP="$OUT/mp240.toml"

# ---- output helpers --------------------------------------------------------
warn() { printf '  [ !! ] %s\n' "$*"; }
die()  { printf '\n  [FAIL] %s\n\n' "$*"; exit 1; }

printf '\n  240-MP - IR remote pairing\n'
printf '  --------------------------\n'

mkdir -p "$OUT"; touch "$CODES"

# ---- load the list of keys -------------------------------------------------
ACTIONS=()               # enabled keys, in file order
declare -A LABELS=()     # KEY_NAME -> description

add_key() {   # add_key <KEY_NAME> <description>
  local k="${1^^}" d="$2"
  [[ $k =~ ^KEY_[A-Z0-9_]+$ ]] || { warn "Invalid key name in config, ignored: $1"; return; }
  [ -n "${LABELS[$k]+x}" ] && { warn "Duplicate key in config, ignored: $k"; return; }
  LABELS[$k]="${d:-$k}"
  ACTIONS+=("$k")
}

load_conf() {
  local line k d
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"      # trim leading spaces
    [ -z "$line" ] && continue
    [[ $line == \#* ]] && continue
    read -r k d <<<"$line"
    add_key "$k" "$d"
  done < "$CONF"
}

if [ -f "$CONF" ]; then
  load_conf
else
  warn "Config file not found, using default keys."
  add_key KEY_UP    "Navigate up"
  add_key KEY_DOWN  "Navigate down"
  add_key KEY_LEFT  "Navigate left"
  add_key KEY_RIGHT "Navigate right"
  add_key KEY_ENTER "Select / confirm (OK)"
  add_key KEY_ESC   "Back"
  add_key KEY_SPACE "Play / pause"
fi
[ ${#ACTIONS[@]} -gt 0 ] || die "No key is enabled in $(basename "$CONF") (every line is commented out)."

# ---- checks (silent unless something is wrong) -----------------------------
command -v ir-keytable >/dev/null 2>&1 || die "ir-keytable is not installed.
      Run once in a terminal on the Pi:  sudo apt install ir-keytable"

for t in stdbuf pkill awk; do
  command -v "$t" >/dev/null 2>&1 \
    || die "'$t' is missing (it is standard on Raspberry Pi OS: coreutils / procps / mawk)."
done

sudo -n true 2>/dev/null || die "sudo asks for a password and this console cannot type one.
      Option A: remove the password requirement (see the README).
      Option B: run 'sudo -v' in a terminal on the Pi, then launch this script
                again within ~15 minutes."

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
    echo "      (replace 18 by the GPIO number wired to the receiver data pin),"
    echo "       then reboot and run this script again."
  fi
  exit 1
fi
printf '  Checks ............. OK (%s)\n' "$RC"

# ---- choose the keys to pair -----------------------------------------------
# Accepts "enter", "ENTER" or "KEY_ENTER"
resolve_key() { local k="${1^^}"; [[ $k == KEY_* ]] || k="KEY_$k"; echo "$k"; }

TARGETS=()
if [ $# -eq 0 ]; then
  TARGETS=("${ACTIONS[@]}")
  : > "$CODES"           # full pairing: start from scratch
elif [ "${1,,}" = "new" ]; then
  for k in "${ACTIONS[@]}"; do
    grep -q "^$k " "$CODES" || TARGETS+=("$k")
  done
  if [ ${#TARGETS[@]} -eq 0 ]; then
    printf '\n  Nothing to pair: all enabled keys already have a code.\n\n'
    exit 0
  fi
else
  for arg in "$@"; do
    k=$(resolve_key "$arg")
    if [ -n "${LABELS[$k]+x}" ]; then TARGETS+=("$k"); else warn "$k is not enabled in the config file"; fi
  done
  [ ${#TARGETS[@]} -gt 0 ] || die "No valid key to pair."
fi

# ---- pairing helpers -------------------------------------------------------
# Protocol variants are not valid names in a keymap file
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

# capture <text of the key line>
# Prints "<protocol> <scancode>" on stdout, or returns 1 on timeout.
# The countdown goes to stderr so it is not captured by $(...).
capture() {
  local tmp line="" i proto code
  tmp=$(mktemp)
  sudo -n stdbuf -oL ir-keytable -s "$RC" -t >"$tmp" 2>&1 &
  local pid=$!
  for ((i=0; i<TIMEOUT*10; i++)); do
    line=$(grep -m1 'scancode = 0x' "$tmp") && break
    if [ "$COUNTDOWN" = 1 ] && [ $((i % 10)) -eq 0 ]; then
      printf '\r  %s %2ds ' "$1" $((TIMEOUT - i/10)) >&2
    fi
    sleep 0.1
  done
  printf '\r%*s\r' 60 '' >&2
  sudo -n pkill -f "ir-keytable -s $RC -t" 2>/dev/null
  wait "$pid" 2>/dev/null; rm -f "$tmp"
  [ -n "$line" ] || return 1
  proto=$(sed -n 's/.*protocol(\([a-z0-9_-]*\)).*/\1/p' <<<"$line")
  code=$(grep -oE '0x[0-9a-fA-F]+' <<<"$line" | tail -1)
  echo "$(normalize "$proto") $code"
}

# Which other key already uses this "<protocol> <scancode>" ?
owner_of() { awk -v r="$1" -v me="$2" '($2" "$3)==r && $1!=me {print $1; exit}' "$CODES"; }

# ---- pairing ---------------------------------------------------------------
printf '\n  Press each button on the REMOTE (%s keys):\n\n' "${#TARGETS[@]}"

# Clear the kernel keymap so remote buttons do not act on 240-MP while pairing
sudo -n ir-keytable -s "$RC" -c -p all >/dev/null 2>&1

n=0; total=${#TARGETS[@]}
for a in "${TARGETS[@]}"; do
  n=$((n+1))
  line_txt=$(printf '[%d/%d] %-24s' "$n" "$total" "${LABELS[$a]:0:24}")
  result="skipped"
  tries=0
  while [ $tries -lt $MAX_TRIES ]; do
    tries=$((tries+1))
    if res=$(capture "$line_txt"); then
      other=$(owner_of "$res" "$a")
      if [ -n "$other" ]; then
        printf '  %s already used, retry\n' "$line_txt"
        sleep 1; continue
      fi
      sed -i "/^$a /d" "$CODES"
      echo "$a $res" >> "$CODES"
      result="OK"
      break
    else
      break
    fi
  done
  printf '  %s %s\n' "$line_txt" "$result"
  sleep 1   # let repeat codes die out
done

# ---- save ------------------------------------------------------------------
# Only keys that are currently enabled in the config file are written
VALID=$(mktemp)
while read -r k pr c; do
  [ -n "${LABELS[$k]+x}" ] && echo "$k $pr $c"
done < "$CODES" > "$VALID"
[ -s "$VALID" ] || { rm -f "$VALID"; die "No code available for the enabled keys, nothing to save."; }

{
  for p in $(awk '{print $2}' "$VALID" | sort -u); do
    printf '[[protocols]]\nname = "mp240"\nprotocol = "%s"\n[protocols.scancodes]\n' "$p"
    while read -r k pr c; do
      [ "$pr" = "$p" ] && printf '%s = "%s"\n' "$c" "$k"
    done < "$VALID"
  done
} > "$KEYMAP"
rm -f "$VALID"

if ! sudo -n ir-keytable -s "$RC" -c -w "$KEYMAP"; then
  warn "The kernel rejected the keymap. File content:"
  cat "$KEYMAP"
  die "Keymap not loaded. Check the key names in $(basename "$CONF")."
fi
loaded=$(sudo -n ir-keytable -s "$RC" -r | grep -c 'KEY_')
[ "$loaded" -gt 0 ] || die "Keymap loaded but the kernel table is empty."

sudo -n install -D -m644 "$KEYMAP" /etc/rc_keymaps/mp240.toml
grep -q mp240 /etc/rc_maps.cfg 2>/dev/null \
  || echo '* * mp240.toml' | sudo -n tee -a /etc/rc_maps.cfg >/dev/null

# ---- result ----------------------------------------------------------------
paired=0; missing=()
for a in "${ACTIONS[@]}"; do
  if grep -q "^$a " "$CODES"; then paired=$((paired+1)); else missing+=("$a"); fi
done

printf '\n  Saved. %d/%d keys paired.\n' "$paired" "${#ACTIONS[@]}"
if [ ${#missing[@]} -gt 0 ]; then
  printf '  Not paired: %s\n' "${missing[*]}"
  printf '  Run again with  args = new\n'
fi
printf '  Test: UP/DOWN scroll this view.\n\n'
