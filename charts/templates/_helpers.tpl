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
