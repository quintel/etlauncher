#!/usr/bin/env bash
# ETLauncher app boot wrapper — entrypoint for the etengine/etmodel/myetm containers.
#
#   1. Warm gems: gems live in a named volume, so a Gemfile change is picked up by a
#      quick `bundle install` at boot (bundle check short-circuits) — no image rebuild.
#   2. DEV_GEMS: when set (comma-separated sibling repo dir names), the listed gems are
#      swapped for live /workspace checkouts via a generated path-override Gemfile, so a
#      gem can be edited with no push + SHA bump. Off by default (pinned refs match prod).
#
# Usage: app-boot.sh <server command...>
set -euo pipefail

# Never frozen in dev — we install deltas at boot.
bundle config unset frozen >/dev/null 2>&1 || true

if [ -n "${DEV_GEMS:-}" ]; then
  # Map sibling repo dir -> "<gemspec-name>" as written in the consuming Gemfiles,
  # optionally "|<extra gem options to preserve>" (turbine is required as 'turbine').
  declare -A GEMSPEC=(
    [merit]="quintel_merit"
    [atlas]="atlas"
    [fever]="fever"
    [refinery]="refinery"
    [identity_rails]="identity"
    [turbine]="turbine-graph|require: 'turbine'"
  )

  dest=/tmp/dev-bundle
  mkdir -p "$dest"
  cp /app/Gemfile "$dest/Gemfile"
  [ -f /app/Gemfile.lock ] && cp /app/Gemfile.lock "$dest/Gemfile.lock"

  IFS=',' read -ra repos <<< "$DEV_GEMS"
  for repo in "${repos[@]}"; do
    repo="$(echo "$repo" | xargs)"            # trim whitespace
    [ -z "$repo" ] && continue
    spec="${GEMSPEC[$repo]:-$repo}"
    name="${spec%%|*}"                        # gemspec name as it appears in the Gemfile
    extra=""
    [ "$spec" != "$name" ] && extra=", ${spec#*|}"   # preserve e.g. require: 'turbine'

    if [ ! -d "/workspace/$repo" ]; then
      echo "DEV_GEMS: /workspace/$repo not found — is the sibling checkout present? Skipping." >&2
      continue
    fi
    if grep -qE "^gem '$name'" "$dest/Gemfile"; then
      sed -i -E "s|^gem '$name'.*|gem '$name', path: '/workspace/$repo'$extra|" "$dest/Gemfile"
      echo "→ DEV_GEMS: $name → /workspace/$repo"
    fi
  done

  export BUNDLE_GEMFILE="$dest/Gemfile"
fi

# Quick no-op when satisfied; installs only the delta (incl. any path: gems above).
bundle check >/dev/null 2>&1 || bundle install --jobs=4 --retry=3

exec "$@"
