#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  check_memory_budget.sh [--env <name>] [--max-ram <pct>] [--max-flash <pct>] [--yes]

Options:
  --env <name>         PlatformIO env (default: ClemS-ESP32-to-5-LEDs)
  --max-ram <pct>      RAM threshold in percent (default: 75)
  --max-flash <pct>    Flash threshold in percent (default: 85)
  --yes                Non-interactive mode
  -h, --help

Examples:
  ./tools/check_memory_budget.sh
  ./tools/check_memory_budget.sh --env ClemS-ESP32-to-5-LEDs --max-ram 75 --max-flash 85 --yes
EOF
}

env_name="ClemS-ESP32-to-5-LEDs"
max_ram="75"
max_flash="85"
non_interactive=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      env_name="${2:-}"
      shift 2
      ;;
    --max-ram)
      max_ram="${2:-}"
      shift 2
      ;;
    --max-flash)
      max_flash="${2:-}"
      shift 2
      ;;
    --yes|--non-interactive)
      non_interactive=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ "$non_interactive" -eq 0 && -t 0 && -t 1 && "$(command -v gum >/dev/null 2>&1; echo $?)" -eq 0 ]]; then
  env_name="$(gum input --value "$env_name" --placeholder "PlatformIO env")"
  max_ram="$(gum input --value "$max_ram" --placeholder "RAM threshold %")"
  max_flash="$(gum input --value "$max_flash" --placeholder "Flash threshold %")"
fi

tmp_log="$(mktemp -t wled-cls-mem-budget.XXXXXX.log)"
cleanup() { rm -f "$tmp_log"; }
trap cleanup EXIT

if [[ -z "${GIT:-}" ]]; then
  git_bin="$(command -v git || true)"
  [[ -n "$git_bin" ]] && export GIT="$git_bin"
fi

echo "[RUN] python3 -m platformio run -e $env_name"
python3 -m platformio run -e "$env_name" | tee "$tmp_log"

ram_line="$(grep -E '^RAM:' "$tmp_log" | tail -n1 || true)"
flash_line="$(grep -E '^Flash:' "$tmp_log" | tail -n1 || true)"

if [[ -z "$ram_line" || -z "$flash_line" ]]; then
  echo "[ERR] RAM/Flash lines not found in PlatformIO output" >&2
  exit 1
fi

ram_pct="$(echo "$ram_line" | sed -E 's/.* ([0-9]+([.][0-9]+)?)% .*/\1/')"
flash_pct="$(echo "$flash_line" | sed -E 's/.* ([0-9]+([.][0-9]+)?)% .*/\1/')"
ram_used="$(echo "$ram_line" | sed -E 's/.*[(]used ([0-9]+) bytes from ([0-9]+) bytes[)].*/\1\/\2/')"
flash_used="$(echo "$flash_line" | sed -E 's/.*[(]used ([0-9]+) bytes from ([0-9]+) bytes[)].*/\1\/\2/')"

echo "[INFO] env=$env_name"
echo "[INFO] RAM   : ${ram_pct}% ($ram_used), threshold=${max_ram}%"
echo "[INFO] Flash : ${flash_pct}% ($flash_used), threshold=${max_flash}%"

ram_over="$(awk "BEGIN {print ($ram_pct > $max_ram) ? 1 : 0}")"
flash_over="$(awk "BEGIN {print ($flash_pct > $max_flash) ? 1 : 0}")"

status=0
if [[ "$ram_over" -eq 1 ]]; then
  echo "[FAIL] RAM usage above threshold"
  status=1
fi
if [[ "$flash_over" -eq 1 ]]; then
  echo "[FAIL] Flash usage above threshold"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "[PASS] memory budget within thresholds"
fi

exit "$status"
