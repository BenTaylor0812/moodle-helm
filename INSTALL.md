# Installing Moodle into a new cluster

Written for deploying into a cluster you don't administer — an office or shared
cluster where you can create objects in your own namespace but can't change the
cluster's ingress controller, storage or admission policy.

## Prerequisites

Check these before you start. Most install failures are one of these missing.

| Requirement | How to check |
|---|---|
| Kubernetes 1.29+ | `kubectl version` |
| An ingress controller | `kubectl get ingressclass` |
| A StorageClass with ReadWriteOnce | `kubectl get storageclass` |
| Registry access to `docker.io` | the cluster's nodes must be able to pull |
| A hostname resolving to the ingress controller | ask whoever runs DNS |
| TLS: a cert-manager issuer **or** an existing TLS Secret | `kubectl get clusterissuer` |

If none is marked `(default)`, or you need a specific one, set `storageClass`
in your values overlay (step 4). Leave it empty to use the cluster default.

## 1. Get the code

```bash
git clone -b calude-help https://github.com/BenTaylor0812/moodle-helm.git
cd moodle-helm
```

## 2. Create a namespace

```bash
kubectl create namespace moodle
```

## 3. Create the two Secrets

Do this rather than putting passwords in a values file, so nothing sensitive
ends up committed.

```bash
kubectl create secret generic moodle-db -n moodle \
  --from-literal=password="$(openssl rand -base64 24)" \
  --from-literal=rootPassword="$(openssl rand -base64 24)"
```

The admin password you'll need to know, so set it deliberately:

```bash
read -rsp "Moodle admin password: " PW && echo && \
  kubectl create secret generic moodle-admin -n moodle \
  --from-literal=password="$PW" && unset PW
```

Record it somewhere before you forget — it's only used at first install, and
resetting it afterwards means a CLI call inside the pod.

## 4. Write a values overlay

Don't edit `charts/values.yaml`. Create a separate file so the chart stays
environment-neutral:

```bash
cat > values-office.yaml <<'EOF'
# Leave empty to use the cluster default; set it if none is default or you
# need a particular class.
storageClass: ''

moodle:
  image: docker.io/bentaylor0812/moodle:5.1.3_version4

ingress:
  enabled: true
  className: nginx            # match `kubectl get ingressclass`
  host: moodle.office.example.com
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: 512m
    # Whatever this cluster uses for certificates, e.g.
    # cert-manager.io/cluster-issuer: <their-issuer>
    # Omit entirely if tls.secretName already exists.
  tls:
    enabled: true
    secretName: moodle-tls
EOF
```

`wwwroot` is deliberately not set — the chart derives it from `ingress.host`
and the TLS setting, so Moodle's idea of its own URL cannot disagree with the
hostname users actually arrive on. That mismatch is the most common way to
break Moodle behind an ingress.

## 5. Check what will be created

```bash
helm template moodle ./charts -n moodle -f values-office.yaml | less
```

Confirm `MOODLE_WWWROOT` and `MOODLE_SSLPROXY` look right before installing.

## 6. Install

```bash
helm install moodle ./charts -n moodle -f values-office.yaml
```

## 7. Watch the first boot

```bash
kubectl get pods -n moodle -w
```

**First boot takes several minutes** while Moodle builds the database schema.
Moodle's code is already in the image, so there's no file copying — the wait is
entirely the install. A `startupProbe` allows up to ten minutes, so the pod is
not killed mid-install; don't intervene unless it exceeds that.

Follow what it's doing. The pod has two containers, so name the one you want:

```bash
kubectl logs -n moodle deploy/moodle -c moodle -f
```

You should see, in order: waiting for MariaDB, syncing Moodle core, writing
`config.php` with your wwwroot, then installing the database.

## 8. Verify

```bash
kubectl get pods,svc,ingress,pvc -n moodle
```

The Moodle pod should read `2/2` — the web container plus the cron sidecar.
Check cron is ticking over:

```bash
kubectl logs -n moodle deploy/moodle -c cron --tail=20
```

Failures in the first few minutes are expected while the install finishes; it
retries every 60 seconds.

Then visit your hostname. You want a clean padlock and the Moodle front page,
and you should be able to log in as `admin`.

## Troubleshooting

| Symptom | Cause |
|---|---|
| PVCs `Pending` | no default StorageClass — see Known gaps |
| `ImagePullBackOff` | nodes can't reach `docker.io`; you may need an internal mirror |
| `MOODLE_WWWROOT must be set` in logs | `ingress.host` empty and `moodle.wwwroot` unset |
| Infinite redirect on HTTPS | `sslproxy` not set — check `MOODLE_SSLPROXY` is `"true"` in the pod env |
| CSS/JS 404, page unstyled | wwwroot doesn't match the hostname you browsed to |
| `413 Request Entity Too Large` | ingress body-size annotation missing or too small |
| Moodle can't connect to the database | `moodle-db` Secret missing, or created after the pods started |
| Pod rejected by admission webhook | PodSecurityStandards — see Known gaps |
| Install seems to hang for minutes | normal on first boot; check logs before acting |

## Known gaps

Things this chart does **not** currently handle, which may matter in a cluster
you don't control:

**No resource requests or limits.** Clusters with a `LimitRange` or
`ResourceQuota` may reject the pods outright, or apply defaults that starve
Moodle.

**The container needs root at startup** to set ownership on the volumes. Under
a `restricted` PodSecurityStandard the pod will be refused. Check with
`kubectl get ns <namespace> -o yaml | grep pod-security`.

**Single replica only.** `moodledata` is ReadWriteOnce, so Moodle cannot be
scaled beyond one pod without RWX storage.

**Plugins require a rebuild.** Moodle's code ships in the image, so the
web-based plugin installer and Moodle's self-update prompts don't work — adding
a plugin means a new image. That's deliberate: it keeps the deployed code
identical to the repository. See `UPGRADING.md`.
