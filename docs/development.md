# Developing with ETLauncher

For contributing to ETLauncher, editing a gem locally, or the internals
behind the day-to-day commands in the main [`README.md`](../README.md).

## Working in the stack

Run app commands against the running services (they use each service's own
installed gems/packages):

```sh
docker compose exec etengine bin/rails console
docker compose exec -e RAILS_ENV=test etmodel bundle exec rspec
docker compose logs -f etmodel
docker compose exec database mysql -uroot -pdev   # the shared DB (all apps)
```

`RAILS_ENV=test` is required for specs: the containers set `RAILS_ENV=development`, so
`spec/rails_helper.rb`'s `ENV['RAILS_ENV'] ||= 'test'` never applies. Without it the
test-group gems are never required (`uninitialized constant FactoryBot`) and any spec
that did load would run against the development database.

There is no host-level access to the database - `database` has no port
mapped to the host, only to the other containers.

### From Docker Desktop (GUI)

The `bin/` scripts are host orchestration (they shell out to `docker compose`
and `docker inspect`), so they're **terminal-only** - Docker Desktop can't run
them. But once the stack exists you can do most day-to-day work from the GUI:

- **First run is terminal:** `./bin/up` once (builds, seeds, creates the
  project). The `etlauncher` project then appears under **Containers**.
- **Lifecycle:** start / stop / restart the project or a single service from
  the Containers view - no script needed for up/down. Use the **Logs** tab
  instead of `docker compose logs`.
- **Per-container tasks - Containers → service → Exec:**
  - `etengine` → `bin/rails db:migrate`, `bin/rails console`
  - `etmodel` → `bundle exec rspec`
  - `database` → `mysql -uroot -pdev` (password is `DB_ROOT_PASSWORD`)
- **Arrow keys not working in Exec?** Docker Desktop's **Exec** opens the
  container's basic `/bin/sh` (dash), which has **no command history or line
  editing**. Type `zsh` (or `bash`) for a full shell - or use a real terminal
  (`docker compose exec workspace zsh`).
- **Reset everything (destructive):** delete the `etlauncher_db_data` volume
  (**Volumes** tab), or delete the project with its volumes from the
  Containers view, then run `./bin/up` once to rebuild and reseed. Same as
  `docker compose down -v && ./bin/up`.
- **Stays terminal-only:** `./bin/up`, `./bin/update`, `./bin/seed-users`,
  `./bin/seed-oauth`, `./bin/db-dump`, `./bin/db-restore`.

## Code reloading

- **Rails apps (etengine, etmodel, myetm):** `app/` code, views, and routes
  reload on the next request (Zeitwerk in development). Restart the service
  for initializer or `settings.yml` changes: `docker compose restart etengine`.
- **Collections (Next.js):** runs `next dev` - components hot-reload in the
  browser instantly.
- **ETModel JS:** no dev server - `config/shakapacker.yml` has
  `compile: true`, so packs recompile on the next request. No live-reload;
  reload the page after a JS change.
- **ETSource:** switching branches in your `etsource/` checkout is picked up
  automatically by etengine's file watcher; make any request and it reloads
  from the new branch.

## Staying up to date

`./bin/update` exists because gems and yarn packages aren't baked into the
Docker image - they install from the `Gemfile`/`package.json` in the
bind-mounted repo when the container boots (see `bin/app-boot.sh`), into a
named volume that persists between runs. So a changed `Gemfile.lock` is picked
up by a container restart (a few seconds), not an image rebuild (slow).

```sh
./bin/update           # Gemfile/lock or package.json changed
./bin/update --build   # also rebuild images - only for Dockerfile / system-package changes
```

Safe to run anytime. Nothing reinstalls if the pull changed no dependencies, but the app
containers are always recreated - expect roughly a minute before every app serves again.

## Data lifecycle - does the DB persist?

**Yes.** All app databases live in **one** MySQL container backed by the
single `db_data` Docker **named volume** (mirroring prod's one MySQL per
server), independent of the container:

| Command | DB data |
|---------|---------|
| `docker compose stop` / `down`, reboot, `./bin/update` | **persists** |
| `docker compose down -v` | **destroyed** (volume removed) |

To snapshot and roll back **without** destroying anything (e.g. before risky
data work), use the dump/restore helpers - they write to the git-ignored
`dumps/`:

```sh
./bin/db-dump            # dumps all databases to dumps/database-<timestamp>.sql
# ... experiment ...
./bin/db-restore         # restores the latest dump
./bin/db-restore dumps/database-20260629-120000.sql   # or a specific file
```

To start completely clean (destroy data, rebuild, reseed):
`docker compose down -v && ./bin/up`.

## Dev container / workspace shell

The `workspace` service is the central toolchain - Ruby, Node, yarn, Python,
uv, pyetm, mysql-client, git - with every repo bind-mounted under
`/workspace`. It has no dependencies, so it runs **on its own without the app
stack** (you only need the stack up to talk to your local model).

**Open a shell** any of three ways:

```sh
# Terminal - stack down: starts a throwaway container, exits on Ctrl-D
docker compose run --rm workspace zsh
# Terminal - stack up: attach to the running container
docker compose exec workspace zsh
```

- **VS Code:** open the `ETLauncher` folder and choose **"Reopen in
  Container"**. This starts **only** the workspace (not the whole stack); the
  integrated terminal opens inside it. Start the apps separately with
  `./bin/up` when needed.
- **Docker Desktop:** **Containers → `etlauncher-workspace` → Exec**.

### Running pyetm

`pyetm` is installed system-wide - `import pyetm` works with no venv:

```sh
python3 -c "import pyetm; print(pyetm.__version__)"
```

### Notebooks

In VS Code, open a `.ipynb` and pick the container's Python interpreter
(`/usr/local/bin/python`) as the kernel. The bundled `ipykernel` + Jupyter
extension run it with no setup.

### Personal shell customisation

The workspace ships a stock oh-my-zsh shell with **no** baked team config -
bring your own dotfiles:

- **VS Code dev container:** point the dotfiles feature at your repo (it's
  cloned and installed into the container). Add to your *user* VS Code
  `settings.json`:
  ```json
  "dotfiles.repository": "your-github-user/dotfiles"
  ```
- **Terminal-only:** bind-mount your own `.zshrc`, e.g.
  `docker compose run --rm -v ~/.zshrc:/root/.zshrc workspace zsh`.

## Editing gems (DEV_GEMS)

By default the apps use the Quintel gems (merit, atlas, fever, refinery,
turbine, identity) pinned to a GitHub `ref:` in their `Gemfile` - matching CI
and production. (`turbine-graph` is the one exception: it floats on a
RubyGems version, `>=0.1`, not a GitHub ref.) To edit a gem locally without
pushing and bumping the ref, opt in per run with `DEV_GEMS`:

```sh
DEV_GEMS=merit,atlas ./bin/up        # or ./bin/update
```

Clone the gems you need as flat siblings, same level as the app repos:

```sh
git clone git@github.com:quintel/merit.git
git clone git@github.com:quintel/atlas.git
git clone git@github.com:quintel/fever.git
git clone git@github.com:quintel/rubel.git
git clone git@github.com:quintel/osmosis.git
git clone git@github.com:quintel/refinery.git
git clone git@github.com:quintel/turbine.git
git clone git@github.com:quintel/etplugin.git
git clone git@github.com:quintel/identity_rails.git
```

```
~/Quintel/
├── etengine/
├── etmodel/
├── etsource/
├── multi-year-charts/
├── my-etm/
├── ETLauncher/
├── merit/
├── atlas/
├── fever/
├── rubel/
├── osmosis/
├── refinery/
├── turbine/
├── etplugin/
└── identity_rails/
```

This mounts the parent directory into the app containers at `/workspace` and
rewrites the listed gems to `path:` overrides at boot, so edits in
`../merit`, `../atlas`, … are live in the running app. Unset `DEV_GEMS` and
re-run `./bin/up` to return to the pinned refs.

**Checkout not a flat sibling?** Give its path relative to the parent
directory: `DEV_GEMS=atlas=some/other/place`. The path must resolve under the
parent - that's the only directory mounted into the containers; anything
outside it doesn't exist as far as the container is concerned.

A missing or unresolvable checkout **fails the boot** rather than silently
falling back to the pinned ref - better to find out immediately than debug
why an edit isn't showing up.

Verify the override took:

```sh
docker compose exec -e BUNDLE_GEMFILE=/tmp/dev-bundle/Gemfile etengine \
  bundle info quintel_merit                                     # → Path: /workspace/merit
```

The `BUNDLE_GEMFILE` matters: app-boot.sh exports it only for the server process it
execs, so a plain `docker compose exec` reads the unmodified `/app/Gemfile` and reports
the pinned git ref - making a working override look broken.

Notes:
- Values are sibling repo dir names - `merit`, `atlas`, `fever`, `refinery`,
  `turbine`, `identity_rails`, `etplugin`, `rubel`, `osmosis` - mapped
  internally to the gem's name in the Gemfile.
- The local checkout should be on a branch whose history contains the `ref:`
  SHA pinned in the consuming app's `Gemfile`, so Bundler can still resolve
  the gem's own dependencies. Checking out the branch you're developing is
  enough.
- A gem only overrides in apps that actually declare it: `identity` applies
  to etengine + etmodel; `merit`/`atlas`/`fever`/`refinery`/`turbine` to
  etengine; `etplugin` to etmodel only.

## Running Collections as its production image (COLLECTIONS_PROD)

By default Collections runs `next dev` for instant hot reload. Staging and
production don't: both serve the `quintel/collections` image built from
`../multi-year-charts/Dockerfile` (`next build` + standalone `node
server.js`). To run that same image locally, opt in per run:

```sh
COLLECTIONS_PROD=1 ./bin/up
```

This layers `compose.collections-prod.yaml` over the base compose file. Use
it to verify a change behaves under a production build before deploying -
it's the only local path that exercises the build the deploy uses.

Notes:
- **No hot reload.** The image is built once; code changes need a rebuild:
  `COLLECTIONS_PROD=1 ./bin/update --build`.
- **`NEXT_PUBLIC_*` URLs are baked in at build time**, not read at runtime
  (Next inlines them into the client bundle). The overlay passes them as
  build args from your `.env` (`ETENGINE_URL`, `ETMODEL_URL`, `MYETM_URL`).
  Change a URL → rebuild.
- Server-only secrets (`NEXTAUTH_SECRET`, `AUTH_CLIENT_SECRET`, …) stay
  runtime env, so they do **not** require a rebuild.

## What `./bin/up` does

1. Creates `.env` from `.env.example` if missing; warns (doesn't overwrite)
   if an existing `.env` is missing a variable `.env.example` now has. Checks
   ports 3000/3001/3002/3005 are free and the sibling checkouts exist.
2. Reports Docker's disk usage, then removes ETLauncher's own stopped
   containers and leftover untagged images - filtered by the
   `com.docker.compose.project=etlauncher` label, so other projects are never
   touched. Builds images and starts the shared `database` (waits until
   healthy).
3. `db:prepare` for MyETM → ETEngine → ETModel (MyETM first - it is the OIDC
   issuer and its seed creates the admin user; all DBs live in the shared
   `database`).
4. `./bin/seed-users` + `./bin/seed-oauth` - idempotently create the dev
   admin/user and the Doorkeeper OAuth applications, with the fixed dev
   credentials from `.env`, so SSO works with no manual MyETM clicks.
5. Starts the whole stack.

## Troubleshooting

- **Docker disk filling up:** `bin/up` and `bin/update` only prune resources
  labelled as ETLauncher's, so a machine-wide clean-up is yours to run -
  `docker system prune` (add `-a` to drop unused tagged images too). Neither
  script does this for you because it reaches every other project on the
  machine and shrinks the shared build cache.
- **Python packages changed (e.g. pyetm version bump):** rebuild the
  workspace image - `docker compose build workspace` - then reconnect. Named
  volumes for Ruby/Node deps are unaffected.
- **ETModel JS schema errors after a deps change:** the named
  `etmodel_node_modules` volume can hold stale packages. Refresh it with
  `docker compose run --rm --no-deps etmodel yarn install`, then
  `docker compose up -d --force-recreate etmodel`.
- **Config overrides:** `overrides/` holds container-correct
  `settings.local.yml` files mounted read-only over each Rails app, so the
  orchestrated values win regardless of any personal `settings.local.yml` in
  your checkout (your host files are never modified).
- **Edited an override or `.env`? Recreate the app.** Compose doesn't detect
  bind-mounted *file-content* changes, and Rails reads settings only at boot,
  so a plain `docker compose up -d` won't pick them up - run
  `docker compose up -d --force-recreate <service>`. (Symptom of a stale app:
  an OIDC "redirect uri doesn't match" error after changing a `client_uri`.)
