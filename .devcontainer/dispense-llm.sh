#!/usr/bin/env bash
# ======================================================================
# Room-password -> model-proxy key dispenser client
# Ported from upstream (Henrik Rexed, ISI-6996 / ISI-7000 / ISI-7001).
# ----------------------------------------------------------------------
# OPTIONAL in this repository. For an instructor-led delivery the host runs
# a LiteLLM proxy that holds the real DeepSeek key and a "dispenser" that
# mints a per-attendee, budget-capped virtual key in exchange for the room
# password. Attendees then set two Codespace secrets:
#
#   WORKSHOP_DISPENSER_URL   https://<dispenser-host>/dispense  (from the host)
#   WORKSHOP_ROOM_PASSWORD   the room password                  (from the host)
#
# This script exchanges them for {proxy_url, virtual_key, model} and writes
# a 0600, gitignored env file that my_functions.sh loads in every terminal:
# the agents, Phoenix and the eval judge then talk to the proxy. Neither the
# URL nor any secret is in this repository.
#
# Contract (host side, unchanged from upstream):
#   GET  <WORKSHOP_DISPENSER_URL>        header  X-Room-Password: <pw>
#   200  {"proxy_url":"https://…","virtual_key":"sk-…","model":"deepseek-chat"}
#   401  wrong / missing password
#
# Exit codes — the caller (aiwDispenseLlm) falls back on anything but 0:
#   0  key dispensed and written
#   2  not configured (neither variable set) — the normal case without a host
#   1  configured but failed — FAIL-CLOSED: nothing written, nothing kept
#
# Never prints the password, the key or the response body. Usage:
#   bash .devcontainer/dispense-llm.sh [output-file]
# ======================================================================
set -uo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$(cd "${_here}/.." && pwd)/.workshop-llm.env}"

info(){ printf '[dispense] %s\n' "$*"; }
fail(){ printf '[dispense] ERROR: %s\n' "$*" >&2; exit 1; }

URL="${WORKSHOP_DISPENSER_URL:-}"
PW="${WORKSHOP_ROOM_PASSWORD:-}"

if [ -z "${URL}${PW}" ]; then
  info "WORKSHOP_DISPENSER_URL / WORKSHOP_ROOM_PASSWORD not set — no model proxy for this session"
  exit 2
fi
[ -n "$URL" ] || fail "WORKSHOP_ROOM_PASSWORD is set but WORKSHOP_DISPENSER_URL is not — ask the workshop host for the dispenser URL"
[ -n "$PW" ]  || fail "WORKSHOP_DISPENSER_URL is set but WORKSHOP_ROOM_PASSWORD is not — ask the workshop host for the room password"

# TLS only: the room password travels in a header. No redirects are followed
# (no -L), so a 3xx to plain http cannot downgrade it either.
case "$URL" in
  https://*) ;;
  *) fail "WORKSHOP_DISPENSER_URL must be an https:// URL" ;;
esac
printf '%s' "$URL" | grep -qE '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/%-]*)?$' \
  || fail "WORKSHOP_DISPENSER_URL is not a plain https://host[:port]/path URL"
# A CR/LF in the password would inject extra request headers.
case "$PW" in
  *$'\n'*|*$'\r'*) fail "WORKSHOP_ROOM_PASSWORD contains a line break" ;;
esac

command -v curl    >/dev/null 2>&1 || fail "curl not found"
command -v python3 >/dev/null 2>&1 || fail "python3 not found (needed to parse the response)"

umask 077
tmp="$(mktemp -d)" || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
# The header goes through a 0600 file (printf is a shell builtin), so the
# password never appears in curl's argv / `ps`.
printf 'X-Room-Password: %s\n' "$PW" > "$tmp/hdr"

info "requesting a per-attendee key from the dispenser (room-password auth)"
code="$(curl --proto '=https' --tlsv1.2 -sS \
  --connect-timeout 10 --max-time 30 --max-filesize 65536 \
  -H @"$tmp/hdr" -o "$tmp/body" -w '%{http_code}' -- "$URL" 2>/dev/null)" || true
code="${code:-000}"

case "$code" in
  200) ;;
  401|403) fail "dispenser refused the room password (HTTP ${code}) — check WORKSHOP_ROOM_PASSWORD" ;;
  000) fail "could not reach the dispenser (network, DNS, TLS or timeout) — is the host's proxy up?" ;;
  *)   fail "dispenser answered HTTP ${code}" ;;   # body not printed: it may echo secrets
esac

# Parse and validate. Every value is checked against a strict character set
# before it is written into a file that shells source.
parsed="$(python3 -I - "$tmp/body" <<'PY'
import json, re, sys
try:
    o = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)
if not isinstance(o, dict):
    sys.exit(3)
pu = str(o.get("proxy_url") or "").rstrip("/")
vk = str(o.get("virtual_key") or "")
md = str(o.get("model") or "deepseek-chat")
if not re.fullmatch(r"https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?", pu):
    sys.exit(4)
if not re.fullmatch(r"[A-Za-z0-9._-]{8,512}", vk):
    sys.exit(5)
if not re.fullmatch(r"[A-Za-z0-9._:/-]{1,64}", md):
    sys.exit(6)
print(pu); print(vk); print(md)
PY
)"
prc=$?
case "$prc" in
  0) ;;
  3) fail "HTTP 200 but the body is not a JSON object" ;;
  4) fail "HTTP 200 but proxy_url is missing or not an https URL" ;;
  5) fail "HTTP 200 but virtual_key is missing or malformed" ;;
  *) fail "HTTP 200 but the response failed validation (${prc})" ;;
esac
PROXY_URL="$(printf '%s\n' "$parsed" | sed -n 1p)"
VKEY="$(printf '%s\n' "$parsed" | sed -n 2p)"
MODEL="$(printf '%s\n' "$parsed" | sed -n 3p)"

# Two base-URL forms: /v1 for OpenAI SDKs / kagent / Phoenix; bare for the
# dt-evals validate probe, which appends /v1/chat/completions itself.
BASE_V1="${PROXY_URL%/v1}/v1"
BASE_NOV1="${PROXY_URL%/v1}"

# Atomic write: never leave a half-written key file behind.
new="${OUT}.new.$$"
cat > "$new" <<EOF || { rm -f "$new"; fail "could not write ${OUT}"; }
# Written by .devcontainer/dispense-llm.sh — per-attendee model-proxy endpoint
# and virtual key. GITIGNORED, mode 0600. Never commit, never paste.
# Regenerate with: dispenseLlmKey
export WORKSHOP_LLM_MODEL="${MODEL}"
export WORKSHOP_LLM_BASE_URL="${BASE_V1}"
export WORKSHOP_LLM_BASE_URL_NOV1="${BASE_NOV1}"
export WORKSHOP_LLM_API_KEY="${VKEY}"
export DEEPSEEK_API_KEY="${VKEY}"
export DEEPSEEK_BASE_URL="${BASE_V1}"
export OPENAI_API_KEY="${VKEY}"
export OPENAI_BASE_URL="${BASE_V1}"
EOF
chmod 600 "$new" && mv -f "$new" "$OUT" || { rm -f "$new"; fail "could not install ${OUT}"; }
info "wrote $(basename "$OUT") (mode 600, model=${MODEL}, key=****masked****)"
exit 0
