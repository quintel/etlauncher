#!/usr/bin/env bash
# Shared by bin/up and bin/update: preflight checks and the proxy's certificate.

LOCAL_DOMAIN="local.energytransitionmodel.com"
APP_HOSTNAMES=(
  "myetm.$LOCAL_DOMAIN"
  "etmodel.$LOCAL_DOMAIN"
  "etengine.$LOCAL_DOMAIN"
  "collections.$LOCAL_DOMAIN"
)

# mkcert -install is idempotent. It asks for your password once/twice, the first time it adds
# the local CA to the system keychain. nss lets it reach Firefox's own store too.
require_mkcert() {
  if ! command -v mkcert >/dev/null 2>&1; then
    echo "mkcert is not installed. Run 'brew install mkcert nss' to install it, then re-run." >&2
    exit 1
  fi
  if ! mkcert -install; then
    echo "mkcert could not install its local CA. Fix the error above, then re-run." >&2
    exit 1
  fi
}

require_free_ports() {
  local busy=() port
  for port in 80 443; do
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && busy+=("$port")
  done
  [ ${#busy[@]} -eq 0 ] && return 0
  echo "Port(s) already in use: ${busy[*]}" >&2
  echo "Either ETLauncher is already running (nothing to do, see 'Stop / start' in the" >&2
  echo "README), or something else is listening (e.g. a local web server). Stop it first." >&2
  exit 1
}

# Aborts rather than warns: a URL change keeps the variable name, so only the value is stale.
require_current_env_urls() {
  local stale=() key value current
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Z_]+_URL$ ]] || continue
    current="$(grep "^${key}=" .env | tail -1 | cut -d= -f2- || true)"
    [ -n "$current" ] && [ "$current" != "$value" ] && stale+=("${key}=${value}")
  done < .env.example
  [ ${#stale[@]} -eq 0 ] && return 0
  echo ".env has app URLs that no longer match .env.example. Change these lines in .env:" >&2
  printf '  %s\n' "${stale[@]}" >&2
  echo "Then re-run. Your databases and scenarios are kept." >&2
  exit 1
}

require_hosts_entries() {
  local missing=() host
  for host in "${APP_HOSTNAMES[@]}"; do
    grep -v '^[[:space:]]*#' /etc/hosts | grep -qw -- "$host" || missing+=("$host")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  echo "/etc/hosts has no entry for: ${missing[*]}" >&2
  echo "Add them with:" >&2
  echo "  sudo sh -c 'echo \"127.0.0.1  ${APP_HOSTNAMES[*]}\" >> /etc/hosts'" >&2
  exit 1
}

# A build that runs out of disk fails part way, with unclear errors - clarify.
require_free_docker_disk() {
  local needed_gb=10 free_gb
  free_gb="$(docker run --rm -q alpine:3 df -Pk / | awk 'NR == 2 { print int($4 / 1048576) }')"
  [ "$free_gb" -ge "$needed_gb" ] && return 0
  echo "Docker has ${free_gb} GB of disk free. bin/up needs about ${needed_gb} GB to build." >&2
  echo "Clear the build cache with 'docker builder prune', or" >&2
  echo "raise the disk size in Docker Desktop, Settings, Resources. Then re-run." >&2
  exit 1
}

# A stable stack's apps must be on its Version's line. That is the branch itself, or a
# feature branch sharing a commit with origin/<branch> that origin/master lacks.
require_version_branches() {
  local branch="$1" repo
  for repo in etengine etmodel multi-year-charts etsource; do
    require_version_branch "$repo" "$branch"
  done
}

require_version_branch() {
  local repo="$1" branch="$2" base current
  if ! git -C "../$repo" rev-parse -q --verify "origin/$branch^{commit}" >/dev/null; then
    echo "$repo has no origin/$branch. Run 'git -C ../$repo fetch origin', then re-run." >&2
    exit 1
  fi
  current="$(git -C "../$repo" branch --show-current)"
  [ "$current" = "$branch" ] && return 0
  base="$(git -C "../$repo" merge-base HEAD "origin/$branch")"
  git -C "../$repo" merge-base --is-ancestor "$base" origin/master || return 0
  echo "$repo is on ${current:-a detached HEAD}, not the $branch line." >&2
  echo "Run 'git -C ../$repo checkout $branch', then re-run." >&2
  exit 1
}

# Named so nginx-proxy matches it to every VIRTUAL_HOST. Reissued if it stops verifying.
issue_local_certificate() {
  local cert="certs/$LOCAL_DOMAIN.crt"
  mkdir -p certs/ca
  cp "$(mkcert -CAROOT)/rootCA.pem" certs/ca/rootCA.pem
  openssl verify -CAfile certs/ca/rootCA.pem "$cert" >/dev/null 2>&1 && return 0
  mkcert -cert-file "$cert" -key-file "certs/$LOCAL_DOMAIN.key" "*.$LOCAL_DOMAIN"
}
