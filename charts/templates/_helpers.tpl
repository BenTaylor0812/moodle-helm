{{/*
Moodle's $CFG->wwwroot — the URL Moodle believes it is served from.

Uses moodle.wwwroot when explicitly set; otherwise derives it from the ingress
host and whether TLS is enabled. Deriving it by default means the URL Moodle
advertises cannot disagree with the hostname users actually arrive on, which is
the most common way to break a Moodle deployment: redirects and asset URLs
point somewhere unreachable and the site appears broken while the ingress is
working perfectly.
*/}}
{{- define "moodle.wwwroot" -}}
{{- if .Values.moodle.wwwroot -}}
{{- .Values.moodle.wwwroot | trimSuffix "/" -}}
{{- else if .Values.ingress.enabled -}}
{{- printf "%s://%s" (ternary "https" "http" .Values.ingress.tls.enabled) .Values.ingress.host -}}
{{- else -}}
{{- fail "moodle.wwwroot must be set explicitly when ingress.enabled is false" -}}
{{- end -}}
{{- end -}}

{{/*
Whether to set $CFG->sslproxy.

True whenever Moodle advertises an https:// wwwroot, because in that case TLS
terminates upstream and the request arriving at the container is plain HTTP.
Without this, Moodle concludes the site is http://, disagrees with its own
wwwroot, and redirect-loops.

Derived from wwwroot rather than configured separately so the two cannot drift.
*/}}
{{- define "moodle.sslproxy" -}}
{{- if hasPrefix "https://" (include "moodle.wwwroot" .) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}

{{/*
The Moodle environment, defined once and used by every container that runs
Moodle code.

This has to be shared rather than set per-container: config.php reads its values
with getenv() at request time, so anything running a Moodle CLI script — the web
container, the cron container — needs the full environment or it cannot reach
the database.
*/}}
{{- define "moodle.env" -}}
- name: MOODLE_DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: moodle-db
      key: password
# Derived from ingress.host unless moodle.wwwroot overrides it.
- name: MOODLE_WWWROOT
  value: {{ include "moodle.wwwroot" . | quote }}
# Derived from the wwwroot scheme.
- name: MOODLE_SSLPROXY
  value: {{ include "moodle.sslproxy" . | quote }}
- name: MOODLE_SITE_FULLNAME
  value: {{ .Values.moodle.site.fullname | quote }}
- name: MOODLE_SITE_SHORTNAME
  value: {{ .Values.moodle.site.shortname | quote }}
- name: MOODLE_ADMIN_USER
  value: {{ .Values.moodle.admin.user | quote }}
- name: MOODLE_ADMIN_EMAIL
  value: {{ .Values.moodle.admin.email | quote }}
- name: MOODLE_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: moodle-admin
      key: password
{{- end -}}
