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
  # merit needs an explicit require too: a path: gem re-evaluates its gemspec in-process,
  # and quintel_merit.gemspec requires merit/version, which defines Merit and would then
  # trip quintel_merit.rb's own "already defined" guard.
  declare -A GEMSPEC=(
    [merit]="quintel_merit|require: 'merit'"
    [atlas]="atlas"
    [fever]="fever"
    [refinery]="refinery"
    [identity_rails]="identity"
    [turbine]="turbine-graph|require: 'turbine'"
    [etplugin]="jquery-etmodel-rails"
  )

  dest=/tmp/dev-bundle
  mkdir -p "$dest"
  cp /app/Gemfile "$dest/Gemfile"
  [ -f /app/Gemfile.lock ] && cp /app/Gemfile.lock "$dest/Gemfile.lock"

  # Entries are "repo" (flat sibling, the default) or "repo=relative/path" for a
  # checkout that isn't a direct sibling. The path is always resolved under
  # /workspace, since that's the only directory the containers mount (see
  # compose.gems.yaml) — anything outside it is invisible to Bundler.
  IFS=',' read -ra entries <<< "$DEV_GEMS"
  for entry in "${entries[@]}"; do
    entry="$(echo "$entry" | xargs)"          # trim whitespace
    [ -z "$entry" ] && continue

    repo="${entry%%=*}"
    if [ "$entry" = "$repo" ]; then
      path="$repo"
    else
      path="$(echo "${entry#*=}" | xargs)"
    fi

    case "$path" in
      /*|*..*)
        echo "DEV_GEMS: '$path' must be a relative path under the parent directory (no leading / or ..) — that's the only directory mounted into the containers. Aborting." >&2
        exit 1
        ;;
    esac
    if [ ! -d "/workspace/$path" ]; then
      echo "DEV_GEMS: /workspace/$path not found — check the sibling checkout exists at that path. Aborting." >&2
      exit 1
    fi

    spec="${GEMSPEC[$repo]:-$repo}"
    name="${spec%%|*}"                        # gemspec name as it appears in the Gemfile
    extra=""
    [ "$spec" != "$name" ] && extra=", ${spec#*|}"   # preserve e.g. require: 'turbine'

    if grep -qE "^gem '$name'" "$dest/Gemfile"; then
      sed -i -E "s|^gem '$name'.*|gem '$name', path: '/workspace/$path'$extra|" "$dest/Gemfile"
      echo "→ DEV_GEMS: $name → /workspace/$path"
    fi
    # No match: this app doesn't declare $name — not an error, gems are app-specific (see README).
  done

  export BUNDLE_GEMFILE="$dest/Gemfile"
fi

# Quick no-op when satisfied; installs only the delta (incl. any path: gems above).
bundle check >/dev/null 2>&1 || bundle install --jobs=4 --retry=3

exec "$@"
