# ETLauncher

One-command local development for the ETM: runs **ETEngine, ETModel, Collections
and MyETM** plus their databases on Docker, with a managed **dev-shell container**
so the toolchain and shell are maintained centrally instead of per laptop.

The only requirements are **Docker** and (optionally) **VS Code**.

## Layout (sibling checkouts)

ETLauncher orchestrates the app repos from sibling directories — it does not
contain them. Clone everything under one parent:
```
mkdir ~/Quintel && cd ~/Quintel
git clone git@github.com:quintel/etengine.git
git clone git@github.com:quintel/etmodel.git
git clone git@github.com:quintel/etsource.git
git clone git@github.com:quintel/multi-year-charts.git
git clone git@github.com:quintel/my-etm.git
git clone git@github.com:quintel/ETLauncher.git
```

Optionally for local dev, create a Gems subfolder and clone any necessary gems there:
```
mkdir Gems && cd Gems
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

This will create a directory with the following structure:
```
~/Quintel/
├── etengine/
├── etmodel/
├── etsource/
├── multi-year-charts/
├── my-etm/
├── ETLauncher/  ← this repo
└── Gems/        ← gems (only needed for local dev with DEV_GEMS)
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

Some data sources do not allow the redistribution of their data, in this case this data
is encripted and etengine will not process this request unless the decryption password
is placed in a file called `.password` in the ETSource directory, this is optional and
does not affect Netherlands data:
```
~/Quintel/
├── etsource/
│   ├── .password   # <- password goes here
│   ├── carriers
│   ├── config
│   ├── datasets
│   ├── ...
```

## Quick start

We need to add the hosts to `/etc/hosts` (each name resolves to loopback for the browser;
the same name is a Docker network alias inside the stack):

```
# etm-stack (local ETM development)
127.0.0.1  myetm.local.energytransitionmodel.com
127.0.0.1  etmodel.local.energytransitionmodel.com
127.0.0.1  etengine.local.energytransitionmodel.com
127.0.0.1  collections.local.energytransitionmodel.com
```

Docker [desktop client](https://www.docker.com/products/docker-desktop/) must be runing beforehand.

So that we can start everything with:

```sh
cd ~/Quintel/ETLauncher
./bin/up                 # build, create DBs, seed OAuth apps, start everything
```

Then, you can open each app at its **own `*.local.energytransitionmodel.com` host**:

| App | URL |
|-----|-----|
| ETEngine | http://etengine.local.energytransitionmodel.com:3000 |
| ETModel | http://etmodel.local.energytransitionmodel.com:3001 |
| MyETM | http://myetm.local.energytransitionmodel.com:3002 |
| Collections | http://collections.local.energytransitionmodel.com:3005 |

**Logins** (seeded, dev-only — see [`CREDENTIALS.md`](CREDENTIALS.md), also printed by
`./bin/up`): admin `admin@etm.local` / `etm-admin`, regular user
`user@etm.local` / `etm-user`.

## Staying up to date

Most pulls need nothing — app code, views, routes, JS, and `etsource` branch
switches propagate automatically into the running containers (see
[Code reloading](#code-reloading)). Run `./bin/update` only when a pull changed
dependencies or build inputs:

```sh
./bin/update           # Gemfile/lock or package.json changed (gems/yarn install on boot)
./bin/update --build   # also rebuild images (only for Dockerfile / system-package changes)
```

`./bin/update` is safe to run anytime — if nothing changed in the pull, it
simply does nothing. So when in doubt after a pull, just run it. Most days you
won't need to: app code reloads on its own (see *Code reloading*), and even a
dependency change is quick. The gems aren't baked into the Docker image; they're
installed when the container starts. So a changed `Gemfile` is picked up by
restarting the container (a few seconds) rather than rebuilding the whole image
(slow). The *Speed* section below explains how this works.

## Working in the stack

Run app commands against the running services (they use each service's own
installed gems/packages):

```sh
docker compose exec etengine bin/rails console
docker compose exec etmodel  bundle exec rspec
docker compose logs -f etmodel
mysql -h 127.0.0.1 -u root -pdev          # the shared DB (all apps), from the host
```

### From Docker Desktop (GUI)

The `bin/` scripts are host orchestration (they shell out to `docker compose` and
`docker inspect`), so they're **terminal-only** — Docker Desktop can't run them. But once
the stack exists you can do most day-to-day work from the GUI:

- **First run is terminal:** `./bin/up` once (builds, seeds, creates the project). The
  `etlauncher` project then appears under **Containers**.
- **Lifecycle:** start / stop / restart the project or a single service from the Containers
  view — no script needed for up/down. Use the **Logs** tab instead of `docker compose logs`.
- **Per-container tasks — Containers → service → Exec:**
  - `etengine` → `bin/rails db:migrate`, `bin/rails console`
  - `etmodel` → `bundle exec rspec`
  - `database` → `mysql -uroot -pdev` (the shared DB; password is `DB_ROOT_PASSWORD`)
- **Arrow keys not working in Exec?** Docker Desktop's **Exec** opens the container's
  basic `/bin/sh` (dash), which has **no command history or line editing**. Type `zsh`
  (or `bash`) to get a full shell with up-arrow history and cursor movement — or do
  interactive work from a real terminal (`docker compose exec workspace zsh`), where it
  works out of the box.
- **Reset everything (destructive):** delete the data volume from the **Volumes** tab
  (`etlauncher_db_data`) — or delete the project with its volumes from the Containers
  view — then run `./bin/up` once to rebuild and reseed. Same as
  `docker compose down -v && ./bin/up`.
- **Stays terminal-only:** `./bin/up`, `./bin/update`, `./bin/seed-users`,
  `./bin/seed-oauth`, `./bin/db-dump`, `./bin/db-restore`.

### Code reloading

Changes to source files propagate automatically — no container restarts needed for day-to-day editing:

- **Rails apps (etengine, etmodel, myetm):** `app/` code, views, and routes reload on the
  next request (Zeitwerk in development). Restart the service for initializer or
  `settings.yml` changes: `docker compose restart etengine`.
- **Collections (Next.js):** runs `next dev` — components hot-reload in the browser instantly.
- **ETModel JS:** no dev server — `config/shakapacker.yml` has `compile: true`, so packs
  recompile on the next request. No live-reload; reload the page after a JS change.
- **ETSource:** switching branches in your `etsource/` checkout is picked up automatically
  by etengine's file watcher; make any request and it reloads from the new branch.

`./bin/update` does **not** run database migrations. If a pull adds migrations,
apply them yourself: `docker compose exec etengine bin/rails db:migrate`.

### Editing gems (DEV_GEMS)

By default the apps use the Quintel gems (merit, atlas, fever, refinery, turbine,
identity) pinned to a GitHub `ref:` in their `Gemfile` — matching CI and production.
To edit a gem **locally without pushing and bumping the SHA**, opt in per run with
`DEV_GEMS` (comma-separated sibling repo dir names):

```sh
DEV_GEMS=merit,atlas ./bin/up        # or ./bin/update
```

This mounts the sibling checkouts into the app containers under `/workspace` and
rewrites the listed gems to `path:` overrides at boot, so your edits in
`../merit`, `../atlas`, … are live in the running app. Unset `DEV_GEMS` and re-run
`./bin/up` to return to the pinned refs.

Verify the override took:

```sh
DEV_GEMS=merit docker compose exec etengine bundle info quintel_merit   # → /workspace/merit
```

Notes:
- Values are **sibling repo dir names** (`merit`, `atlas`, `fever`, `refinery`,
  `turbine`, `identity_rails`), mapped internally to the gem's name in the Gemfile.
- The local checkout should be on a branch whose history contains the `ref:` SHA
  pinned in the consuming app's `Gemfile`, so Bundler can still resolve the gem's
  own dependencies. Checking out the branch you're developing is enough.
- A gem only overrides in apps that actually declare it (e.g. `identity` applies to
  etengine + etmodel; `merit`/`atlas`/`fever`/`refinery`/`turbine` to etengine).

### Running Collections as its production image (COLLECTIONS_PROD)

By default Collections runs `next dev` for instant hot reload. To instead run it the
way the Docker deploy will — built from `../multi-year-charts/Dockerfile` (`next build`
+ standalone `node server.js`) — opt in per run:

```sh
COLLECTIONS_PROD=1 ./bin/up
```

This layers `compose.collections-prod.yaml` over the base compose file. Use it to
verify a change behaves under a production build before deploying.

Notes:
- **No hot reload.** The image is built once; code changes need a rebuild:
  `COLLECTIONS_PROD=1 ./bin/update --build`.
- **`NEXT_PUBLIC_*` URLs are baked in at build time**, not read at runtime (Next inlines
  them into the client bundle). The overlay passes them as build args from your `.env`
  (`ETENGINE_URL`, `ETMODEL_URL`, `MYETM_URL`). Change a URL → rebuild. This is the
  key difference from the `next dev` default and why a Docker deploy rebuilds per
  environment
- Server-only secrets (`NEXTAUTH_SECRET`, `AUTH_CLIENT_SECRET`, …) stay runtime env, so
  they do **not** require a rebuild.

### Dev container / workspace shell

The `workspace` service is the central toolchain — Ruby, Node, yarn, Python, uv,
pyetm, mysql-client, git — with every repo bind-mounted under `/workspace`. It
has no dependencies, so you can use it **on its own without starting the app stack**
(you only need the stack up to talk to your *local* model — see below).

**Open a shell** any of three ways:

```sh
# Terminal — stack down: starts a throwaway container, exits on Ctrl-D
docker compose run --rm workspace zsh
# Terminal — stack up: attach to the running container
docker compose exec workspace zsh
```

- **VS Code:** open the `ETLauncher` folder and choose **"Reopen in Container"**. This
  starts **only** the workspace (not the whole stack); the integrated terminal opens inside
  it. Start the apps separately with `./bin/up` when you actually need them.
- **Docker Desktop:** **Containers → `etlauncher-workspace` → Exec** opens a shell in the
  running container.

#### Running pyetm

`pyetm` is installed system-wide, so `import pyetm` works with no venv:

```sh
python3 -c "import pyetm; print(pyetm.__version__)"
```

#### Notebooks

In VS Code, open a `.ipynb` and pick the container's Python interpreter
(`/usr/local/bin/python`) as the kernel. The bundled `ipykernel` + Jupyter extension run it
with no setup.

**Personal shell customisation:** the workspace ships a stock oh-my-zsh shell with
**no** baked team config — bring your own `.zshrc`/dotfiles. Two ways:

- **VS Code dev container:** point the dotfiles feature at your repo (it's cloned and
  installed into the container). Add to your *user* VS Code `settings.json`:
  ```json
  "dotfiles.repository": "your-github-user/dotfiles"
  ```
- **Terminal-only:** bind-mount your own `.zshrc` into the workspace, e.g.
  `docker compose run --rm -v ~/.zshrc:/root/.zshrc workspace zsh`.

## Data lifecycle — does the DB persist?

**Yes.** All app databases live in **one** MySQL container backed by the single
`db_data` Docker **named volume** (mirroring prod's one MySQL per server), which is
independent of the container:

| Command | DB data |
|---------|---------|
| `docker compose stop` / `down`, reboot, `./bin/update` | **persists** |
| `docker compose down -v` | **destroyed** (volume removed) |

To snapshot and roll back **without** destroying anything (e.g. before risky
data work), use the dump/restore helpers — they write to the git-ignored `dumps/`:

```sh
./bin/db-dump            # dumps all databases to dumps/database-<timestamp>.sql
# ... experiment ...
./bin/db-restore         # restores the latest dump
./bin/db-restore dumps/database-20260629-120000.sql   # or a specific file
```

To start completely clean (destroy data, then rebuild and reseed), run
`docker compose down -v && ./bin/up`. From Docker Desktop: delete the
`etlauncher_db_data` volume (**Volumes** tab) — or the project with its volumes from
**Containers** — then `./bin/up` once.


## What `./bin/up` does

1. Creates `.env` from the example if missing; checks the sibling checkouts exist.
2. Builds images and starts the shared `database` (waits until healthy).
3. `db:prepare` for MyETM → ETEngine → ETModel (MyETM first — it is the OIDC
   issuer and its seed creates the admin user; all DBs live in the shared `database`).
4. `./bin/seed-users` + `./bin/seed-oauth` — idempotently create the dev admin/user
   and the Doorkeeper OAuth applications, with the fixed dev credentials from `.env`,
   so SSO works with no manual MyETM clicks.
5. Starts the whole stack.

## Notes & troubleshooting

- **Gemfile / package.json changed:** just `./bin/update` (gems/yarn install on
  boot). `./bin/update --build` only if a Dockerfile or system package changed.
- **Python packages changed (e.g. pyetm version bump):** rebuild the workspace image —
  `docker compose build workspace` — then reconnect. Named volumes for Ruby/Node deps
  are unaffected.
- **Reset everything (destroys all DB data):** `docker compose down -v && ./bin/up`,
  or from Docker Desktop delete the `etlauncher_db_data` volume (**Volumes** tab) then
  run `./bin/up`.
- **ETModel JS schema errors after a deps change:** the named `etmodel_node_modules`
  volume can hold stale packages. Refresh it with
  `docker compose run --rm --no-deps etmodel yarn install`, then
  `docker compose up -d --force-recreate etmodel`.
- **Config overrides:** `overrides/` holds container-correct `settings.local.yml`
  files mounted read-only over each Rails app, so the orchestrated values win
  regardless of any personal `settings.local.yml` in your checkout (your host
  files are never modified).
- **Edited an override or `.env`? Recreate the app.** Compose does not detect
  bind-mounted *file-content* changes, and Rails reads settings only at boot, so a
  plain `docker compose up -d` won't pick them up — run
  `docker compose up -d --force-recreate <service>`. (Symptom of a stale app: an
  OIDC "redirect uri doesn't match" error after changing a `client_uri`.)
- **Always open apps at `<service>.local.energytransitionmodel.com:<port>`**, not
  bare `localhost:<port>`. The OAuth callback targets the app's configured host, so
  **starting on a different host strands the session cookie and breaks login.**
