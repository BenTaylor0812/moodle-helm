# Upgrading Moodle and its plugins

How upgrades work in this chart, and what to do for each kind.

## How it works

The container's entrypoint does three things on every start, in order:

1. **rsync** Moodle core from the image onto the `moodle-code` volume
2. **rewrite `config.php`** from environment variables
3. **run `admin/cli/upgrade.php`** if the database already exists

`rsync` runs without `--delete`. That means core files are refreshed from the
image, while directories that exist only on the volume — your installed
plugins — are left alone. So a new image upgrades Moodle without destroying
plugins, and a plugin installed by hand survives every restart.

The trade-off: files *removed* upstream in a major Moodle upgrade stay behind
as orphans. Moodle tolerates this; *Site administration → Development → Code
integrity* lists them if you want to tidy up.

## Before any upgrade: back up

Both of these, every time. Upgrades change the database schema and are not
reversible without a backup.

```bash
kubectl exec -n moodle deploy/mariadb -- \
  sh -c 'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction moodle' \
  > moodle-db-$(date +%F).sql
```

```bash
kubectl exec -n moodle deploy/moodle -- \
  tar -czf - -C /var/www moodledata > moodledata-$(date +%F).tar.gz
```

The PVCs carry `helm.sh/resource-policy: keep`, so `helm uninstall` won't
delete your data — but that is not a backup, it's just a safety catch.

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

Look for the `<MOODLE version="X.Y">` block matching your target, and the
`<PHP version="..." level="required">` inside it. If it exceeds the
`FROM php:X.Y-apache` line in `moodle-docker/Dockerfile`, bump that too.

Known so far: Moodle 5.0 and 5.1 require PHP 8.2; Moodle 5.2 requires PHP 8.3.

Also check the required extension list in the same file against what the
Dockerfile installs. Moodle 5.1 needs `exif` and `soap` on top of the defaults,
and a new release may add more.

### 2. Add the new tarball

```bash
curl -L -o moodle-docker/moodle-versions/moodle-<new>.tgz <download-url>
```

Official downloads: https://download.moodle.org/releases/latest/

### 3. Build and push

```bash
cd moodle-docker
docker build --build-arg MOODLE_VERSION=<new> -t bentaylor0812/moodle:<new>_version1 .
docker push bentaylor0812/moodle:<new>_version1
```

Use a new tag every time. Never reuse a tag or push `:latest` — nodes cache by
tag, so a reused tag means some nodes run old code and you cannot tell which.

### 4. Deploy

```bash
helm upgrade moodle ./charts -n moodle -f values-office.yaml \
  --set moodle.image=docker.io/bentaylor0812/moodle:<new>_version1
```

Better: edit the image in your values overlay and commit it, so the deployed
version is recorded rather than living in shell history.

### 5. Watch it

```bash
kubectl logs -n moodle deploy/moodle -f
```

Expect, in order:

```
Upgrading Moodle core on volume: 5.1.3 (...) -> 5.2.1 (...)
Writing config.php (wwwroot=... sslproxy=...)
Moodle database present — applying any pending upgrade...
```

The schema upgrade is the slow part and scales with how much content you have.
The `startupProbe` allows ten minutes; raise `failureThreshold` in
`moodle-deployment.yaml` if a large site needs longer.

### 6. Verify, then purge caches

```bash
kubectl exec -n moodle deploy/moodle -- php /var/www/moodle/admin/cli/purge_caches.php
```

Check *Site administration → Notifications* for environment warnings, and
confirm the version under *Site administration → Server → Environment*.

### Rolling back

```bash
helm rollback moodle -n moodle
```

**This reverts the code, not the database.** Moodle's schema upgrade is
one-way. A rollback leaves old code against a newer schema, which Moodle will
refuse to run. To roll back properly you must restore the database dump as
well.

This is why step zero is the backup.

---

## Upgrading or installing plugins

Plugins live on the `moodle-code` volume, so they persist across restarts and
survive core upgrades. Two ways to manage them.

### Option A: install at runtime (current approach)

Fine for a lab or a site you administer directly.

**1. Check compatibility.** Every plugin page on
https://moodle.org/plugins lists which Moodle versions it supports. Installing
a plugin built for an older release will fail its version check, or worse,
half-install.

**2. Find the right directory.** Plugin type determines where it goes:

| Type | Directory |
|---|---|
| `auth_*` | `/var/www/moodle/public/auth/` |
| `mod_*` | `/var/www/moodle/public/mod/` |
| `block_*` | `/var/www/moodle/public/blocks/` |
| `theme_*` | `/var/www/moodle/public/theme/` |
| `local_*` | `/var/www/moodle/public/local/` |
| `tool_*` | `/var/www/moodle/public/admin/tool/` |

The unzipped directory name must match the plugin's component name exactly —
`auth_oidc` unpacks to a folder called `oidc` inside `public/auth/`.

**3. Install it:**

```bash
kubectl exec -n moodle deploy/moodle -- bash -c '
  cd /var/www/moodle/public/auth &&
  curl -L -o plugin.zip "<plugin-download-url>" &&
  unzip -q plugin.zip && rm plugin.zip &&
  chown -R www-data:www-data .
'
```

**4. Apply the database changes:**

```bash
kubectl exec -n moodle deploy/moodle -- \
  php /var/www/moodle/admin/cli/upgrade.php --non-interactive
```

**5. Purge caches:**

```bash
kubectl exec -n moodle deploy/moodle -- php /var/www/moodle/admin/cli/purge_caches.php
```

**Caveat:** a runtime-installed plugin exists only on that volume. Rebuild the
cluster or lose the PVC and it's gone, and nothing in this repo records that it
was ever installed. Keep a list.

### Option B: bake plugins into the image (recommended once settled)

Once you know which plugins you want permanently, put them in the image so the
deployment is reproducible.

Add to `moodle-docker/Dockerfile`, after the Moodle extraction:

```dockerfile
COPY plugins/auth/oidc.zip /tmp/
RUN unzip -q /tmp/oidc.zip -d /usr/src/moodle/public/auth/ && rm /tmp/oidc.zip
```

Then rebuild and deploy as a core upgrade. `rsync` places them on the volume,
and `upgrade.php` installs them. The repo now describes the full system, and a
fresh cluster comes up identically.

### Removing a plugin

Because `rsync` doesn't use `--delete`, deleting the files from the image is
not enough — the copy on the volume stays. Uninstall properly from
*Site administration → Plugins → Plugin overview*, which also removes its
database tables, then delete the directory:

```bash
kubectl exec -n moodle deploy/moodle -- rm -rf /var/www/moodle/public/auth/oidc
```

---

## A note on OAuth / Keycloak

The `plugins/oauth/` directory in this repo holds `auth_oidc` builds for Moodle
3.9 through 4.5. **None of them targets Moodle 5.x**, and the Dockerfile does
not install them.

Before adding `auth_oidc`, consider that **Moodle has OAuth 2 in core** —
*Site administration → Server → OAuth 2 services* — which works with a generic
OIDC provider such as Keycloak and needs no plugin at all. `auth_oidc` is
Microsoft's plugin, aimed at Entra ID; it has more features but is probably not
what a Keycloak integration needs.
