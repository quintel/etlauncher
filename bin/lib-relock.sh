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

  if [ -f "$lock" ] && [ "$(locked_bundler_major "$lock")" != "$TOOLCHAIN_BUNDLER_MAJOR" ]; then
    echo "→ $app: Gemfile.lock is from Bundler $(locked_bundler_major "$lock"), the toolchain's is $TOOLCHAIN_BUNDLER_MAJOR. Not relocked."
    return 0
  fi

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

# Relocking rewrites BUNDLED WITH to the toolchain's Bundler, which an older Version's
# Ruby cannot install, so a lockfile from another major is left alone.
locked_bundler_major() {
  awk '/^BUNDLED WITH/ { getline; split($1, v, "."); print v[1] }' "$1"
}

relock_all() {
  echo "→ Ensuring toolchain image..."
  ensure_workspace_image
  TOOLCHAIN_BUNDLER_MAJOR="$(docker compose run --rm --no-deps -T workspace bundle --version | grep -oE '[0-9]+' | head -1)"
  for app in etengine etmodel my-etm; do
    relock_if_needed "$app"
  done
}
