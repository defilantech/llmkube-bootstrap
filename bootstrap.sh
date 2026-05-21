#!/usr/bin/env bash
#
# llmkube-bootstrap entrypoint.
#
# Job in three sentences:
#   1. Make sure Xcode CLT + Homebrew + Ansible exist on this Mac.
#   2. Install Ansible Galaxy collections the playbook needs.
#   3. Run the playbook against localhost with the right --tags
#      derived from --with-foreman / --with-carnice flags.
#
# Re-runnable. Each step short-circuits when its outcome already holds.

set -euo pipefail

WITH_FOREMAN=0
WITH_CARNICE=0
EXTRA_ARGS=()

usage() {
  cat <<'EOF'
Usage: ./bootstrap.sh [--with-foreman] [--with-carnice] [-- <extra ansible-playbook args>]

Flags:
  --with-foreman   Install the Foreman agentic-workload add-on.
  --with-carnice   Pull the Carnice 35B GGUF (~36 GB) and deploy it
                   as a second InferenceService.

Anything after `--` is passed through to ansible-playbook (e.g.
`--check --diff` for a dry run, or `-vv` for verbose).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-foreman) WITH_FOREMAN=1; shift ;;
    --with-carnice) WITH_CARNICE=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; EXTRA_ARGS=("$@"); break ;;
    *)              echo "bootstrap: unknown flag: $1" >&2; usage; exit 64 ;;
  esac
done

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- 1. Xcode Command Line Tools -----------------------------------------

if ! xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (a GUI dialog will appear)"
  xcode-select --install || true
  log "Waiting for Xcode CLT install to finish; re-run this script when the dialog closes."
  exit 1
fi
log "Xcode Command Line Tools present: $(xcode-select -p)"

# --- 2. Homebrew ----------------------------------------------------------

if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH for the current shell. On Apple Silicon brew
# installs to /opt/homebrew; on Intel to /usr/local. shellenv is the
# blessed way to get the right one onto PATH idempotently.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

log "Homebrew on PATH: $(brew --version | head -1)"

# --- 3. Ansible -----------------------------------------------------------

if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "Installing Ansible via Homebrew"
  brew install ansible
fi
log "Ansible: $(ansible --version | head -1)"

# Galaxy collections the playbook depends on. requirements.yml is the
# source of truth; we just call ansible-galaxy with it.
log "Installing Ansible Galaxy collections"
ansible-galaxy collection install -r requirements.yml >/dev/null

# --- 4. Compose the --tags list from the opt-in flags ---------------------

TAGS="always,base"
if (( WITH_FOREMAN )); then TAGS="${TAGS},foreman"; fi
if (( WITH_CARNICE )); then TAGS="${TAGS},carnice"; fi

log "Running playbook with tags: ${TAGS}"

ansible-playbook \
  -i inventory/localhost.yml \
  playbook.yml \
  --tags "${TAGS}" \
  --diff \
  "${EXTRA_ARGS[@]:-}"

log "Bootstrap complete. Next: set the secrets listed in README.md."
