#!/usr/bin/env bash
# Shared by bin/up and bin/update: keep each app's Gemfile.lock in sync with its
# Gemfile so the frozen image build doesn't abort on an un-relocked change.
# Relocked via the bind-mounted workspace toolchain so users never run bundler
# themselves. Source this file, then call relock_all.

ensure_workspace_image() {
  if ! docker image inspect etlauncher-workspace >/dev/null 2>&1; then
    docker compose build workspace
  fi
}

relock_if_needed() {
  local app="$1"
  local lock="../$app/Gemfile.lock"
  [ -f "../$app/Gemfile" ] || return 0

  local before=""
  [ -f "$lock" ] && before=$(shasum "$lock" | awk '{ print $1 }')

  docker compose run --rm --no-deps -T -w "/workspace/$app" workspace bundle lock >/dev/null 2>&1 || {
    echo "Could not update $app/Gemfile.lock." >&2
    echo "  If a gem points at a private repo, the toolchain needs git access" >&2
    echo "  (e.g. SSH agent forwarding into the 'workspace' service)." >&2
    exit 1
  }

  [ "$(shasum "$lock" | awk '{ print $1 }')" != "$before" ] && echo "→ $app: Gemfile.lock updated to match Gemfile."
  return 0
}

relock_all() {
  echo "→ Ensuring toolchain image..."
  ensure_workspace_image
  for app in etengine etmodel MyETM; do
    relock_if_needed "$app"
  done
}
