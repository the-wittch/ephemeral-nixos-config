#!/usr/bin/env bash

set -euo pipefail

VAULT=${PASS_SSH_VAULT:-Personal}
OUTDIR=${PASS_SSH_DIR:-$HOME/.ssh}
DRY_RUN=0
LIST_ONLY=0
DEBUG=0
TITLES=()
JSON_FILE=
FOUND_TITLES=()
FOUND_PUBS=()

usage() {
  cat <<'USAGE'
~/.ssh/<title>.pub from Proton Pass SSH items.

  ssh-pubs-from-pass [--list | --debug | --dry-run] [--vault NAME] [--outdir DIR] [title...]

PASS_SSH_VAULT   default Personal
PASS_SSH_DIR     default ~/.ssh
USAGE
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h | --help) usage 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list) LIST_ONLY=1; shift ;;
    --debug) DEBUG=1; shift ;;
    --vault)
      VAULT=${2:?--vault needs a name}
      shift 2
      ;;
    --outdir)
      OUTDIR=${2:?--outdir needs a path}
      shift 2
      ;;
    --)
      shift
      TITLES+=("$@")
      break
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage 1
      ;;
    *)
      TITLES+=("$1")
      shift
      ;;
  esac
done

need() {
  command -v "$1" >/dev/null || {
    echo "need $1 on PATH (rebuild so pass-cli is installed, then: pass-cli login)" >&2
    exit 1
  }
}

need pass-cli
need python3

# shellcheck disable=SC2329
cleanup() {
  [[ -n ${JSON_FILE:-} && -f ${JSON_FILE:-} ]] && rm -f -- "$JSON_FILE"
}
trap cleanup EXIT

fetch_vault_json() {
  local err
  JSON_FILE=$(mktemp)
  err=$(mktemp)

  if ! pass-cli item list --vault-name "$VAULT" --output json >"$JSON_FILE" 2>"$err"; then
    echo "failed to list vault: $VAULT" >&2
    cat "$err" >&2 || true
    rm -f -- "$err"
    echo "(try: pass-cli login)" >&2
    exit 1
  fi
  rm -f -- "$err"

  if [[ ! -s $JSON_FILE ]]; then
    echo "empty response listing vault: $VAULT" >&2
    exit 1
  fi
}

normalize_pub() {
  local raw=$1
  local pub
  pub=$(printf '%s' "$raw" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  pub=$(printf '%s\n' "$pub" | sed -n '/./{p;q;}')
  if [[ $pub == ssh-* || $pub == ecdsa-* ]]; then
    printf '%s\n' "$pub"
    return 0
  fi
  return 1
}

read_public_key() {
  local title=$1
  local pub field

  for field in public_key publicKey "Public key" "public key"; do
    pub=$(pass-cli item view --vault-name "$VAULT" --item-title "$title" --field "$field" 2>/dev/null || true)
    if pub=$(normalize_pub "$pub"); then
      printf '%s\n' "$pub"
      return 0
    fi
  done

  pub=$(pass-cli item view "pass://${VAULT}/${title}/public_key" 2>/dev/null || true)
  if pub=$(normalize_pub "$pub"); then
    printf '%s\n' "$pub"
    return 0
  fi

  pub=$(
    pass-cli item view --vault-name "$VAULT" --item-title "$title" --output json 2>/dev/null |
      python3 -c '
import json, sys, re
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

def walk(o):
    if isinstance(o, dict):
        for v in o.values():
            yield from walk(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk(v)
    elif isinstance(o, str):
        yield o

pat = re.compile(r"^(ssh-(?:ed25519|rsa|dss)|ecdsa-sha2-\S+)\s+\S+")
for s in walk(data):
    s = s.strip()
    if pat.match(s):
        print(s.splitlines()[0])
        sys.exit(0)
sys.exit(1)
' || true
  )
  if pub=$(normalize_pub "$pub"); then
    printf '%s\n' "$pub"
    return 0
  fi
  return 1
}

list_item_rows() {
  python3 - "$JSON_FILE" <<'PY'
import json, sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)

if isinstance(data, dict):
    items = data.get("items") or []
elif isinstance(data, list):
    items = data
else:
    items = []

for it in items:
    if not isinstance(it, dict):
        continue
    title = (it.get("title") or it.get("name") or "").strip()
    if not title:
        continue
    typ = it.get("item_type", it.get("type", it.get("itemType")))
    if isinstance(typ, dict):
        typ = next(iter(typ), "")
    print(f"{title}\t{typ}")
PY
}

title_wanted() {
  local title=$1
  local t
  if [[ ${#TITLES[@]} -eq 0 ]]; then
    return 0
  fi
  for t in "${TITLES[@]}"; do
    if [[ ${t,,} == "${title,,}" ]]; then
      return 0
    fi
  done
  return 1
}

discover_ssh_keys() {
  local title typ pub
  FOUND_TITLES=()
  FOUND_PUBS=()

  while IFS=$'\t' read -r title typ; do
    [[ -z $title ]] && continue
    if ! title_wanted "$title"; then
      continue
    fi

    if pub=$(read_public_key "$title"); then
      FOUND_TITLES+=("$title")
      FOUND_PUBS+=("$pub")
      if [[ $DEBUG -eq 1 ]]; then
        printf '  OK   %-40s  type=%s\n' "$title" "${typ:-?}" >&2
      fi
    elif [[ $DEBUG -eq 1 ]]; then
      printf '  skip %-40s  type=%s  (no public_key)\n' "$title" "${typ:-?}" >&2
    fi
  done < <(list_item_rows)
}

file_for_title() {
  local title=$1
  local slug
  slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/_/g; s/^_+|_+$//g')
  if [[ -z $slug ]]; then
    slug=ssh_key
  fi
  printf '%s.pub' "$slug"
}

write_one() {
  local title=$1
  local pub=$2
  local dest
  dest="$OUTDIR/$(file_for_title "$title")"

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY   $title  →  $dest"
    return 0
  fi

  umask 077
  mkdir -p "$OUTDIR"
  chmod 700 "$OUTDIR"
  printf '%s\n' "$pub" >"$dest"
  chmod 644 "$dest"
  echo "OK    $title  →  $dest"
}

echo "Vault:  $VAULT"
echo "Outdir: $OUTDIR"
echo

fetch_vault_json

if [[ $DEBUG -eq 1 ]]; then
  echo "Probing items for public_key…" >&2
fi

discover_ssh_keys

count=${#FOUND_TITLES[@]}

declare -A seen=()
for i in "${!FOUND_TITLES[@]}"; do
  f=$(file_for_title "${FOUND_TITLES[$i]}")
  if [[ -n ${seen[$f]:-} ]]; then
    echo "'${seen[$f]}' and '${FOUND_TITLES[$i]}' both map to $f; rename one in Pass" >&2
    exit 1
  fi
  seen[$f]=${FOUND_TITLES[$i]}
done

if [[ $LIST_ONLY -eq 1 || $DEBUG -eq 1 ]]; then
  echo "SSH keys in vault:"
  if [[ $count -eq 0 ]]; then
    echo "  (none)"
  else
    for i in "${!FOUND_TITLES[@]}"; do
      printf '  - %s  →  %s\n' "${FOUND_TITLES[$i]}" "$(file_for_title "${FOUND_TITLES[$i]}")"
    done
  fi
  echo
  echo "$count key(s)."
fi

if [[ $LIST_ONLY -eq 1 ]]; then
  echo "Run without --list to import into $OUTDIR."
  exit 0
fi

if [[ $DEBUG -eq 1 && $DRY_RUN -eq 0 ]]; then
  echo "Re-run without --debug to import, or add --dry-run to preview writes."
  exit 0
fi

if [[ $count -eq 0 ]]; then
  echo "no SSH key items with a readable public_key in vault ${VAULT}." >&2
  if [[ ${#TITLES[@]} -gt 0 ]]; then
    echo "requested: ${TITLES[*]}" >&2
  fi
  echo >&2
  echo "Items in vault (title / type):" >&2
  list_item_rows | while IFS=$'\t' read -r title typ; do
    [[ -z $title ]] && continue
    printf '  - %s (%s)\n' "$title" "${typ:-?}" >&2
  done
  echo >&2
  echo "Try: ssh-pubs-from-pass --debug" >&2
  exit 1
fi

echo "Importing $count SSH key(s)…"
fail=0
for i in "${!FOUND_TITLES[@]}"; do
  if ! write_one "${FOUND_TITLES[$i]}" "${FOUND_PUBS[$i]}"; then
    fail=1
  fi
done

if [[ $DRY_RUN -eq 0 && $fail -eq 0 ]]; then
  echo
  echo "Pin in ~/.ssh/config with the matching .pub, e.g.:"
  echo "  Host github.com"
  echo "    User git"
  echo "    IdentitiesOnly yes"
  echo "    IdentityFile ~/.ssh/$(file_for_title "${FOUND_TITLES[0]}")"
fi

exit "$fail"
