# Upgrading Moodle and its plugins

How upgrades work in this chart, and what to do for each kind.

## How it works

**Moodle's code lives in the image, not on a volume.** Upgrading Moodle means
building a new image and deploying it. Nothing is copied onto persistent
storage at startup.

On every container start the entrypoint:

1. waits for MariaDB
2. writes `config.php` from environment variables
3. installs the database schema if it's empty, or applies any pending upgrade

Only **`moodledata`** and the **database** persist. That means the running code
is always exactly what the image contains — there's no volume accumulating
state that drifts between your lab and the office, and no orphaned files left
behind by an upgrade.

The consequence: **plugins must be baked into the image.** Anything installed
into the code directory at runtime is gone the moment the pod restarts.

## Before any upgrade: back up

Both of these, every time. Schema upgrades are not reversible without a backup.

```bash
kubectl exec -n moodle deploy/mariadb -- \
  sh -c 'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction moodle' \
  > moodle-db-$(date +%F).sql
```

```bash
kubectl exec -n moodle deploy/moodle -c moodle -- \
  tar -czf - -C /var/www moodledata > moodledata-$(date +%F).tar.gz
```

There's nothing to back up for the code — the image and this repository *are*
that backup, which is one of the better arguments for the immutable approach.

The PVCs carry `helm.sh/resource-policy: keep`, so `helm uninstall` won't
delete your data. That's a safety catch, not a backup.

---

## Upgrading Moodle core

### 1. Check the PHP requirement first

Each Moodle release raises its minimum PHP version, and the base image must
satisfy it. Read it from the release itself rather than guessing:

```bash
tar -xzf moodle-docker/moodle-versions/moodle-<new>.tgz \
  -O moodle/public/admin/environment.xml \
  | grep -B2 'PHP version' | tail -20
```

Look for the `<MOODLE version="X.Y">` block matching your target and the
`<PHP version="..." level="required">` inside it. If it exceeds the
`FROM php:X.Y-apache` line in `moodle-docker/Dockerfile`, bump that too.

Known so far: Moodle 5.0 and 5.1 require PHP 8.2; Moodle 5.2 requires PHP 8.3.

Check the required extension list in the same file against what the Dockerfile
installs. Moodle 5.1 needs `exif` and `soap` on top of the base image defaults,
and a new release may add more.

### 2. Add the new tarball

```bash
curl -L -o moodle-docker/moodle-versions/moodle-<new>.tgz <download-url>
```

Official downloads: https://download.moodle.org/releases/latest/

Keep the tarball in the repository rather than fetching at build time — the
build then works offline and reproduces identically in the office.

### 3. Build and push

```bash
cd moodle-docker
docker build --build-arg MOODLE_VERSION=<new> -t bentaylor0812/moodle:<new>_version1 .
docker push bentaylor0812/moodle:<new>_version1
```

Use a new tag every time. Never reuse a tag or push `:latest` — nodes cache by
tag, so a reused tag means some nodes run old code and you can't tell which.

### 4. Deploy

Edit `moodle.image` in your values overlay and commit it, so the deployed
version is recorded in git rather than living in someone's shell history:

```bash
helm upgrade moodle ./charts -n moodle -f values-office.yaml
```

### 5. Watch it

```bash
kubectl logs -n moodle deploy/moodle -c moodle -f
```

Expect, in order:

```
Waiting for MariaDB at mariadb:3306...
Moodle 5.2.1 (Build: ...) from image
Writing config.php (wwwroot=... sslproxy=...)
Moodle database present — applying any pending upgrade...
```

The schema upgrade is the slow part and scales with how much content you have.
The `startupProbe` allows ten minutes; raise `failureThreshold` in
`moodle-deployment.yaml` if a large site needs longer.

### 6. Verify, then purge caches

```bash
kubectl exec -n moodle deploy/moodle -c moodle -- php /var/www/moodle/admin/cli/purge_caches.php
```

Check *Site administration → Notifications* for environment warnings, and
confirm the version under *Site administration → Server → Environment*.

### Rolling back

```bash
helm rollback moodle -n moodle
```

**This reverts the code, not the database.** Moodle's schema upgrade is
one-way. A rollback leaves old code against a newer schema, which Moodle will
refuse to run. To roll back properly you must restore the database dump too.

This is why step zero is the backup.

---

## Installing or upgrading plugins

Plugins go in the image. There is no other durable route, because the code
directory isn't persistent.

### 1. Check compatibility

Every plugin page on https://moodle.org/plugins lists the Moodle versions it
supports. You can also read it straight from the zip:

```bash
unzip -p plugin.zip '*/version.php' | grep -E 'requires|supported|release'
```

`$plugin->requires` is a **minimum** Moodle version — a plugin built for an
older release will usually still be accepted by a newer Moodle. What stops
installation is `$plugin->supported`, which some plugins set as an upper bound.

Accepted isn't the same as working, though. Moodle 5.0 moved the web root into
`public/` and deprecated APIs along the way, so an older plugin may install and
then misbehave. Test it.

### 2. Add the zip to the repository

```
plugins/auth/auth_oidc.zip
```

Committing it keeps the build offline-capable and reproducible, same as the
Moodle tarball.

### 3. Add a block to the Dockerfile

Place it after the Moodle extraction and **before** the `chown`:

```dockerfile
COPY plugins/auth/auth_oidc.zip /tmp/
RUN unzip -q /tmp/auth_oidc.zip -d /var/www/moodle/public/auth/ \
 && rm /tmp/auth_oidc.zip \
 && test -f /var/www/moodle/public/auth/oidc/version.php
```

**That `test` line matters.** Moodle identifies a plugin by its directory name,
so `auth_oidc` must unpack to a folder called exactly `oidc`. Zips from
moodle.org usually get this right; GitHub archives usually don't, unpacking to
something like `moodle-auth_oidc-main/`. The assertion fails the build
immediately instead of leaving you with a confusing Moodle error later.

If the archive does unpack wrongly, rename during the build:

```dockerfile
RUN unzip -q /tmp/plugin.zip -d /tmp/x \
 && mv /tmp/x/* /var/www/moodle/public/auth/oidc \
 && rm -rf /tmp/x /tmp/plugin.zip
```

Where each plugin type belongs:

| Type | Directory |
|---|---|
| `auth_*` | `/var/www/moodle/public/auth/` |
| `mod_*` | `/var/www/moodle/public/mod/` |
| `block_*` | `/var/www/moodle/public/blocks/` |
| `theme_*` | `/var/www/moodle/public/theme/` |
| `local_*` | `/var/www/moodle/public/local/` |
| `tool_*` | `/var/www/moodle/public/admin/tool/` |
| `enrol_*` | `/var/www/moodle/public/enrol/` |
| `filter_*` | `/var/www/moodle/public/filter/` |

### 4. Build, push, deploy

Exactly as for a core upgrade. On the first start with the new image, the
entrypoint's `upgrade.php` call notices the new plugin and installs its
database tables. **No manual step.**

### Trying a plugin out without a rebuild

You can install into a running container, and it will work — until the pod
restarts, at which point it's gone:

```bash
kubectl exec -n moodle deploy/moodle -c moodle -- bash -c '
  cd /var/www/moodle/public/auth &&
  curl -L -o plugin.zip "<url>" &&
  unzip -q plugin.zip && rm plugin.zip &&
  chown -R www-data:www-data .
'
kubectl exec -n moodle deploy/moodle -c moodle -- \
  php /var/www/moodle/admin/cli/upgrade.php --non-interactive
```

Useful for a quick evaluation. Never for anything you want to keep — and note
the database tables persist after the files vanish, which leaves Moodle
complaining about a plugin that's missing from disk.

### Removing a plugin

Order matters. **Uninstall from Moodle first**, via
*Site administration → Plugins → Plugin overview*, which drops its database
tables. Then remove the `COPY`/`RUN` block from the Dockerfile, rebuild, and
deploy.

Removing it from the image without uninstalling leaves orphaned tables and
Moodle reporting a missing plugin.

---

## A note on OAuth / Keycloak

The `plugins/oauth/` directory holds `auth_oidc` builds for Moodle 3.9 through
4.5, and the Dockerfile does not install any of them.

Those builds would probably be *accepted* by Moodle 5.1 — `$plugin->requires`
is a minimum and they declare no upper bound — but they predate the `public/`
restructure in Moodle 5.0, so whether they work properly is untested.

Two things worth knowing before reaching for `auth_oidc`:

**Moodle has OAuth 2 in core** — *Site administration → Server → OAuth 2
services*, with a `custom` issuer type that works against a generic OIDC
provider such as Keycloak. No plugin, nothing to maintain across upgrades.

**`auth_oidc` does not do role mapping either.** It's a long-standing open
feature request. In Moodle, roles come from enrolment, not from the
authentication plugin — the chain is
`Keycloak group → Moodle cohort → cohort sync enrolment → role in a context`.
Whichever auth plugin you choose, something still has to manage cohort
membership. See `scripts/keycloak_to_moodle_csv.py` for the CSV route.
