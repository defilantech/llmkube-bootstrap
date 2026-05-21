#!/usr/bin/env bash
#
# Nuke the LLMKube layer for re-testing. Deliberately preserves
# Homebrew, Docker Desktop, and your shell config — those are part of
# the machine, not the LLMKube install.

set -euo pipefail

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- metal-agent launchd unit --------------------------------------------

PLIST="$HOME/Library/LaunchAgents/com.llmkube.metal-agent.plist"
if [[ -f "$PLIST" ]]; then
  log "Unloading + removing metal-agent launchd unit"
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
fi

# --- foreman-{operator,agent} background processes -----------------------

for proc in foreman-operator foreman-agent; do
  if pgrep -fl "bin/${proc}" >/dev/null 2>&1; then
    log "Stopping ${proc}"
    pkill -f "bin/${proc}" || true
  fi
done

# --- kind cluster --------------------------------------------------------

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q '^llmkube-local$'; then
  log "Deleting kind cluster llmkube-local"
  kind delete cluster --name llmkube-local
fi

# --- local model store (downloaded GGUFs) --------------------------------

if [[ -d "$HOME/llmkube-models" ]]; then
  log "Removing $HOME/llmkube-models (downloaded GGUFs)"
  rm -rf "$HOME/llmkube-models"
fi

# --- foreman workspaces ---------------------------------------------------

if [[ -d "$HOME/foreman-workspaces" ]]; then
  log "Removing $HOME/foreman-workspaces"
  rm -rf "$HOME/foreman-workspaces"
fi

log "Teardown complete. Homebrew, Docker Desktop, and ~/src/LLMKube are preserved."
log "Run ./bootstrap.sh to rebuild."
