#!/usr/bin/env bash
# Sourced by every bin/ script that calls docker compose. It points compose at the stack
# bin/up last started.

# Gitignored. Holds the Version tag bin/up last started; absent means latest.
STACK_FILE=".stack"

# Everything follows from the tag: 2025.01 runs the 2025-01 branches as project
# etlauncher-2025-01. Latest keeps the project name etlauncher, so its data survives.
use_stack() {
  VERSION_TAG="$1"
  STACK_BRANCH="${VERSION_TAG//./-}"
  COMPOSE_PROJECT_NAME="etlauncher"
  [ "$VERSION_TAG" != "latest" ] && COMPOSE_PROJECT_NAME="etlauncher-$STACK_BRANCH"
  COMPOSE_PROJECT_LABEL="label=com.docker.compose.project=$COMPOSE_PROJECT_NAME"
  export VERSION_TAG COMPOSE_PROJECT_NAME
}

record_stack() {
  echo "$VERSION_TAG" > "$STACK_FILE"
}

use_stack "$(cat "$STACK_FILE" 2>/dev/null || echo latest)"

# Stacks share ports 80, 443 and 3307, so only one runs at a time. Stopping keeps the
# other stack's containers and data, so users can switch back and forth.
stop_other_stacks() {
  local project
  for project in $(docker ps --format '{{.Label "com.docker.compose.project"}}' | sort -u); do
    [[ "$project" =~ ^etlauncher(-.+)?$ ]] && [ "$project" != "$COMPOSE_PROJECT_NAME" ] || continue
    echo "Stopping the $project stack so $COMPOSE_PROJECT_NAME can take its ports..."
    docker stop $(docker ps -q --filter "label=com.docker.compose.project=$project") >/dev/null
  done
}

# Printed before every build. A build that runs out of disk reports it as an opaque
# error, so the numbers that explain it need to already be on screen — including how
# much a prune would reclaim, and from which projects.
report_docker_usage() {
  echo "Docker disk usage — every project on this machine, not just ETLauncher:"
  docker system df
  echo "If a build below fails for disk space, reclaim it yourself with"
  echo "'docker system prune' (or Docker Desktop → Settings → Resources)."
}

# Remove this stack's own stopped containers and the untagged images its rebuilds
# leave behind. Compose stamps both with com.docker.compose.project, so this cannot
# reach another project's work — unlike a bare 'docker system prune', which also
# removes other projects' stopped containers and shrinks the shared build cache.
# Volumes are never pruned here, so db_data and the bundle caches survive.
prune_etlauncher_resources() {
  echo "Removing $COMPOSE_PROJECT_NAME's stopped containers and leftover images..."
  docker container prune -f --filter "$COMPOSE_PROJECT_LABEL" >/dev/null
  docker image prune -f --filter "$COMPOSE_PROJECT_LABEL" >/dev/null
}
