# ETLauncher — local logins

**Dev-only.** These are fixed, non-secret credentials for the local stack, seeded
into MyETM by `bin/seed-users`. They are defined in `.env` (from `.env.example`);
change them there and re-run `./bin/seed-users` to change them.

## MyETM logins

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@etm.local` | `etm-admin` |
| Regular user | `user@etm.local` | `etm-user` |

Use these to sign in to any app through MyETM (the OIDC provider).

## App URLs

Open each app at its **own `*.local.energytransitionmodel.com` host**. Add to `/etc/hosts`:

```
127.0.0.1  myetm.local.energytransitionmodel.com etmodel.local.energytransitionmodel.com etengine.local.energytransitionmodel.com collections.local.energytransitionmodel.com
```

| App | URL |
|-----|-----|
| ETEngine | https://etengine.local.energytransitionmodel.com |
| ETModel | https://etmodel.local.energytransitionmodel.com |
| MyETM | https://myetm.local.energytransitionmodel.com |
| Collections | https://collections.local.energytransitionmodel.com |
