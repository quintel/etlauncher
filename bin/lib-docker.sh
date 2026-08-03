#!/usr/bin/env bash
# Shared by bin/up and bin/update: Docker housekeeping that stays inside ETLauncher's
# own resources. Source this file, then call report_docker_usage and
# prune_etlauncher_resources.

COMPOSE_PROJECT_LABEL="label=com.docker.compose.project=etlauncher"

# Printed before every build. A build that runs out of disk reports it as an opaque
# error, so the numbers that explain it need to already be on screen — including how
# much a prune would reclaim, and from which projects.
report_docker_usage() {
  echo "Docker disk usage — every project on this machine, not just ETLauncher:"
  docker system df
  echo "If a build below fails for disk space, reclaim it yourself with"
  echo "'docker system prune' (or Docker Desktop → Settings → Resources)."
}

# Remove ETLauncher's own stopped containers and the untagged images its rebuilds
# leave behind. Compose stamps both with com.docker.compose.project, so this cannot
# reach another project's work — unlike a bare 'docker system prune', which also
# removes other projects' stopped containers and shrinks the shared build cache.
# Volumes are never pruned here, so db_data and the bundle caches survive.
prune_etlauncher_resources() {
  echo "Removing ETLauncher's stopped containers and leftover images..."
  docker container prune -f --filter "$COMPOSE_PROJECT_LABEL" >/dev/null
  docker image prune -f --filter "$COMPOSE_PROJECT_LABEL" >/dev/null
}
