# ETLauncher

One-command local ETM: ETEngine, ETModel, Collections and MyETM plus their
databases on Docker, with a managed dev-shell container so the toolchain is
maintained centrally instead of per laptop. macOS only.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/), running.
  **Settings → Resources:** at least 8 GB memory, 40 GB disk image size. The
  stack's images and volumes come to roughly 10 GB; the rest is headroom for
  rebuilds and Docker's build cache, which can grow over time.
- `git`, with an [SSH key added to your GitHub
  account](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)
  - every repo below is cloned over `git@github.com:`.
- Ports 3000, 3001, 3002 and 3005 free - if anything else is listening on
  these (e.g. a natively-running ETM), ETLauncher will not work.

## 1. Clone the repos

Your repositories should be flat siblings, inside one parent directory with no subfolders:

```
~/ETM/
├── etengine/
├── etmodel/
├── etsource/
├── multi-year-charts/
├── my-etm/
└── etlauncher/  ← this repo
```

> Note: You can call the parent directory whatever you want.

If you already have the repositories, inside your parent directory run:

```sh
git clone git@github.com:quintel/etlauncher.git
```

### Starting from scratch

```sh
mkdir ~/ETM && cd ~/ETM
git clone git@github.com:quintel/etengine.git
git clone git@github.com:quintel/etmodel.git
git clone git@github.com:quintel/etsource.git
git clone git@github.com:quintel/multi-year-charts.git
git clone git@github.com:quintel/my-etm.git
git clone git@github.com:quintel/etlauncher.git
```

Some ETSource data is encrypted. If you have the decryption password, place it
at `etsource/.password`. Without it the stack still runs only certain datasets are not accessible.

## 2. Add hosts

Each app needs its own hostname which needs to be added to `/etc/hosts`. Add them with the following command:

```sh
grep -q myetm.local.energytransitionmodel.com /etc/hosts || sudo sh -c 'echo "127.0.0.1  myetm.local.energytransitionmodel.com etmodel.local.energytransitionmodel.com etengine.local.energytransitionmodel.com collections.local.energytransitionmodel.com" >> /etc/hosts'
```
> You will be prompted for your password - it is your computer's password. You will not see anything when you type.

## 3. Start

```sh
cd ~/ETM/etlauncher
./bin/up
```

Builds images, creates databases, seeds users and OAuth apps, starts
everything. It will take several minutes on the first run.

## 4. Log in

There's no sign-up - every app shares one seeded login via MyETM (the OIDC
provider). Open any app below and log in with:

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@etm.local` | `etm-admin` |
| Regular user | `user@etm.local` | `etm-user` |

> Note: Collections needs about a minute after `bin/up`
> finishes (it installs its packages on first boot), so give it
> a moment if it refuses the connection:

| App | URL |
|-----|-----|
| ETEngine | http://etengine.local.energytransitionmodel.com:3000 |
| ETModel | http://etmodel.local.energytransitionmodel.com:3001 |
| MyETM | http://myetm.local.energytransitionmodel.com:3002 |
| Collections | http://collections.local.energytransitionmodel.com:3005 |

## 5. Import scenarios (optional)

A fresh stack starts with no scenarios. To bring some in, get an `.etm` export
from **Admin → All Scenarios → Export selected** on a production/staging
MyETM (or another local instance). It downloads to your `Downloads` folder.

Import runs **inside the `my-etm` container**, not on your host. Put the file
somewhere the container can see it first (the `my-etm` checkout is
bind-mounted in, and its `tmp/` is already git-ignored):

```sh
mv ~/Downloads/*.etm ../my-etm/tmp/
docker compose exec my-etm bin/import-scenarios tmp
```

It prompts for confirmation and, if `tmp/` has more than one `.etm` file,
which to import. Scenarios are owned by the admin user (above) by default;
`--user your.email@quintel.com` sets a different owner, `--on-dup create`
always creates new scenarios instead of updating existing ones with matching
IDs. Full options: `docker compose exec my-etm bin/import-scenarios --help`.

## Everyday use

**Which command do I actually run?**

| I want to... | Do this |
|---|---|
| Pause the stack (e.g. end of day) | Docker Desktop **Stop** on the `etlauncher` project (or `docker compose stop`) |
| Resume it | Docker Desktop **Start** (or `docker compose start`) - same containers, same data, fast |
| Pick up a `git pull` (Gemfile/package.json changed, or a migration) | `./bin/update` |
| Pick up a Dockerfile / system package change | `./bin/update --build` |
| Wipe everything and start clean | `docker compose down -v && ./bin/up` |

`bin/up` and `bin/update` are for setup and picking up code changes, not for
routine stop/start - re-running `bin/up` on an already-set-up stack is safe
(it no-ops what's already done) but far slower than just using Docker
Desktop's controls.

- **After `git pull`:** app code, views, routes, JS, and `etsource` branch
  switches reload automatically - most pulls need nothing further from the
  table above. `./bin/update` is only for a changed `Gemfile`/`package.json`
  or a new migration.
- **Run app commands (e.g. a Rails console):** in Docker Desktop,
  **Containers → service → Exec**, then run the command, e.g.
  `bin/rails console` on `etengine`.
- **View logs:** in Docker Desktop, **Containers → service → Logs**.

## Common problems

- **`bin/up` fails: port already in use.** Something is listening on
  3000/3001/3002/3005 - either the stack is already up (in which case there's
  nothing to do), or a native ETM install is running. Stop it and re-run.
- **`.env is missing variable(s)...` warning.** `.env` is created once from
  `.env.example` and never overwritten - a variable added to `.env.example`
  later doesn't reach your `.env` automatically. Add it by hand.
- **Login or redirect breaks.** Always open apps at
  `<service>.local.energytransitionmodel.com:<port>`, never bare
  `localhost:<port>` - the OAuth callback targets the configured host.
- **`bin/import-scenarios: command not found` / it silently finds no files.**
  Run it via `docker compose exec my-etm ...`, not directly on your host -
  there's no local Ruby install, and your host's `~/Downloads` isn't visible
  inside the container. See [step 5](#5-import-scenarios-optional).
- **`../etsource/.password is missing` warning.** Expected without the
  decryption password - some scenario calculations will fail; everything else
  works.
- **`bin/up` fails part-way through the build.** Usually disk space. `bin/up`
  prints Docker's disk usage before building, so check those numbers; reclaim
  space with `docker system prune` or raise the disk image size in Docker
  Desktop → Settings → Resources.

---

Contributing to ETLauncher, or editing a gem (merit, atlas, fever,
refinery, turbine, identity_rails)? See
[`docs/development.md`](docs/development.md).
